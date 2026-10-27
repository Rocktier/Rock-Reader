/**
 * 阅读页（分页模式，M3）
 * 设计依据：docs/v1-design.md §5 / §6 / §8
 *
 * 快在哪（本页的性能骨架）：
 *  1. 整章**一次** layoutSync 拿全部行区间 → 切成页表（TextPaginator）；
 *  2. 页表按 layoutKey 缓存（PageCache）→ 命中时**翻页只是换 substring，零测量**；
 *  3. 只持当前章文本，不整本入内存。
 *
 * 交互（对齐 spec §8）：
 *  - 零常驻控件：正文之外只有一行页脚（等宽章名 + 页码）
 *  - 点屏幕中间 → 浮出上下细栏；点左右两侧 → 翻页
 *  - 横滑（PanGesture）→ 翻页；**淡入淡出 + 微小位移**，v1 不做仿真翻页
 *  - 目录 / 设置 都从浮层进入；设置返回时**按字符偏移复原位置**（切档位不跳页）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { curves, promptAction, router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { BookDb } from '../data/BookDb';
import { pushCardUpdate, saveCardLeftHint } from '../data/CardData';
import { bookPercentOf, chapterLeftText } from '../engine/stats/ReadStats';
import { ReaderPrefs, TTS_PERSON_DEFAULT } from '../data/ReaderPrefs';
import { BookRecord, BookmarkRow, ChapterRow, HighlightRow, ProgressSnapshot, ReadingProgress, SearchHitRow } from '../common/Types';
import { BookSource, createBookSource } from '../engine/parser/BookSource';
import {
  fontSizeFpOf,
  fontWeightOf,
  layoutKey,
  LayoutLevels,
  LEVEL_MAX,
  lineHeightRatioOf,
  marginVpOf,
  readingMarginOf,
  WEIGHT_MAX
} from '../common/LayoutStyle';
import { buildMarksExport } from '../engine/marks/MarkExport';
import { PageRange, PageTable, pageOfChar } from '../engine/paginator/PageTableBuilder';
import { LayoutBox, PageCache, Paginator } from '../engine/paginator/Paginator';
import { FontStore } from '../data/FontStore';
import { MIN_SESSION_MS, ReadSession } from '../engine/stats/ReadStats';
import { FontEntry } from '../common/FontCatalog';
import { TextPaginator } from '../engine/paginator/TextPaginator';
import { TtsEngine, TtsCallbacks } from '../engine/tts/TtsEngine';
import { Palette, paletteOf, themeLabel, THEME_AUTO, THEME_DARK, THEME_GREEN, THEME_LIGHT, THEME_SEPIA, ThemeName, resolveTheme } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';
import { RR_FS_TITLE, RR_FS_HEADING, RR_FS_BODY, RR_FS_LABEL, RR_FS_META, RR_FS_DIGIT, RR_FS_MICRO, RR_SP_SM, RR_SP_MD, RR_SP_LG, RR_SP_XL, RR_SP_2XL, RR_SP_3XL, RR_SP_4XL, RR_SP_5XL, RR_SP_6XL, RR_SP_VOID, RR_SP_TOP, RR_RADIUS_COVER } from '../theme/RrTokens';

interface ReaderParams {
  bookId: string;
}

/**
 * 目录数据源 —— LazyForEach 要求实现 IDataSource。
 *
 * 为什么换成懒加载：目录可能有几千章（`task_plan` 里按"三千章"量级设计），
 * 一次性把每章都建成 ListItem 会明显卡顿；改成懒加载后只渲染可视区那几行。
 */
class ChapterDataSource implements IDataSource {
  private list: ChapterRow[] = [];
  private listeners: DataChangeListener[] = [];

  /** 换数据（切书 / 搜索过滤）后必须调它，否则 LazyForEach 不会刷新 */
  update(list: ChapterRow[]): void {
    this.list = list;
    for (let i: number = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  totalCount(): number {
    return this.list.length;
  }

  getData(index: number): ChapterRow {
    return this.list[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }
}

/**
 * 目录项 —— 标 **@Reusable**：长列表滚动时复用节点，省掉反复创建/销毁的开销
 * （配合上面的 LazyForEach：一个管"只渲染可见的"，一个管"滚出去的别扔"）。
 *
 * 为什么不直接传 `Palette`：ArkTS 的 `@Prop` 只支持基础类型，而 Palette 是 interface，
 * 所以把用到的几个色值逐个传进来（@Prop 会自动跟随父组件更新，不必写 aboutToReuse）。
 */
@Reusable
@Component
struct ChapterItem {
  @Prop title: string = '';
  @Prop index: number = 0;
  @Prop current: boolean = false;
  @Prop textColor: string = '';
  @Prop text2Color: string = '';
  /** 当前章的强调色竖条（原家族红，2026-10-10 随原生化改为官方系统蓝） */
  @Prop accentColor: string = '';
  private onJump: (index: number) => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(RR_FS_BODY)
        .fontColor(this.current ? this.textColor : this.text2Color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 无障碍：屏幕阅读器要能读出章名（AGC 审核会查）
        .stateStyles({ pressed: { opacity: 0.6 } })
        .accessibilityText(this.title)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_2XL, bottom: RR_SP_2XL })
    // 当前章 = 左侧强调色竖条（原家族红 → 官方系统蓝）。原来的序号列去掉了：它是"第几个条目"，
    // 与章名里作者写的「第N章」并列时数字对不上（版权页/序章也占号），真机反馈 #4 —— 只看数字必被误导；
    // 真实的位置指示由页脚 16/182 承担。
    .border({
      width: { left: 3 },
      color: this.current ? this.accentColor : Color.Transparent
    })
    .onClick(() => this.onJump(this.index))
  }
}

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 页脚高度（vp）：正文可用高度要扣掉 */
const FOOTER_VP: number = 30;
/**
 * topBar 朗读入口喇叭图标边长（vp）—— SVG 三态（待机 / 暂停 / 播放）。
 * 28vp：整图标 glyph 约 20vp，与返回键「‹」的字形同量级。
 * （2026-10-19 党哥反馈 20vp 太小，且与相邻章号数字没有居中对齐。）
 */
const SPEAKER_ICON_VP: number = 28;
/** 正文顶部留白（vp） */
const HEADER_VP: number = 34;
/** 每次翻页落一次进度太重 → 章内每 5 页落一次；切章 / 退出必落 */
const PERSIST_EVERY_PAGES: number = 5;
/** 翻页动画时长（ms）——短促，对齐 spec「动效 ≈0.2s」 */
const FADE_OUT_MS: number = 90;
const FADE_IN_MS: number = 130;
/** 淡入淡出的位移量（vp） */
const FADE_SHIFT_VP: number = 18;
/** 跟手翻页：松手时判定翻页的最小拖拽距离（屏宽倍数）—— 跟手比"轻滑"更笃定 */
const DRAG_TURN_RATIO: number = 0.25;
/** 跟手翻页：快扫速度阈值（vp/s），轻扫一下也能翻 */
const DRAG_TURN_VELOCITY: number = 900;
/** 到头了（首页往前 / 末页往后）：拖不动，只给 35% 位移当橡皮筋 */
const DRAG_RESIST: number = 0.35;
/** 回弹 / 当前页滑出 / 新页淡入的时长（ms） */
const DRAG_BACK_MS: number = 200;
const DRAG_OUT_MS: number = 130;
const DRAG_IN_MS: number = 150;
/** 目录抽屉宽度（占屏宽比例）：不铺满，右侧留白透出正文，便于边看边选章 */
const TOC_PANEL_WIDTH: string = '72%';
/** 抽屉滑入的起始位移（vp）与动画时长（ms）；两个抽屉（目录/设置）共用同一套时长 */
const TOC_SLIDE_VP: number = 320;
const SETTINGS_SLIDE_VP: number = 460;
const PANEL_ANIM_MS: number = 220;
/**
 * 设置抽屉顶部「点外部关闭」带的最小高度（vp）。
 *
 * ⚠️ 2026-10-23 复评实测补：原设计给关闭带 layoutWeight(1)，但面板内容
 * （4 行档位 + 主题/字体/音色/语速 + 更多设置）总高超过抽屉本身时，
 * 关闭带被挤成 **0 像素** —— 面板铺满全屏且点上面关不掉，只能靠系统返回。
 * 改成固定最小高度 + 面板内部 Scroll 收缩，两条关闭路（点带 / ×）都常在。
 */
const SETTINGS_STRIP_VP: number = 88;

@Entry
@Component
struct Reader {
  @State palette: Palette = paletteOf(THEME_DARK);
  @State title: string = '';
  @State chapterTitle: string = '';
  @State chapterIndex: number = 0;
  @State chapterCount: number = 0;
  /** 各章已确认字数（下标 = 章序，未量过 = 0）。见 computeBookPercent 的口径说明。 */
  private charCounts: number[] = [];
  /** 字数普查进行中标记（防重复进入） */
  private surveying: boolean = false;
  @State pageIndex: number = 0;
  @State pageCount: number = 0;
  @State pagePercent: number = 0;
  @State bookPercent: number = 0;
  @State pageText: string = '';
  @State showMenu: boolean = false;
  @State showToc: boolean = false;
  /** 设置抽屉（P11-2：就地改排版、正文实时跟着变）；与目录抽屉互斥 */
  @State showSettings: boolean = false;
  /** 抽屉里显示的档位（与 prefs 同步；改一下即重排 → 实时预览） */
  @State levels: LayoutLevels = { fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3, fontWeightLevel: 1 };
  /** 目录搜索词；空 = 展示全部章节 */
  @State tocQuery: string = '';
  /** 目录当前展示的章节（搜索时为子集，**index 仍是原章号**，跳转与高亮不受影响） */
  @State tocFiltered: ChapterRow[] = [];
  @State hint: string = '';
  @State loading: boolean = true;
  /**
   * 不能叫 opacity —— ArkUI 的 CustomComponent 自带 opacity(value) 属性方法，
   * 同名字段会报 10505001（Type 'number' is not assignable to ...CommonAttribute）。
   */
  @State pageOpacity: number = 1;
  @State shiftX: number = 0;
  /** 跟手拖拽的实时位移（vp）：0 = 静止；与 shiftX 叠加后作用于正文 */
  @State dragX: number = 0;
  /** 渲染参数：必须与排版参数同源（唯一真源 = common/LayoutStyle） */
  @State fontSizeFp: number = 18;
  @State lineHeightVp: number = 34.2;
  /** 字重数值（400/500/700），来自档位表 —— 测量与渲染必须共用同一个值 */
  @State fontWeightValue: number = 400;
  @State marginVp: number = 20;
  /** '' = 系统默认字体；非空时渲染与测量都必须用同一个族名 */
  @State fontFamily: string = '';

  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();
  private book: BookRecord | null = null;
  private chapters: ChapterRow[] = [];
  private source: BookSource | null = null;
  private chapterText: string = '';
  private pages: PageRange[] = [];
  private fontStore: FontStore | null = null;
  /** 当前字体（下载字体）在沙箱里的路径；系统字体为 '' */
  private fontPath: string = '';
  private paginator: Paginator = new TextPaginator();
  private cache: PageCache = new PageCache(4);
  /** 目录列表的滚动器：打开目录时用它把当前章定位到中间 */
  private tocScroller: Scroller = new Scroller();
  /** 目录数据源（懒加载）；`tocFiltered` 仍保留，只用来判空 */
  private tocSource: ChapterDataSource = new ChapterDataSource();
  private theme: ThemeName = THEME_DARK;
  /**
   * A2（2026-10-25）：**生效主题**。用户选 'auto' 时按小时在晴昼/子夜间解析，
   * 色板与系统状态栏一律读这个，不读 this.theme（抽屉选中态才看 this.theme）。
   */
  private activeTheme: ThemeName = THEME_DARK;
  /** A1：这本书有没有排版覆盖（抽屉「恢复全局」入口的显隐） */
  @State private hasOverride: boolean = false;
  /** A3：本章剩余阅读文案（'本章还剩约 12 分钟'；空 = 不显示） */
  @State private chapterLeftText: string = '';
  private currentKey: string = '';
  /** 上一次取文本时用的加工设置：变了就必须重新取章（净化/简繁会改正文） */
  private purifyOn: boolean = true;
  private convertMode: string = 'off';
  /** 阅读会话（统计用）：进入某章的开始时间与章号；-1 表示没有进行中的会话 */
  private sessionStartAt: number = 0;
  private sessionChapter: number = -1;
  private viewWidthVp: number = 0;
  private viewHeightVp: number = 0;
  /** 本轮手势是否已进入跟手态（按下时若开着菜单/目录，则整轮忽略） */
  private dragging: boolean = false;
  /** 上一次排版时的视口（vp）；用于识别"旋转/分屏/字号缩放"导致的尺寸变化 */
  private laidOutWidthVp: number = 0;
  private laidOutHeightVp: number = 0;
  private areaReady: boolean = false;
  /** 首屏：拿到视口尺寸后再排版 */
  private pendingChapter: number = 0;
  private pendingOffset: number = 0;
  private pagesSincePersist: number = 0;
  /** 章加载失败态：true 时 persistProgress 禁止落库（防进度被清成 0，审查报告 B2） */
  private failed: boolean = false;

  // ---- 三件套（2026-10-22 评审 P0-2：书签 / 摘录 / 全文搜索）----
  /** 本书全部书签（进书加载一次；增删后重拉） */
  @State bookmarks: BookmarkRow[] = [];
  /** 本书全部摘录（同上） */
  @State highlights: HighlightRow[] = [];
  /** 抽屉页签：'toc' 目录 | 'marks' 书签+摘录 | 'search' 全文搜索 */
  @State drawerTab: string = 'toc';
  /** ⚑ 点击后的落签脉冲（弹一下 = "签上了"，与私记的钤印手感同源） */
  @State markKick: boolean = false;
  /** 摘录面板是否开着（长按正文唤起） */
  @State showHighlight: boolean = false;
  /** 摘录面板里的注（用户输入） */
  @State highlightNote: string = '';
  /** 摘录的原文快照（开面板时定格） */
  private highlightExcerpt: string = '';
  private highlightStart: number = 0;
  private highlightEnd: number = 0;
  /** 全文搜索词与命中 */
  @State searchQuery: string = '';
  @State searchHits: SearchHitRow[] = [];
  @State searchBusy: boolean = false;
  /** 全文搜索防抖 */
  private searchTimer: number = -1;

  // ---- 朗读（TTS，2026-10-17 加；2026-10-18 改章级）----
  /**
   * 引擎单例跨 Reader 页生命周期复用（aboutToDisappear 才 shutdown）。
   * 能力探测在 aboutToAppear 触发；探测失败 → ttsSupported 保持 false
   * → 入口不渲染（用户完全感知不到）。
   */
  private tts: TtsEngine = TtsEngine.shared();
  /** 设备支持 TTS（探测结论）；false = 隐藏全部朗读入口 */
  @State ttsSupported: boolean = false;
  /** 朗读会话激活（页脚显示播放条替换章名/页码） */
  @State speakActive: boolean = false;
  /** 当前音色 person（设置面板选中态；试听失败自动回退默认） */
  @State ttsPerson: number = TTS_PERSON_DEFAULT;
  /** 朗读语速（设置面板选中态；与 prefs/引擎三方同源） */
  @State ttsSpeed: number = 1.0;
  /** 暂停中（继续/暂停 文字切换） */
  @State speakPaused: boolean = false;
  /** begin 已发起但首段未开播的瞬态（createEngine 异步） */
  @State speakPreparing: boolean = false;
  /** 播放条进度文案：章级朗读 = 章内百分比（如 '32%'）；准备中为 '准备中' */
  @State speakProgress: string = '';
  /** 队列当前载入的章序号（≠ chapterIndex = 跨章了，showPage 时须重载） */
  private speakChapterIndex: number = -1;
  /** 位置同步翻页标记：定时器驱动的 showPage 不重载朗读（纯视觉跟随） */
  private speakSyncing: boolean = false;
  /** 位置跟踪定时器 id（-1 = 未运行；speakActive 期间每 1s 报一次章内偏移） */
  private speakTimer: number = -1;
  /** 朗读定时档位（分钟）：0=关，循环 15→30→60→0（页脚播放条按钮切换） */
  @State sleepMin: number = 0;
  /** 定时剩余秒数：播放中每秒递减（暂停时 tick 提前返回，倒计时自然冻结），到 0 停读 */
  @State sleepLeft: number = 0;
  /** 播放/暂停的一拍即走脉冲（topBar 喇叭与页脚文字共用；两段式，见 kickSpeak） */
  @State private speakKick: boolean = false;
  /** 音色下载中（person；0 = 无）—— chip 上显示进度，2026-10-23 复评补齐 */
  @State private voiceBusyPerson: number = 0;
  /** 音色「确认下载」态（person；0 = 无）：两击确认的第一击，防误触 */
  @State private voiceArmedPerson: number = 0;
  /** 音色下载进度（-1 = 未知/未开始） */
  @State private voicePct: number = -1;

  aboutToAppear(): void {
    // 下载的字体**每次启动都要重新注册**（registerFont 只在进程内存活，不持久化）
    const store: FontStore = new FontStore(this.getUIContext().getHostContext() as Context);
    this.fontStore = store;
    this.registerLocalFonts(store);
    this.initTts();
    this.init();
  }

  /** 朗读初始化：挂回调 + 探测能力。探测失败（模拟器/低端机）= 入口不出现，零感知 */
  private initTts(): void {
    const tts: TtsEngine = this.tts;
    this.ttsSpeed = this.prefs.getTtsSpeed();
    tts.setSpeed(this.ttsSpeed);
    this.ttsPerson = this.prefs.getTtsPerson();
    tts.setPerson(this.ttsPerson);
    // ArkTS 坑（2026-10-17 实测）：对象字面量的**属性值为箭头函数表达式**时会踩
    // arkts-no-untyped-obj-literals（类型推导失效）；先用显式函数类型变量接住，再作属性值。
    // （方法语法 onXxx(): void {} 也可过，但闭包要抓 this —— 方法内 this 指向字面量本身，不可用。）
    const onSegStart: (index: number, total: number, charOffset: number) => void =
      (index: number, total: number, charOffset: number): void => {
        this.speakPreparing = false;
        this.speakPaused = false;
        this.speakActive = true;
        this.speakProgress = this.chapterPercent(charOffset);
        this.startSpeakTimer();
      };
    const onAllDone: () => void = (): void => {
      // 整章读完：能翻页就翻（跨章后 openChapter → showPage 会重载新章续读，
      // 见 showPage 尾部），全书末章则收工。同章内不存在"读完还有剩页"
      // （段覆盖全章文本，最后一段结束 = 章尾）。
      const canForward: boolean = this.pageIndex < this.pageCount - 1
        || this.chapterIndex < this.chapterCount - 1;
      if (canForward) {
        this.turnPage(1);
      } else {
        this.speakActive = false;
        this.speakPaused = false;
        this.speakProgress = '';
        this.stopSpeakTimer();
      }
    };
    const onErr: (msg: string) => void = (msg: string): void => {
      this.speakPreparing = false;
      this.speakActive = false;
      this.speakPaused = false;
      this.speakProgress = '';
      this.stopSpeakTimer();
      // 音色试听失败（如凌飞哲未下载 → createEngine 1002300003）：
      // 选中态/prefs/引擎全部回退默认音色 —— 别把用户卡在坏选项上，
      // 且给一句明确提示（静默失败最难排查）。
      if (this.ttsPerson !== TTS_PERSON_DEFAULT) {
        this.ttsPerson = TTS_PERSON_DEFAULT;
        this.prefs.setTtsPerson(TTS_PERSON_DEFAULT);
        this.tts.setPerson(TTS_PERSON_DEFAULT);
        this.hint = '该音色暂不可用，已切回聆小珊';
        return;
      }
      this.hint = msg.length > 0 ? msg : '朗读出错，请重试';
    };
    const cbs: TtsCallbacks = new TtsCallbacks();
    cbs.onSegmentStart = onSegStart;
    cbs.onAllDone = onAllDone;
    cbs.onError = onErr;
    tts.setCallbacks(cbs);
    tts.probe((supported: boolean) => {
      this.ttsSupported = supported;
      hilog.info(DOMAIN, TAG, 'tts probe: supported=%{public}s', String(supported));
    });
  }

  /** 把已下载字体注册进 ArkUI（渲染用）；测量端由 TextPaginator 用文件路径单独挂 */
  private registerLocalFonts(store: FontStore): void {
    // 内置字体先就位（首次启动从包内复制到沙箱，之后幂等为空操作）
    store.syncBuiltin();
    const list: FontEntry[] = store.downloaded();
    if (list.length === 0) {
      hilog.info(DOMAIN, TAG, 'registerFont: no downloaded fonts');
      return;
    }
    for (let i: number = 0; i < list.length; i++) {
      // registerFont 必须用 file:// uri（裸路径静默失败 —— 2026-09-22 字体切换不生效的根因）
      const path: string = store.uriOf(list[i]);
      try {
        this.getUIContext().getFont().registerFont({
          familyName: list[i].familyName,
          familySrc: path
        });
        // 成功也要记：定位"字体切换不生效"时，成败本身就是最关键的判据
        hilog.info(DOMAIN, TAG, 'registerFont OK: %{public}s -> %{public}s', list[i].familyName, path);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'registerFont FAILED: %{public}s path=%{public}s err=%{public}s',
          list[i].familyName, path, JSON.stringify(e));
      }
    }
  }

  onPageShow(): void {
    // 从独立设置页返回：主题/档位/字体可能变了
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.prefs.reload();
    // 回前台要**重开计时会话**（审查报告 B8）：onPageHide 已把 sessionStartAt 清 0，
    // 章内翻页不经过 openChapter —— 不重开的话，锁屏/接电话回来后的阅读时长全部丢失
    if (this.sessionStartAt === 0 && this.sessionChapter >= 0) {
      this.sessionStartAt = Date.now();
    }
    // **字体可能刚下载完** —— registerFont 只在进程内/本 UIContext 存活，
    // aboutToAppear 那次注册时字体还不存在；而设置页自己的注册不影响阅读页
    // （实测：下载后回来选楷体，正文毫无变化 —— 就是漏了这次补注册）。幂等，重复调用无害。
    if (this.fontStore === null) {
      this.fontStore = new FontStore(this.getUIContext().getHostContext() as Context);
    }
    this.registerLocalFonts(this.fontStore);
    this.applyPrefsToLayout();
    // 语速偏好可能刚在设置页改过（设置页改语速是期二 UI；此处先接上，成本 0）
    this.tts.setSpeed(this.prefs.getTtsSpeed());
    // 音色偏好同步（设置里试听失败回退过 prefs；此处以 prefs 为准对齐引擎）
    this.ttsPerson = this.prefs.getTtsPerson();
    this.tts.setPerson(this.ttsPerson);
    // 回前台续听（2026-10-23 复评）：onPageHide 暂停后原来**不自动恢复**，
    // 用户每次切回本页都要手点「继续」。现在暂停态且引擎仍是 paused 时自动续。
    // 边界说明：锁屏/后台持续播放在无 AVSession 前维持「即停」策略（期二），
    // 这里只消灭「回前台还要多点一下」的摩擦，不冒充后台播放。
    if (this.speakActive && this.speakPaused && this.tts.state === 'paused') {
      this.tts.resume();
      this.speakPaused = false;
      this.speakPreparing = true;
      this.startSpeakTimer();
    }
    // 从独立设置页返回：浮层全部复位（审查报告 B23 —— 菜单卡在开启态）
    this.showMenu = false;
    this.showToc = false;
    this.showSettings = false;
  }

  /**
   * 把 prefs 的档位/主题/字体反映到当前页面；**变了才重排**，且按字符偏移复原位置（切档位不跳页）。
   *
   * 两个调用方：
   *   ① 从独立设置页返回（onPageShow）
   *   ② **阅读页内的设置抽屉**改档位（P11-2：边看边调，正文实时跟着变）
   * 两处共用同一段逻辑，避免"抽屉改了不生效 / 两边行为不一致"。
   */
  /**
   * A2（2026-10-25）：把「用户选的主题」解析成「当前生效的主题」落到色板/系统栏。
   * auto 档按小时在晴昼/子夜间切 —— 阅读页每翻一页（showPage）顺带调一次，
   * 夜里读到跨 18:30 自动转夜，不用读者手动切。开销：一次 if + 偶尔一次换色板。
   */
  private syncTheme(): void {
    const effective: ThemeName = resolveTheme(this.theme, new Date().getHours());
    if (effective !== this.activeTheme) {
      this.activeTheme = effective;
      this.palette = paletteOf(effective);
      applyThemeToSystem(this.getUIContext().getHostContext() as Context, effective);
    }
  }

  private applyPrefsToLayout(): void {
    const bookId: string = this.book === null ? '' : this.book.id;
    const theme: ThemeName = this.prefs.effectiveTheme(bookId);
    if (theme !== this.theme) {
      this.theme = theme;
    }
    this.syncTheme();
    this.hasOverride = this.prefs.hasBookOverride(bookId);
    const family: string = this.prefs.effectiveFamily(bookId);
    if (family !== this.fontFamily) {
      this.fontFamily = family;
      this.fontPath = this.fontStore === null ? '' : this.fontStore.uriForFamily(family);
    }
    hilog.info(DOMAIN, TAG, 'applyPrefs: family=[%{public}s] path=[%{public}s] key=%{public}s',
      this.fontFamily, this.fontPath, this.currentKey);
    // 抽屉里显示的档位跟着走（无论是否触发重排）
    this.levels = this.prefs.effectiveLevels(bookId);
    if (!this.areaReady || this.chapterCount === 0 || this.book === null) {
      return;
    }
    // 档位 / 字体 / 视口任一变化都要重排；位置按字符偏移复原（切档位不跳页）
    const next: string = this.boxOf(this.prefs.getLevels()).signature;
    // 净化 / 简繁变化会改正文内容 → 不能只重排，必须重新取一次章文本
    const textChanged: boolean =
      this.prefs.isPurifyOn() !== this.purifyOn || this.prefs.getConvertMode() !== this.convertMode;
    if (next !== this.currentKey || textChanged) {
      const keep: number = this.pages.length > 0 ? this.pages[this.pageIndex].start : 0;
      this.openChapter(this.chapterIndex, keep);
    }
  }

  onPageHide(): void {
    this.persistProgress(true);
    this.flushSession();
    // B1：离开阅读页 = 不再「正在读」，清标记（书架页据此判断卡片点击是否重复 push）
    AppStorage.setOrCreate('readerOpenBook', '');
    // 回后台暂停朗读（后台/锁屏播放是期二 AVSession 的事，一期从简：停在这里）
    if (this.speakActive) {
      this.tts.pause();
      this.speakPaused = true;
    }
  }

  aboutToDisappear(): void {
    this.persistProgress(true);
    this.flushSession();
    this.stopSpeakTimer();
    // 无条件 shutdown（幂等）：speakActive 时要停播；仅探测过没开读时，
    // probe 留下的引擎也必须释放（否则进程内常驻音频资源）
    this.tts.shutdown();
    this.speakActive = false;
    this.speakPaused = false;
    this.speakProgress = '';
    if (this.source !== null) {
      this.source.release();
    }
    this.cache.clear();
  }

  // ------------------------------------------------------------------
  // 初始化与排版
  // ------------------------------------------------------------------

  private async init(): Promise<void> {
    try {
      const params = this.getUIContext().getRouter().getParams() as ReaderParams;
      // B1：标记「正在读这本」—— 书架页据此判断卡片点击是否重复 push（同本书直接前台化）
      AppStorage.setOrCreate('readerOpenBook', params.bookId);
      this.prefs.open(this.getUIContext().getHostContext() as Context);
      // A1：这本书的覆盖优先、全局兜底（党哥 2026-10-25 拍板「仅这一本」）
      this.theme = this.prefs.effectiveTheme(params.bookId);
      this.levels = this.prefs.effectiveLevels(params.bookId);
      this.hasOverride = this.prefs.hasBookOverride(params.bookId);
      this.syncTheme();

      await this.db.open(this.getUIContext().getHostContext() as Context);
      const book: BookRecord | null = await this.db.getBook(params.bookId);
      if (book === null) {
        this.hint = '找不到这本书';
        this.loading = false;
        return;
      }
      this.book = book;
      this.title = book.title;
      this.source = createBookSource(book, this.prefs);

      this.fontFamily = this.prefs.effectiveFamily(book.id);
      this.fontPath = this.fontStore === null ? '' : this.fontStore.uriForFamily(this.fontFamily);
      this.chapters = await this.db.listChapters(book.id);
      this.chapterCount = this.chapters.length;
      // 已量过字数的章节（下标 = 章序，未量 = 0）；全书进度按真实字数算的真值来源
      this.charCounts = await this.db.loadCharCounts(book.id);
      if (this.charCounts.length !== this.chapterCount) {
        this.charCounts = [];
      }
      if (this.chapterCount === 0) {
        this.hint = book.format === 'epub' ? '这本书的目录解析失败' : '这本书没有解析出章节';
        this.loading = false;
        return;
      }
      const progress: ReadingProgress | null = await this.db.getProgress(book.id);
      this.pendingChapter = progress === null ? 0 : Math.min(progress.chapterIndex, this.chapterCount - 1);
      this.pendingOffset = progress === null ? 0 : progress.charOffset;
      // 三件套数据进书即拉（书签/摘录是这本书的常驻行李，不是要用才找）
      await this.reloadMarks();
      this.loading = false;
      if (this.areaReady) {
        this.openChapter(this.pendingChapter, this.pendingOffset);
        // 后台补一次各章字数普查 → 全书进度按真实字数算（fire-and-forget，不挡打开）
        this.surveyChars();
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'reader init failed: %{public}s', JSON.stringify(e));
      this.hint = '打开失败';
      this.loading = false;
    }
  }

  /** 由档位 + 视口算出这一套排版参数（**唯一真源**：测量端与渲染端都从这里取数） */
  private boxOf(levels: LayoutLevels): LayoutBox {
    // 字号先取 fp，再换 px —— 两个单位同时放进 box，渲染端就不必自己再查一次档位表
    const fontSizeFp: number = fontSizeFpOf(levels.fontSizeLevel);
    const fontSizePx: number = this.getUIContext().fp2px(fontSizeFp);
    const lineHeightPx: number = fontSizePx * lineHeightRatioOf(levels.lineHeightLevel);
    // P0-5 平板版心（2026-10-22）：行宽按「最多 MAX_LINE_CHARS 个字」封顶 ——
    // 平板满屏一行 40+ 字，逐行扫视必丢行（可读性硬伤）。封顶超出部分折进
    // 等效边距（正文居中），手机竖屏到不了封顶、行为与旧版完全一致。
    // 判定在 LayoutStyle.readingMarginOf（纯逻辑，CI 有单测守门）；
    // 测量 widthPx 与渲染 padding 同源于此，断行不会分叉。
    const marginVp: number = readingMarginOf(this.viewWidthVp, marginVpOf(levels.marginLevel), fontSizeFp);
    const widthPx: number = this.getUIContext().vp2px(Math.max(1, this.viewWidthVp - marginVp * 2));
    const heightPx: number = this.getUIContext().vp2px(Math.max(1, this.viewHeightVp - FOOTER_VP - HEADER_VP));
    return {
      fontSizeFp: fontSizeFp,
      fontSizePx: fontSizePx,
      lineHeightPx: lineHeightPx,
      widthPx: widthPx,
      heightPx: heightPx,
      fontFamily: this.fontFamily,
      fontPath: this.fontPath,
      fontWeight: fontWeightOf(levels.fontWeightLevel),
      marginVp: marginVp,
      signature: layoutKey(levels, fontSizePx, lineHeightPx, widthPx, this.fontFamily)
    };
  }

  /**
   * 单章失败时的统一善后：**必须清掉上一章的残留**。
   * 不清的话会出现最难查的一类现象：章名/页码已换成新章，正文却还是上一章的内容，
   * 而且还能继续翻页（页表是旧的）。
   */
  private failChapter(message: string): void {
    // 失败态标记：persistProgress 看到它就**禁止落库** ——
    // 否则 pages=[] 会让 offset 落成 0，把用户真实进度覆盖成"章首"（审查报告 B2）
    this.failed = true;
    this.hint = message;
    this.pages = [];
    this.pageCount = 0;
    this.pageText = '';
    this.pageIndex = 0;
    this.pagePercent = 0;
  }

  /** 记一条阅读会话（短于阈值的不记：翻目录误触不该污染统计） */
  private flushSession(): void {
    const started: number = this.sessionStartAt;
    const chapter: number = this.sessionChapter;
    this.sessionStartAt = 0;
    this.sessionChapter = -1;
    const book: BookRecord | null = this.book;
    if (book === null || started <= 0 || chapter < 0) {
      return;
    }
    const now: number = Date.now();
    if (now - started < MIN_SESSION_MS) {
      return;
    }
    const s: ReadSession = { bookId: book.id, chapterIndex: chapter, startAt: started, endAt: now };
    this.db.addSession(s).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'save session failed: %{public}s', e.message);
    });
  }

  /** 打开某章并定位到某个字符偏移（内部会按签名查缓存，命中则不重排） */
  /**
   * 全书进度：按**真实字数**算，而不是「第几章 ÷ 总章数」。
   *
   * 为什么不能按章数：那等于假设每章一样长。实测《暗恋·橘生淮南》100 章 39.3 万字，
   * 读到第 7 章 2/3 时按章算是 8.67%，按字数真实只有 4.66% —— 虚高近一倍，
   * 因为前面夹着「版权信息」「序章」这类几百字的短章，前段失真最厉害。
   *
   * 难点：EPUB 导入阶段刻意**不读正文**（否则导入 = 解压上百个 HTML），
   * 所以导入时根本拿不到每章字数 —— chapters.start_char/end_char 对 EPUB 恒为 0，
   * 想在建库时一次性把全书字数索引建好也无从下手。
   *
   * 解法：**读到哪、算到哪**。每展开一章就把它真实字数回填 chapters.char_count
   * （此刻整章全文已在内存，白量）；没读过的章用「已确认章的平均字数」外推。
   * 于是第一眼就有合理估值，越读越准，读过一遍后完全精确。
   * 存量用户的书不需要重新导入 —— 重读哪一章哪一章自动补上。
   */
  private computeBookPercent(): number {
    return bookPercentOf(this.charCounts, this.chapterCount, this.chapterIndex, this.pagePercent);
  }

  /**
   * 回填本章真实字数（内存 + 落库）。
   * 只写未知项：已量过就不动 —— 净化/简繁会改变 `text` 内容，若每次按当前文本覆盖，
   * 用户拨一下开关进度就会跟着抖，这是不能接受的。
   */
  private learnChapterChars(index: number, count: number): void {
    if (index < 0 || index >= this.chapterCount || count <= 0) {
      return;
    }
    if (this.charCounts.length !== this.chapterCount) {
      const fresh: number[] = [];
      for (let i: number = 0; i < this.chapterCount; i++) {
        fresh.push(0);
      }
      this.charCounts = fresh;
    }
    if (this.charCounts[index] > 0) {
      return;
    }
    this.charCounts[index] = count;
    if (this.book !== null) {
      this.db.saveChapterCharCount(this.book.id, index, count).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'saveChapterCharCount failed: %{public}s', JSON.stringify(e));
      });
    }
  }

  /**
   * 后台普查：把还没量过字数的章**全部**量一遍。
   *
   * 为什么光靠"读到哪量到哪"不够：没读过的章只能按「已确认章的平均字数」外推，
   * 而这本 100 章的书前 9 章平均 2093 字、全书平均 3928 字（后半章节明显更长），
   * 外推出来是 8.75% —— 跟按章数的 8.67% 一样虚高。章节长度不均匀的书，外推救不了。
   *
   * 所以打开书后补一次普查：读到哪算到哪的渐进精度改成一进门就精确。
   * 成本可控：单章就是「读一节 HTML 去标签」，且已量过的直接跳过，
   * 第二次打开这本书时整轮只剩 100 次数组比较；每 8 章让出一帧不焊死 UI。
   */
  private async surveyChars(): Promise<void> {
    if (this.surveying || this.source === null || this.book === null) {
      return;
    }
    this.surveying = true;
    try {
      for (let i: number = 0; i < this.chapterCount; i++) {
        if (this.charAt(i) > 0) {
          continue;
        }
        try {
          const t: string = this.source.chapterText(this.chapters[i]);
          if (t.length > 0) {
            this.learnChapterChars(i, t.length);
          }
        } catch (e) {
          // 单章读不出来就跳过：少一章的精度不影响进度可用
        }
        if (i % 8 === 7) {
          await new Promise<void>((resolve: (v: void) => void) => {
            setTimeout(() => { resolve(); }, 0);
          });
          // 让出前先原地刷新一次百分比：普查是渐进的，用户能看着它收敛到真值
          this.bookPercent = this.computeBookPercent();
        }
      }
      this.bookPercent = this.computeBookPercent();
      // 这条日志是「进度按真实字数」能否成立的唯一凭据 —— 它说出多少章拿到了真字数。
      // 装机打开一本书后 measured 若恒为 0，就说明普查压根没跑，百分比会退回按章数的
      // 虚高口径（首帧兜底路径漏调普查，就是对着这个数看出来的）。
      let measured: number = 0;
      for (let i: number = 0; i < this.chapterCount; i++) {
        if (this.charAt(i) > 0) {
          measured++;
        }
      }
      hilog.info(DOMAIN, TAG, 'char survey done: %{public}d/%{public}d chapters measured',
        measured, this.chapterCount);
      // 普查把全书字数总量改了 → 进度必须重新落库，否则书架/卡片还是按旧口径的数。
      // force=true 同时穿透卡片限流（见 pushCardUpdate 注释）：这一推是"口径升级"，
      // 被限流吞掉的话用户得等到下次翻页才看到正确百分比。
      this.persistProgress(true);
    } finally {
      this.surveying = false;
    }
  }

  /** 第 i 章已确认字数；越界或脏值（负数/NaN）一律按「没量过」处理 */
  private charAt(i: number): number {
    if (i < 0 || i >= this.charCounts.length) {
      return 0;
    }
    const c: number = this.charCounts[i];
    return (c > 0) ? c : 0;
  }

  private openChapter(index: number, charOffset: number): void {
    if (this.source === null || index < 0 || index >= this.chapters.length) {
      return;
    }
    // 换章才结算会话：重排（改档位/视口变化）也会走这里，不能把一次连续阅读切碎
    if (this.sessionChapter !== index) {
      this.flushSession();
      this.sessionChapter = index;
      this.sessionStartAt = Date.now();
    }
    const levels: LayoutLevels = this.prefs.getLevels();
    const box: LayoutBox = this.boxOf(levels);
    this.fontWeightValue = fontWeightOf(levels.fontWeightLevel);
    this.purifyOn = this.prefs.isPurifyOn();
    this.convertMode = this.prefs.getConvertMode();
    const chapter: ChapterRow = this.chapters[index];

    this.hint = '';
    let text: string = '';
    try {
      text = this.source.chapterText(chapter);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'read chapter failed: %{public}s', JSON.stringify(e));
      this.failChapter('这一章读取失败');
      return;
    }

    // 走到这里 = 本章读取成功，解除失败态（persistProgress 恢复正常落库）
    this.failed = false;
    this.chapterIndex = index;
    this.chapterTitle = chapter.title;
    this.chapterText = text;
    // 本章真实字数回填 → 全书进度从此按真实字数算（见 computeBookPercent）
    this.learnChapterChars(index, text.length);
    // 渲染用的量全部**从 box 派生**（而不是在这里再查一遍档位表）——
    // 否则渲染端与测量端就是两个各算一遍的真源，任何一处表值/换算改动都会悄悄分叉
    this.fontSizeFp = box.fontSizeFp;
    this.lineHeightVp = this.getUIContext().px2vp(box.lineHeightPx);
    // 等效边距从 box 取（版心封顶时 = (视口−封顶)/2），与测量断行同源不分叉
    this.marginVp = box.marginVp;

    // 净化/简繁开关会改变 text 内容（BookSource.chapterText 按开关重算），**必须进缓存键** ——
    // 否则切开关后命中旧键：页表是"净化后短文本"算的、正文已是"未净化长文本"，
    // 本章尾部若干页永远出不来（审查报告 B1）。这两个字段是 private 但同类内可见，直接读。
    const cacheKey: string = index + '|' + box.signature +
      '|p' + (this.purifyOn ? 1 : 0) + 'c' + this.convertMode;
    this.currentKey = box.signature;
    let table: PageTable | null = this.cache.get(cacheKey);
    if (table === null) {
      let built: PageTable;
      try {
        built = this.paginator.paginate(text, box);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'paginate failed: %{public}s', JSON.stringify(e));
        this.failChapter('这一章排版失败');
        return;
      }
      this.cache.put(cacheKey, built);
      table = built;
    }

    this.pages = table.pages;
    this.pageCount = table.pages.length;
    const target: number = charOffset < 0
      ? this.pageCount - 1
      : pageOfChar(table.pages, charOffset) - 1;
    this.showPage(target < 0 ? 0 : target);
    // 切章一定落进度：showPage 里的节流保存可能刚好被跳过（距上次落库不足 5 页）
    this.persistProgress(true);
  }

  // ------------------------------------------------------------------
  // 三件套（2026-10-22 评审 P0-2）：书签 / 摘录 / 全文搜索
  // ------------------------------------------------------------------

  /** 重拉本书的书签与摘录（进书 / 增删后调用） */
  private async reloadMarks(): Promise<void> {
    const book: BookRecord | null = this.book;
    if (book === null) {
      return;
    }
    try {
      this.bookmarks = await this.db.listBookmarks(book.id);
      this.highlights = await this.db.listHighlights(book.id);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load marks failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 当前页首加书签（页起始 offset 与 progress 同坐标系，页表可直接反查页码） */
  private async addBookmarkHere(): Promise<void> {
    const book: BookRecord | null = this.book;
    if (book === null || this.pages.length === 0 || this.failed) {
      return;
    }
    // 同一位置重复落签没有意义（同章同 offset 已有签 ⇒ 这次点击变成"取消"）
    const offset: number = this.pages[this.pageIndex].start;
    const existing: BookmarkRow | null = this.bookmarks.find((b: BookmarkRow) =>
      b.chapterIndex === this.chapterIndex && b.charOffset === offset) ?? null;
    try {
      if (existing !== null) {
        await this.db.deleteBookmark(existing.id);
      } else {
        // 快照取页首第一行非空文本（≤60 字）—— 删书后也能看懂当时为什么签它
        const line: string = this.pageText.replace(/\s+/g, ' ').trim().substring(0, 60);
        await this.db.addBookmark({
          id: 0,
          bookId: book.id,
          chapterIndex: this.chapterIndex,
          charOffset: offset,
          excerpt: line,
          createdAt: Date.now()
        });
      }
      await this.reloadMarks();
      // ⚑ 落签脉冲（与私记钤印手感同源）：点击放大一拍，spring 归位
      this.markKick = true;
      setTimeout(() => {
        this.markKick = false;
      }, 50);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'bookmark toggle failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 长按正文 ⇒ 摘录面板（存当前页快照 + 注） */
  private openHighlightPanel(): void {
    if (this.failed || this.pageText.length === 0) {
      return;
    }
    const range: PageRange = this.pages[this.pageIndex];
    // 原文快照截 200 字（快照是给"删书后还能看"的，不是全文备份）
    this.highlightExcerpt = this.pageText.replace(/\s+/g, ' ').trim().substring(0, 200);
    this.highlightStart = range.start;
    this.highlightEnd = range.end;
    this.highlightNote = '';
    this.showHighlight = true;
  }

  private async saveHighlight(): Promise<void> {
    const book: BookRecord | null = this.book;
    if (book === null || !this.showHighlight) {
      return;
    }
    try {
      await this.db.addHighlight({
        id: 0,
        bookId: book.id,
        chapterIndex: this.chapterIndex,
        startChar: this.highlightStart,
        endChar: this.highlightEnd,
        excerpt: this.highlightExcerpt,
        note: this.highlightNote.trim(),
        createdAt: Date.now()
      });
      this.showHighlight = false;
      await this.reloadMarks();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'save highlight failed: %{public}s', JSON.stringify(e));
    }
  }

  private async removeBookmark(id: number): Promise<void> {
    try {
      await this.db.deleteBookmark(id);
      await this.reloadMarks();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'remove bookmark failed: %{public}s', JSON.stringify(e));
    }
  }

  private async removeHighlight(id: number): Promise<void> {
    try {
      await this.db.deleteHighlight(id);
      await this.reloadMarks();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'remove highlight failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 全文搜索（P0-2 之三）：逐章读文本找命中。
   * 成本控制：每章最多记 3 条、全局 50 条封顶；每 10 章让出一帧（大书不卡 UI）。
   * 净化/简繁开关会影响 chapterText 的结果 —— 搜的就是"当前看到的样子"，语义自洽。
   */
  private async runFullTextSearch(query: string): Promise<void> {
    const q: string = query.trim();
    if (q.length === 0 || this.source === null) {
      this.searchHits = [];
      return;
    }
    this.searchBusy = true;
    const hits: SearchHitRow[] = [];
    try {
      for (let i: number = 0; i < this.chapters.length; i++) {
        let text: string = '';
        try {
          text = this.source.chapterText(this.chapters[i]);
        } catch (e) {
          continue; // 单章读失败不阻断整本搜索
        }
        let from: number = 0;
        let perChapter: number = 0;
        while (perChapter < 3) {
          const at: number = text.indexOf(q, from);
          if (at < 0) {
            break;
          }
          const ctxStart: number = Math.max(0, at - 30);
          const ctxEnd: number = Math.min(text.length, at + q.length + 30);
          const hit: SearchHitRow = {
            chapterIndex: i,
            chapterTitle: this.chapters[i].title,
            charOffset: at,
            snippet: (ctxStart > 0 ? '…' : '') + text.substring(ctxStart, ctxEnd) + (ctxEnd < text.length ? '…' : '')
          };
          hits.push(hit);
          perChapter++;
          from = at + q.length;
          if (hits.length >= 50) {
            break;
          }
        }
        if (hits.length >= 50) {
          break;
        }
        // 每 10 章让一帧：三千章的书不至于把 UI 线程钉死
        if (i % 10 === 9) {
          await new Promise<void>((resolve: () => void) => {
            setTimeout(resolve, 0);
          });
        }
      }
    } finally {
      this.searchHits = hits;
      this.searchBusy = false;
    }
  }

  private showPage(index: number): void {
    if (this.pages.length === 0) {
      return;
    }
    // A2：翻页顺带查一次昼夜（auto 档夜里跨 18:30 自动转夜，成本一次 if）
    this.syncTheme();
    let i: number = index;
    if (i < 0) {
      i = 0;
    }
    if (i > this.pages.length - 1) {
      i = this.pages.length - 1;
    }
    this.pageIndex = i;
    const range: PageRange = this.pages[i];
    this.pageText = this.chapterText.substring(range.start, range.end);
    this.pagePercent = (i + 1) / this.pages.length;
    this.bookPercent = this.computeBookPercent();
    this.persistProgress(false);
    // 朗读中的页面切换，三种来路分流（章级朗读，2026-10-18）：
    // ① speakSyncing（定时器页同步）：纯视觉跟随，音频队列不动；
    // ② 跨章（目录跳章 / 章末自动翻）：队列里是旧章文本 → reloadSpeakCurrent
    //    重载新章全文开读（跨章后停在第 0 页 = 章首）；
    // ③ 同章内用户手动翻页：耳朵跟眼睛走 —— seekTo 跳到新页起始偏移续读
    //    （暂停中只后移恢复点，不开读；点「继续」从新位置读）。
    if (this.speakActive && !this.speakSyncing) {
      if (this.speakChapterIndex !== this.chapterIndex) {
        this.reloadSpeakCurrent();
      } else {
        this.tts.seekTo(range.start);
        if (this.speakPaused) {
          this.speakProgress = '已换页';
        }
      }
    }
    this.refreshChapterLeft();
  }

  /**
   * A3（2026-10-25）：本章剩余阅读文案，对标 Apple Books「本章还剩 X 分钟」。
   * 用**固定估算速度**（见 ReadStats.EST_WPM）+ UI 上的「约」字 —— 阅读页不加载
   * sessions，引个人 WPM 要为此多一条查询，YAGNI；真实速度统计在 Stats 页已有。
   */
  private refreshChapterLeft(): void {
    if (this.pages.length === 0 || this.chapterText.length === 0) {
      this.chapterLeftText = '';
      return;
    }
    const left: number = this.chapterText.length - this.pages[this.pageIndex].start;
    this.chapterLeftText = chapterLeftText(left);
  }

  // ------------------------------------------------------------------
  // 朗读（TTS）控制 —— 章级朗读（2026-10-18 修订，findings §16.9）
  // 音频按章连续播，翻页只是视觉跟随；暂停/继续用句界回退续读。
  // ------------------------------------------------------------------

  /** 章内百分比文案（播放条显示；空章防除零） */
  private chapterPercent(charOffset: number): string {
    const len: number = this.chapterText.length;
    if (len <= 0) {
      return '0%';
    }
    const pct: number = Math.floor(Math.max(0, Math.min(charOffset, len)) / len * 100);
    return pct + '%';
  }

  /** 当前页在章内的起始字符偏移（朗读定位/跳转的统一基准） */
  private pageStartOffset(): number {
    if (this.pages.length === 0 || this.pageIndex >= this.pages.length) {
      return 0;
    }
    return this.pages[this.pageIndex].start;
  }

  /** 开始朗读：载入**整章**，从当前页位置开播（微信读书行为：点哪读哪） */
  private startSpeak(): void {
    if (!this.ttsSupported) {
      return;
    }
    const n: number = this.tts.loadChapter(this.chapterText);
    this.speakChapterIndex = this.chapterIndex;
    if (n === 0) {
      this.hint = '本章没有可读的内容';
      return;
    }
    this.speakPreparing = true;
    this.speakProgress = '准备中';
    this.speakPaused = false;
    if (this.tts.startFrom(this.pageStartOffset())) {
      // 同步路径：引擎已就绪，首段已 speak（onSegmentStart 会到）
      this.speakActive = true;
      this.speakPreparing = false;
      this.startSpeakTimer();
    }
    // startFrom 返回 false 且无 onError 到 = 引擎创建中的瞬态：
    // speakActive 由 onSegmentStart 置 true；期间播放条不显示（避免"假播放条"）
  }

  /** 播放/暂停切换（topBar 按钮与页脚播放条共用） */
  private toggleSpeak(): void {
    if (!this.speakActive) {
      this.startSpeak();
      return;
    }
    if (this.speakPaused) {
      // 继续：从暂停点（句界回退后）续读。队列被跨章重载成 idle 的防御路径
      // 走 startFrom(当前页偏移) —— 正常暂停态队列是 paused + cursor 已定位。
      if (this.tts.state === 'paused') {
        this.tts.resume();
      } else {
        this.tts.startFrom(this.pageStartOffset());
      }
      this.speakPaused = false;
      this.speakPreparing = true;
      this.speakProgress = '准备中';
      this.startSpeakTimer();
      this.kickSpeak();
    } else {
      this.tts.pause();
      this.speakPaused = true;
      this.kickSpeak();
    }
  }

  /** 播放/暂停脉冲：置 true 后 220ms 归位（与保存脉冲同参数，EaseOut 稳手感） */
  private kickSpeak(): void {
    this.speakKick = true;
    setTimeout(() => {
      this.speakKick = false;
    }, 220);
  }

  /** 停止朗读（收工：复位全部状态） */
  private stopSpeak(): void {
    this.tts.stop();
    this.speakActive = false;
    this.speakPaused = false;
    this.speakPreparing = false;
    this.speakProgress = '';
    this.speakChapterIndex = -1;
    this.stopSpeakTimer();
  }

  /**
   * 朗读定时循环切换：关 → 15 分 → 30 分 → 60 分 → 关。
   * 切档即重置剩余秒数（播放中立即生效；暂停中只改档位，恢复播放后开始倒数）。
   * 到点走 stopSpeak()——与手点「停止」同一路径，状态复位不漏。
   */
  private pickSleep(): void {
    this.sleepMin = this.sleepMin === 0 ? 15 : (this.sleepMin === 15 ? 30 : (this.sleepMin === 30 ? 60 : 0));
    this.sleepLeft = this.sleepMin * 60;
    if (this.sleepMin > 0) {
      this.hint = `定时：${this.sleepMin} 分钟后停止朗读`;
    }
  }

  /**
   * 跨章续读（章读完自动翻章 / 用户从目录跳章）：载入新章全文并开读。
   * 同章内的翻页不走这里（走 seekTo，见 showPage 尾部）。
   */
  private reloadSpeakCurrent(): void {
    const n: number = this.tts.loadChapter(this.chapterText);
    this.speakChapterIndex = this.chapterIndex;
    if (n === 0) {
      this.stopSpeak();
      return;
    }
    this.speakPreparing = true;
    this.speakProgress = '准备中';
    this.tts.begin();
  }

  // ---- 位置跟踪（章级朗读的"眼睛跟耳朵走"）----

  private startSpeakTimer(): void {
    if (this.speakTimer >= 0) {
      return;
    }
    this.speakTimer = setInterval(() => this.onSpeakTick(), 1000);
  }

  private stopSpeakTimer(): void {
    if (this.speakTimer >= 0) {
      clearInterval(this.speakTimer);
      this.speakTimer = -1;
    }
  }

  /** 每秒：更新章内百分比 + 页同步（音频位置驱动的翻页不碰朗读队列） */
  private onSpeakTick(): void {
    if (!this.speakActive || this.speakPaused) {
      return;
    }
    // 定时倒数：暂停时不进这里（tick 提前返回），倒计时随播放冻结
    if (this.sleepLeft > 0) {
      this.sleepLeft -= 1;
      if (this.sleepLeft <= 0) {
        this.stopSpeak();
        this.hint = '朗读定时已到，休息吧';
        return;
      }
    }
    const off: number = this.tts.estimatedOffset();
    if (off < 0) {
      return;
    }
    this.speakProgress = this.chapterPercent(off);
    if (this.pages.length === 0) {
      return;
    }
    const target: number = pageOfChar(this.pages, off) - 1;
    if (target < 0 || target === this.pageIndex) {
      return;
    }
    // speakSyncing = 本次 showPage 是音频跟随，不是用户翻页：
    // showPage 尾部据此跳过 seekTo（否则音频被自己的页同步打断）。
    this.speakSyncing = true;
    this.showPage(target);
    this.speakSyncing = false;
  }

  // ------------------------------------------------------------------
  // 翻页
  // ------------------------------------------------------------------

  /** 翻页：dir = +1 下一页 / -1 上一页。章内换页零计算；跨章才取新文本 */
  private turnPage(dir: number): void {
    if (this.pageCount === 0) {
      return;
    }
    if (dir > 0 && this.pageIndex < this.pageCount - 1) {
      this.animateTurn(this.chapterIndex, this.pageIndex + 1, dir);
      return;
    }
    if (dir < 0 && this.pageIndex > 0) {
      this.animateTurn(this.chapterIndex, this.pageIndex - 1, dir);
      return;
    }
    const next: number = this.chapterIndex + dir;
    if (next < 0 || next >= this.chapterCount) {
      return;
    }
    this.animateTurn(next, dir > 0 ? 0 : -1, dir);
  }

  /** 淡出 → 换页 → 淡入（带微小位移，方向感来自位移方向） */
  private animateTurn(chapterIndex: number, pageIndex: number, dir: number): void {
    this.getUIContext().animateTo({
      duration: FADE_OUT_MS,
      curve: Curve.EaseIn,
      onFinish: () => {
        if (chapterIndex !== this.chapterIndex) {
          this.openChapter(chapterIndex, pageIndex < 0 ? -1 : 0);
          if (pageIndex >= 0 && pageIndex !== this.pageIndex) {
            this.showPage(pageIndex);
          }
        } else {
          this.showPage(pageIndex);
        }
        this.shiftX = dir * FADE_SHIFT_VP;
        this.getUIContext().animateTo({ duration: FADE_IN_MS, curve: Curve.EaseOut }, () => {
          this.shiftX = 0;
          this.pageOpacity = 1;
        });
      }
    }, () => {
      this.pageOpacity = 0;
      this.shiftX = -dir * FADE_SHIFT_VP;
    });
  }

  // ------------------------------------------------------------------
  // 跟手翻页（鸿蒙「可中断动效」：拖到哪停到哪，松手才决定）
  // ------------------------------------------------------------------

  /** 还能不能往这个方向翻（首页往前 / 末页往后 = 不能，用于橡皮筋与松手判定） */
  private canTurn(dir: number): boolean {
    if (this.pageCount === 0) {
      return false;
    }
    if (dir > 0) {
      return this.pageIndex < this.pageCount - 1 || this.chapterIndex + 1 < this.chapterCount;
    }
    return this.pageIndex > 0 || this.chapterIndex > 0;
  }

  /** 拖拽时的实时位移：能翻就 1:1 跟手，不能翻只给 DRAG_RESIST（像橡皮筋） */
  private dragOffsetOf(dx: number): number {
    const dir: number = dx > 0 ? -1 : 1;
    return this.canTurn(dir) ? dx : dx * DRAG_RESIST;
  }

  /** 松手结算：够了就滑出并翻页，不够就回弹。全程只动 translate / opacity，不重排版 */
  private settleDrag(dx: number, velocityX: number): void {
    const dir: number = dx > 0 ? -1 : 1;
    const passed: boolean = Math.abs(dx) >= this.viewWidthVp * DRAG_TURN_RATIO
      || Math.abs(velocityX) >= DRAG_TURN_VELOCITY;
    if (!passed || !this.canTurn(dir)) {
      this.getUIContext().animateTo({ duration: DRAG_BACK_MS, curve: Curve.EaseOut }, () => {
        this.dragX = 0;
      });
      return;
    }
    const out: number = dx > 0 ? this.viewWidthVp : -this.viewWidthVp;
    this.getUIContext().animateTo({
      duration: DRAG_OUT_MS,
      curve: Curve.EaseOut,
      onFinish: () => {
        // 换页在"当前页已滑出且不可见"时发生 → 用户看不到换页瞬间
        this.applyTurn(dir);
        this.dragX = 0;
        this.pageOpacity = 0;
        this.getUIContext().animateTo({ duration: DRAG_IN_MS, curve: Curve.EaseOut }, () => {
          this.pageOpacity = 1;
        });
      }
    }, () => {
      this.dragX = out;
      this.pageOpacity = 0;
    });
  }

  /** 切到目标页但不做动画（跟手路径专用：进出场动画已由 settleDrag 负责） */
  private applyTurn(dir: number): void {
    if (dir > 0 && this.pageIndex < this.pageCount - 1) {
      this.showPage(this.pageIndex + 1);
      return;
    }
    if (dir < 0 && this.pageIndex > 0) {
      this.showPage(this.pageIndex - 1);
      return;
    }
    const next: number = this.chapterIndex + dir;
    if (next < 0 || next >= this.chapterCount) {
      return;
    }
    this.openChapter(next, dir > 0 ? 0 : -1);
  }

  private jumpToChapter(index: number): void {
    this.showToc = false;
    // 越界守卫必须在这里做：openChapter 对越界 index 直接 return，
    // 下面的 showPage(0) 若无条件执行会把用户瞬移回本章第 1 页并落库覆盖真实进度
    //（审查报告 B6 —— 首/末章点上一章/下一章触发）
    if (index < 0 || index >= this.chapters.length || index === this.chapterIndex) {
      return;
    }
    this.openChapter(index, 0);
    this.showPage(0);
  }

  // ------------------------------------------------------------------
  // 目录
  // ------------------------------------------------------------------

  /** 打开目录：清掉上次的搜索词，列表复位为全量（打开瞬间由 List.onAppear 定位到当前章） */
  private openToc(): void {
    // 三个覆盖层互斥（审查报告 B23）：目录开着时菜单/设置不能同时画着
    this.showSettings = false;
    this.showMenu = false;
    // 抽屉页签复位到目录（上次停在"搜索"页签的话，重开还是回到目录这条主线）
    this.drawerTab = 'toc';
    this.tocQuery = '';
    this.tocFiltered = this.chapters;
    this.tocSource.update(this.tocFiltered);
    this.showToc = true;
  }

  /**
   * 目录搜索：标题子串匹配，忽略大小写。
   * 只过滤不重编号 —— `item.index` 保持原章号，所以跳转、当前章高亮、序号显示都照旧正确。
   */
  private applyTocQuery(query: string): void {
    const key: string = query.trim().toLowerCase();
    if (key.length === 0) {
      this.tocFiltered = this.chapters;
      this.tocSource.update(this.tocFiltered);
      return;
    }
    this.tocFiltered = this.chapters.filter(
      (c: ChapterRow) => c.title.toLowerCase().indexOf(key) >= 0
    );
    this.tocSource.update(this.tocFiltered);
  }

  // ------------------------------------------------------------------
  // 设置抽屉（P11-2：就地改排版，正文实时跟着变，不用来回切页）
  // ------------------------------------------------------------------

  private openSettings(): void {
    // 三个覆盖层互斥（审查报告 B23）：目录/设置/中央菜单同时只开一个，
    // 否则抽屉叠抽屉、透明区吃点击 —— 返回键都点不动
    this.showToc = false;
    this.showMenu = false;
    this.levels = this.prefs.effectiveLevels(this.book === null ? '' : this.book.id);
    this.hasOverride = this.book === null ? false : this.prefs.hasBookOverride(this.book.id);
    this.showSettings = true;
  }

  /**
   * A1（2026-10-25 党哥拍板「仅这一本」）：抽屉里改的排版写进**这本书**的覆盖，
   * 不碰全局。全局默认值仍归独立设置页管（那边是「所有书」的口径）。
   */
  private saveBookLayout(): void {
    if (this.book === null) {
      return;
    }
    this.hasOverride = true;
    this.prefs.saveBookOverride(this.book.id, {
      levels: this.levels,
      theme: this.theme,
      fontFamily: this.fontFamily
    });
  }

  /** 挑档位：kind = 'font' | 'line' | 'margin' | 'weight' —— 存下来后立刻重排（不跳页） */
  private pickLevel(kind: string, value: number): void {
    const cur: LayoutLevels = this.levels;
    const next: LayoutLevels = {
      fontSizeLevel: kind === 'font' ? value : cur.fontSizeLevel,
      lineHeightLevel: kind === 'line' ? value : cur.lineHeightLevel,
      marginLevel: kind === 'margin' ? value : cur.marginLevel,
      fontWeightLevel: kind === 'weight' ? value : cur.fontWeightLevel
    };
    this.levels = next;
    this.saveBookLayout();
    this.applyPrefsToLayout();
  }

  private pickTheme(theme: ThemeName): void {
    this.theme = theme;
    this.saveBookLayout();
    this.applyPrefsToLayout();
  }

  private pickFont(family: string): void {
    hilog.info(DOMAIN, TAG, 'pickFont: %{public}s', family);
    this.fontFamily = family;
    this.saveBookLayout();
    this.applyPrefsToLayout();
  }

  /** 抽屉里的字体候选：只列**系统默认 + 已下载**的开源字体（系统字体全列表留在独立设置页） */
  private fontChoices(): FontEntry[] {
    return this.fontStore === null ? [] : this.fontStore.downloaded();
  }

  private rangeOf(max: number): number[] {
    const out: number[] = [];
    for (let i: number = 1; i <= max; i++) {
      out.push(i);
    }
    return out;
  }

  /**
   * 当前档位。抽屉里的选中态**必须经它读**，不能把数值当参数传进 @Builder：
   * ArkUI 的 @Builder **按值传参不会驱动刷新**（真机已验证：点字号后正文变了、选中框不动 ——
   * themeChip / fontChip 正常恰是因为它们在 Builder 内部直接读 this.theme / this.fontFamily）。
   * 另外 ForEach 的键必须含选中态，否则状态变了、键没变，item 也不会重建（见 chipRow）。
   */
  private levelOf(kind: string): number {
    if (kind === 'font') {
      return this.levels.fontSizeLevel;
    }
    if (kind === 'line') {
      return this.levels.lineHeightLevel;
    }
    if (kind === 'margin') {
      return this.levels.marginLevel;
    }
    return this.levels.fontWeightLevel;
  }

  /** 档位 kind 的中文名 —— 无障碍朗读要读"字号 5"而不是光一个"5" */
  private kindLabel(kind: string): string {
    if (kind === 'font') {
      return '字号';
    }
    if (kind === 'line') {
      return '行距';
    }
    if (kind === 'margin') {
      return '页边距';
    }
    return '字重';
  }

  // ------------------------------------------------------------------
  // 进度
  // ------------------------------------------------------------------

  private persistProgress(force: boolean): void {
    if (this.book === null || this.chapterCount === 0) {
      return;
    }
    // **失败态禁止落库**（审查报告 B2）：failChapter 清空了 pages，
    // 这时落库会把 offset 写成 0，用户的真实阅读进度被覆盖成"章首"且无法找回
    if (this.failed) {
      return;
    }
    if (!force) {
      this.pagesSincePersist += 1;
      if (this.pagesSincePersist < PERSIST_EVERY_PAGES) {
        return;
      }
    }
    this.pagesSincePersist = 0;
    const offset: number = this.pages.length > 0 && this.pageIndex < this.pages.length
      ? this.pages[this.pageIndex].start
      : 0;
    const p: ReadingProgress = {
      bookId: this.book.id,
      chapterIndex: this.chapterIndex,
      charOffset: offset,
      percent: this.bookPercent,
      updatedAt: Date.now()
    };
    // 两个写库**都完成后**才发 AppStorage 信号 —— 书架（Index）靠 @Watch 收到后重拉进度。
    // 2026-09-26 审核驳回第 3 条根因：以前是 fire-and-forget，返回书架时 Index 的
    // onPageShow 立刻查库，查询跑在写入前面 → 书架拿到旧进度（显示 0%），要杀进程重进才好。
    Promise.all([
      this.db.saveProgress(p),
      this.db.touchLastRead(this.book.id, p.updatedAt)
    ]).then(() => {
      hilog.info(DOMAIN, TAG, 'progress saved ok, sending signal');
      // **带快照发信号**：书架 Index 的 @Watch 收到后直接改本地 @State 刷新 UI
      // （不查库、不等 onPageShow、不依赖版本行为）。
      // 2026-10-12 华为 1.0.1 审核反馈：API 24 真机上只靠 onPageShow + 查库的链路仍不刷新。
      const snap: ProgressSnapshot = { bookId: p.bookId, percent: p.percent };
      AppStorage.setOrCreate('progressSaved', snap);
      AppStorage.setOrCreate('progressSavedAt', p.updatedAt);
      // B1：顺带推服务卡片（内部限流 + 全兜异常，fire-and-forget 不拖慢落库链路）。
      // force（最后一次）必须穿透限流 —— 否则被限流吞掉的那次很可能就是用户离开前
      // 的最后进展，桌面卡片会停在旧百分比上再也补不上（详见 pushCardUpdate 注释）。
      pushCardUpdate(this.getUIContext().getHostContext() as Context, force);
      // B1：EPUB 的 chapters 表不存 end_char，卡片算不出「本章还剩 N 分钟」——
      // 这里把当前章剩余字数（内存里有整章文本）写进提示，卡片读取时按书+章校验使用
      if (this.chapterText.length > 0) {
        const ctx: Context = this.getUIContext().getHostContext() as Context;
        saveCardLeftHint(ctx, {
          bookId: p.bookId,
          chapterIndex: p.chapterIndex,
          charsLeft: Math.max(0, this.chapterText.length - offset)
        });
      }
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'save progress failed: %{public}s', e.message);
    });
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  @Builder
  topBar() {
    Row() {
      Text('‹')
        .fontSize(RR_FS_TITLE)
        .fontColor(this.palette.text)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .responseRegion({ x: -5, y: -5, width: 44, height: 44 })
        .accessibilityText('返回书架')
        .onClick(() => this.getUIContext().getRouter().back())
      Text(this.title)
        .fontSize(RR_FS_LABEL)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .maxLines(1)
        // 与书架卡片书名的共享元素转场（同 id）；book 还是 null 时 id 配不上，退化为普通转场，不崩
        .sharedTransition('rr-title-' + (this.book !== null ? this.book.id : ''), { duration: 300 })
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: RR_SP_MD })
        .layoutWeight(1)
      Text(this.chapterCount > 0 ? `${this.chapterIndex + 1}/${this.chapterCount}` : '')
        .fontSize(RR_FS_MICRO)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
      // 朗读入口：仅设备支持 TTS 时渲染（探测失败的设备完全看不到）。
      // 放标题行而不是底部四等分按钮行 —— 不破坏「上一章/目录/Aa/下一章」的构图。
      // 图标而非文字（党哥 2026-10-18 要求）：三态 = 待机无声波 / 暂停单弧压暗 /
      // 播放双弧；SVG 矢量 + fillColor 跟随 palette.text（四套主题通用）。
      // ⚠️ 不走 Shape/Path：Path commands 是**物理 px**，viewPort 声明式缩放实测
      // 不生效（API26 模拟器，2026-10-19，findings §17.8）—— 20vp 的框里图标
      // 只有 11×16px，且墨色贴在框顶导致与相邻数字不居中。SVG 由渲染器缩放，
      // 与 DPR 无关；28vp 整框进 Row，VerticalAlign.Center 保证与数字居中对齐。
      if (this.ttsSupported) {
        Image(this.speakActive
          ? (this.speakPaused ? $r('app.media.ic_speaker_paused') : $r('app.media.ic_speaker_playing'))
          : $r('app.media.ic_speaker_idle'))
          .width(SPEAKER_ICON_VP)
          .height(SPEAKER_ICON_VP)
          .fillColor(this.palette.text)
          .margin({ left: RR_SP_MD })
          // 播放/暂停一拍即走：喇叭同步脉冲（与页脚文字按钮同一状态）
          .scale({ x: this.speakKick ? 1.2 : 1.0, y: this.speakKick ? 1.2 : 1.0 })
          .animation({ duration: 220, curve: Curve.EaseOut })
          // 视觉 28vp，热区 56×44：触摸标准 ≥44（上下各撑 8，左右各撑 14）
          .responseRegion({ x: -14, y: -8, width: 56, height: 44 })
          .accessibilityText(this.speakActive ? (this.speakPaused ? '继续朗读' : '暂停朗读') : '开始朗读')
          .onClick(() => this.toggleSpeak())
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: RR_SP_2XL, right: RR_SP_3XL, top: RR_SP_XL, bottom: RR_SP_2XL })
    .backgroundColor(this.palette.overlay)
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
    // 中央菜单唤起时自上滑入（复评整改：原瞬现）
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: -16 }))
      .animation({ duration: 180, curve: Curve.EaseOut }))
  }

  @Builder
  segBar(percent: number) {
    Row({ space: 2 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (i: number) => {
        Row()
          .layoutWeight(1)
          .height(2)
          .backgroundColor(percent * 10 > i ? this.palette.text : this.palette.line)
      }, (i: number) => 'seg' + i)
    }
    .width('100%')
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        Text(this.chapterTitle)
          .fontSize(RR_FS_DIGIT)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.chapterLeftText.length > 0) {
          Text(this.chapterLeftText)
            .fontSize(RR_FS_META)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: RR_SP_MD })
        }
        Text(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '')
          .fontSize(RR_FS_DIGIT)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: RR_SP_XL })

      Row() {
        // 视觉 34vp，热区 44vp：触摸标准 ≥44，用 responseRegion 上下各撑 5
        // （.+ accessibilityText：屏幕朗读要能说出按钮名字，AGC 审核会查）
        Text('上一章')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.chapterIndex <= 0 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText('上一章')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => this.jumpToChapter(this.chapterIndex - 1))
        // ⚑ 书签（2026-10-22 P0-2 三件套）：一键落签当前位置；
        // 已签的页再点一次 = 取消。列表在抽屉「标记」页签里。
        Text(this.bookmarks.some((b: BookmarkRow) =>
          b.chapterIndex === this.chapterIndex &&
          (this.pages.length > 0 && b.charOffset === this.pages[this.pageIndex].start)) ? '⚑' : '⚐')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.markKick || this.bookmarks.some((b: BookmarkRow) =>
            b.chapterIndex === this.chapterIndex &&
            (this.pages.length > 0 && b.charOffset === this.pages[this.pageIndex].start))
            ? this.palette.accent : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText(this.bookmarks.length > 0 ? '添加或取消书签' : '添加书签')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          // 落签脉冲：点击放大一拍，spring 归位（与私记钤印手感同源）
          .scale({ x: this.markKick ? 1.4 : 1.0, y: this.markKick ? 1.4 : 1.0 })
          .animation({ duration: 320, curve: curves.springMotion(0.3, 0.7) })
          .onClick(() => {
            this.addBookmarkHere();
          })
        Text('目录')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText('目录')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => {
            this.openToc();
          })
        Text('A a')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText('排版设置')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => {
            this.openSettings();
          })
        Text('下一章')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.chapterIndex >= this.chapterCount - 1 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText('下一章')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => this.jumpToChapter(this.chapterIndex + 1))
      }
      .width('100%')
      .margin({ bottom: RR_SP_2XL })

      this.segBar(this.bookPercent)

      Row() {
        Text(`${Math.round(this.bookPercent * 100)}%`)
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ top: RR_SP_LG })
    }
    .width('100%')
    .padding({ left: RR_SP_3XL, right: RR_SP_3XL, top: RR_SP_3XL, bottom: RR_SP_5XL })
    .backgroundColor(this.palette.overlay)
    .border({ width: { top: 1 }, color: this.palette.lineSoft })
    // 中央菜单唤起时自下滑入（复评整改：原瞬现）
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.translate({ y: 16 }))
      .animation({ duration: 180, curve: Curve.EaseOut }))
    .onClick(() => {
    })
  }

  @Builder
  tocPanel() {
    Column() {
      // 抽屉页签（2026-10-22 P0-2 三件套）：目录 / 标记（书签+摘录）/ 全文搜索
      Row({ space: 18 }) {
        Text('目录')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.drawerTab === 'toc' ? this.palette.text : this.palette.text3)
          .border({ width: { bottom: 1.5 }, color: this.drawerTab === 'toc' ? this.palette.accent : Color.Transparent })
          .padding({ bottom: 6 })
          .accessibilityText('目录页签')
          .onClick(() => {
            this.drawerTab = 'toc';
          })
        Text(`标记 ${this.bookmarks.length + this.highlights.length}`)
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.drawerTab === 'marks' ? this.palette.text : this.palette.text3)
          .border({ width: { bottom: 1.5 }, color: this.drawerTab === 'marks' ? this.palette.accent : Color.Transparent })
          .padding({ bottom: 6 })
          .accessibilityText('标记页签，共 ' + (this.bookmarks.length + this.highlights.length) + ' 条')
          .onClick(() => {
            this.drawerTab = 'marks';
          })
        Text('搜索')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.drawerTab === 'search' ? this.palette.text : this.palette.text3)
          .border({ width: { bottom: 1.5 }, color: this.drawerTab === 'search' ? this.palette.accent : Color.Transparent })
          .padding({ bottom: 6 })
          .accessibilityText('全文搜索页签')
          .onClick(() => {
            this.drawerTab = 'search';
          })
        Blank()
        Text(this.drawerTab === 'toc' && this.tocQuery.length > 0
          ? `${this.tocFiltered.length}/${this.chapterCount}`
          : this.drawerTab === 'toc' ? `${this.chapterCount}` : '')
          .fontSize(RR_FS_DIGIT)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_XL })

      if (this.drawerTab === 'toc') {
        this.tocList()
      } else if (this.drawerTab === 'marks') {
        this.marksPanel()
      } else {
        this.searchPanel()
      }
    }
    .width(TOC_PANEL_WIDTH)
    .height('100%')
    .backgroundColor(this.palette.overlay)
    // 左抽屉：圆角与描边只做贴着屏幕右缘的那侧（左侧贴着屏边，不需要）
    .borderRadius({ topRight: 12, bottomRight: 12 })
    .border({ width: { top: 1, right: 1, bottom: 1 }, color: this.palette.line })
    .transition(TransitionEffect.translate({ x: -TOC_SLIDE_VP })
      .animation({ duration: PANEL_ANIM_MS, curve: Curve.FastOutSlowIn }))
    .onClick(() => {
    })
  }

  /** 原目录内容（页签化后抽出来的正文部分，结构与原 tocPanel 一致） */
  @Builder
  tocList() {
    Column() {
      // 章节搜索：三千章的书不必手滚着找
      Row() {
        Text('/')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .width(18)
        TextInput({ text: this.tocQuery, placeholder: '查找章节' })
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text)
          .placeholderColor(this.palette.text3)
          .placeholderFont({ size: 12.5 })
          .caretColor(this.palette.accent)
          .backgroundColor(Color.Transparent)
          .borderRadius(RR_RADIUS_COVER)
          .padding(0)
          .height(36)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.tocQuery = value;
            this.applyTocQuery(value);
          })
        if (this.tocQuery.length > 0) {
          Text('×')
            .fontSize(RR_FS_HEADING)
            .fontColor(this.palette.text3)
            .width(26)
            .textAlign(TextAlign.Center)
            .accessibilityText('清除目录搜索')
            .onClick(() => {
              this.tocQuery = '';
              this.applyTocQuery('');
            })
        }
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      if (this.tocFiltered.length === 0) {
        Text(this.tocQuery.length > 0 ? '没有匹配的章节' : '这本书没有解析出章节')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_6XL })
      } else {
        List({ scroller: this.tocScroller }) {
          LazyForEach(this.tocSource, (item: ChapterRow) => {
            ListItem() {
              ChapterItem({
                title: item.title,
                index: item.index,
                current: item.index === this.chapterIndex,
                textColor: this.palette.text,
                text2Color: this.palette.text2,
                accentColor: this.palette.accent,
                onJump: (i: number) => this.jumpToChapter(i)
              })
            }
          }, (item: ChapterRow) => 'ch' + item.index)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 1, color: this.palette.lineSoft })
        .onAppear(() => {
          // 打开目录即把当前章滚到中间 —— 读到第 2000 章不用自己从头找
          try {
            this.tocScroller.scrollToIndex(this.chapterIndex, false, ScrollAlign.CENTER);
          } catch (e) {
            hilog.warn(DOMAIN, TAG, 'toc scrollToIndex failed: %{public}s', (e as Error).message);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
    })
  }

  /**
   * 把这本书的书签 + 摘录交给用户（交给系统分享面板）。
   *
   * 为什么只走系统分享、不自己往磁盘落一个文件：自己写要申请存储/挑选权限，
   * 而 Share Kit 是**零权限**的 —— 数据从沙箱直接进用户自己挑的目的地
   * （微信、备忘录、云盘、另一台手机），既不用问权限，也不用替他决定存哪。
   * 这一条同时守住家族「零权限」和「核心数据不联网」两条铁律：
   * 分享是**用户当场主动发起的一次性动作**，不是后台偷偷同步。
   */
  private exportMarks(): void {
    if (this.book === null) {
      return;
    }
    const body: string = buildMarksExport(
      this.title, this.book.author, this.highlights, this.bookmarks, new Date()
    );
    try {
      const data: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.TEXT,
        content: body,
        title: '《' + this.title + '》的笔记',
        description: 'Rock阅读 · 本机导出'
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      controller.show(ctx, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'share marks failed: %{public}s', JSON.stringify(e));
      });
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'share marks build failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 「标记」页签（P0-2）：书签 + 摘录两个分组。
   * 点条目跳回原位（书签按 offset、摘录按 startChar，同一套页表反查）。
   */
  @Builder
  marksPanel() {
    Column() {
      if (this.bookmarks.length === 0 && this.highlights.length === 0) {
        Column() {
          Text('还没有标记')
            .fontSize(RR_FS_LABEL)
            .fontColor(this.palette.text3)
          Text('工具条的 ⚑ 落书签 · 长按正文存摘录')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.text3)
            .margin({ top: RR_SP_SM })
        }
        .width('100%')
        .margin({ top: RR_SP_6XL })
      } else {
        List() {
          if (this.bookmarks.length > 0) {
            ListItem() {
              Text('书签')
                .fontSize(RR_FS_META)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .width('100%')
                .padding({ top: RR_SP_LG, bottom: RR_SP_SM, left: RR_SP_4XL, right: RR_SP_4XL })
            }
          }
          ForEach(this.bookmarks, (b: BookmarkRow) => {
            ListItem() {
              Row() {
                Column() {
                  Text('⚑ ' + (b.excerpt.length > 0 ? b.excerpt : `第 ${b.chapterIndex + 1} 章`))
                    .fontSize(RR_FS_LABEL)
                    .fontColor(this.palette.text)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  Text(`第 ${b.chapterIndex + 1} 章`)
                    .fontSize(RR_FS_MICRO)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('×')
                  .fontSize(RR_FS_HEADING)
                  .fontColor(this.palette.text3)
                  .width(32)
                  .textAlign(TextAlign.Center)
                  .accessibilityText('删除这个书签')
                  .onClick(() => {
                    this.removeBookmark(b.id);
                  })
              }
              .width('100%')
              .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_MD, bottom: RR_SP_MD })
              .onClick(() => {
                this.showToc = false;
                this.openChapter(b.chapterIndex, b.charOffset);
              })
            }
          }, (b: BookmarkRow) => 'bm' + b.id)
          if (this.highlights.length > 0) {
            ListItem() {
              Text('摘录')
                .fontSize(RR_FS_META)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .width('100%')
                .padding({ top: RR_SP_LG, bottom: RR_SP_SM, left: RR_SP_4XL, right: RR_SP_4XL })
            }
          }
          ForEach(this.highlights, (h: HighlightRow) => {
            ListItem() {
              Row() {
                Column() {
                  Text('「' + h.excerpt + '」')
                    .fontSize(RR_FS_LABEL)
                    .fontColor(this.palette.text)
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                  if (h.note.length > 0) {
                    Text(h.note)
                      .fontSize(RR_FS_MICRO)
                      .fontColor(this.palette.text2)
                      .margin({ top: 4 })
                      .width('100%')
                  }
                  Text(`第 ${h.chapterIndex + 1} 章`)
                    .fontSize(RR_FS_MICRO)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('×')
                  .fontSize(RR_FS_HEADING)
                  .fontColor(this.palette.text3)
                  .width(32)
                  .textAlign(TextAlign.Center)
                  .accessibilityText('删除这条摘录')
                  .onClick(() => {
                    this.removeHighlight(h.id);
                  })
              }
              .width('100%')
              .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_MD, bottom: RR_SP_MD })
              .onClick(() => {
                this.showToc = false;
                this.openChapter(h.chapterIndex, h.startChar);
              })
            }
          }, (h: HighlightRow) => 'hl' + h.id)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 1, color: this.palette.lineSoft })

        // 导出：攒了几十条摘抄却拿不出去，等于把人锁死在这个应用里 —— 这不对。
        // 只在真的有标记时出现：导一团空文本除了让人失望没有别的用处。
        if (this.bookmarks.length > 0 || this.highlights.length > 0) {
          Row() {
            Text('导出这本书的笔记')
              .fontSize(RR_FS_LABEL)
              .fontColor(this.palette.text)
          }
          .width('100%')
          .height(44)
          .justifyContent(FlexAlign.Center)
          .borderWidth(1)
          .borderColor(this.palette.line)
          .borderRadius(RR_RADIUS_COVER)
          .margin({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_LG, bottom: RR_SP_2XL })
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText('导出这本书的书签和摘录')
          .onClick(() => {
            this.exportMarks();
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
    })
  }

  /** 「搜索」页签（P0-2）：全文搜索（标题搜索仍在目录页签里） */
  @Builder
  searchPanel() {
    Column() {
      Row() {
        Text('/')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .width(18)
        TextInput({ text: this.searchQuery, placeholder: '在全书正文中查找' })
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text)
          .placeholderColor(this.palette.text3)
          .placeholderFont({ size: 12.5 })
          .caretColor(this.palette.accent)
          .backgroundColor(Color.Transparent)
          .borderRadius(RR_RADIUS_COVER)
          .padding(0)
          .height(36)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.searchQuery = value;
            // 防抖 400ms：逐章扫描的成本不该付在每次按键上
            if (this.searchTimer >= 0) {
              clearTimeout(this.searchTimer);
              this.searchTimer = -1;
            }
            const q: string = value.trim();
            if (q.length === 0) {
              this.searchHits = [];
              return;
            }
            this.searchTimer = setTimeout(() => {
              this.searchTimer = -1;
              this.runFullTextSearch(q);
            }, 400);
          })
        if (this.searchQuery.length > 0) {
          Text('×')
            .fontSize(RR_FS_HEADING)
            .fontColor(this.palette.text3)
            .width(26)
            .textAlign(TextAlign.Center)
            .accessibilityText('清除搜索')
            .onClick(() => {
              this.searchQuery = '';
              this.searchHits = [];
            })
        }
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      if (this.searchBusy) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(this.palette.text3)
          Text('正在全书搜索…')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.text3)
            .margin({ top: RR_SP_SM })
        }
        .width('100%')
        .margin({ top: RR_SP_6XL })
      } else if (this.searchQuery.trim().length === 0) {
        Text('输入词句，找到它在哪一章')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_6XL })
      } else if (this.searchHits.length === 0) {
        Text('全书没有匹配')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_6XL })
      } else {
        List() {
          ForEach(this.searchHits, (hit: SearchHitRow) => {
            ListItem() {
              Column() {
                Row() {
                  Text(hit.chapterTitle)
                    .fontSize(RR_FS_MICRO)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                }
                .width('100%')
                Text(hit.snippet)
                  .fontSize(RR_FS_LABEL)
                  .fontColor(this.palette.text)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
              .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_MD, bottom: RR_SP_MD })
              .onClick(() => {
                this.showToc = false;
                this.openChapter(hit.chapterIndex, hit.charOffset);
              })
            }
          }, (hit: SearchHitRow) => 'sh' + hit.chapterIndex + ':' + hit.charOffset)
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .divider({ strokeWidth: 1, color: this.palette.lineSoft })
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
    })
  }

  /** 长按正文唤起的摘录面板（P0-2）：快照 + 一句注 */
  @Builder
  highlightEditor() {
    Column() {
      Text('存一段摘录')
        .fontSize(RR_FS_HEADING)
        .fontColor(this.palette.text)
        .width('100%')
      Text('「' + this.highlightExcerpt + '」')
        .fontSize(RR_FS_LABEL)
        .fontColor(this.palette.text2)
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: RR_SP_MD })
        .padding(RR_SP_MD)
        .backgroundColor(this.palette.overlay)
        .borderRadius(8)
      TextInput({ placeholder: '写一句注（可空）', text: this.highlightNote })
        .fontSize(RR_FS_LABEL)
        .fontColor(this.palette.text)
        .placeholderColor(this.palette.text3)
        .placeholderFont({ size: 12.5 })
        .caretColor(this.palette.accent)
        .backgroundColor(this.palette.overlay)
        .borderRadius(RR_RADIUS_COVER)
        .height(40)
        .margin({ top: RR_SP_MD })
        .onChange((v: string) => {
          this.highlightNote = v;
        })
      Row({ space: RR_SP_MD }) {
        Button('取消', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text2)
          .backgroundColor(Color.Transparent)
          .borderRadius(RR_RADIUS_COVER)
          .layoutWeight(1)
          .onClick(() => {
            this.showHighlight = false;
          })
        Button('存下', { type: ButtonType.Normal, stateEffect: true })
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.bg)
          .backgroundColor(this.palette.accent)
          .borderRadius(RR_RADIUS_COVER)
          .layoutWeight(1)
          .onClick(() => {
            this.saveHighlight();
          })
      }
      .width('100%')
      .margin({ top: RR_SP_LG })
    }
    .width('82%')
    .padding(RR_SP_3XL)
    .backgroundColor(this.palette.bg)
    .borderRadius(16)
    .border({ width: 1, color: this.palette.line })
    .transition(TransitionEffect.OPACITY
      .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }))
      .animation({ duration: 200, curve: Curve.FastOutSlowIn }))
    .onClick(() => {
    })
  }

  /** 一行档位芯片（4vp 圆角、选中反白 —— 与独立设置页同一套视觉） */
  @Builder
  chipRow(kind: string, max: number) {
    Row({ space: 8 }) {
      ForEach(this.rangeOf(max), (n: number) => {
        Text(`${n}`)
          .fontSize(RR_FS_LABEL)
          .fontFamily('monospace')
          // 选中判断必须读 this（@Builder 值传参不追踪，见 levelOf 的注释）
          .fontColor(n === this.levelOf(kind) ? this.palette.bg : this.palette.text2)
          .backgroundColor(n === this.levelOf(kind) ? this.palette.text : this.palette.card)
          .borderWidth(1)
          .borderColor(n === this.levelOf(kind) ? this.palette.text : this.palette.line)
          .width(44)
          .height(34)
          .textAlign(TextAlign.Center)
          // 视觉 44×34：宽度已达标，高度差 10 → 热区上下各撑 5 补到 44
          .stateStyles({ pressed: { opacity: 0.6 } })
          .accessibilityText(`${this.kindLabel(kind)} ${n}`)
          .responseRegion({ x: 0, y: -5, width: 44, height: 44 })
          .onClick(() => this.pickLevel(kind, n))
      }, (n: number) => kind + '-' + n + (n === this.levelOf(kind) ? '-on' : '-off'))
    }
    .width('100%')
  }

  @Builder
  settingsRow(label: string, max: number, kind: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        Blank()
        Text(`${this.levelOf(kind)}/${max}`)
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: RR_SP_XL })
      this.chipRow(kind, max)
    }
    .width('100%')
    .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_3XL })
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
  }

  @Builder
  themeChip(theme: ThemeName) {
    Text(themeLabel(theme))
      .fontSize(RR_FS_LABEL)
      .fontColor(this.theme === theme ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.theme === theme ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(this.theme === theme ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
      .textAlign(TextAlign.Center)
      .stateStyles({ pressed: { opacity: 0.6 } })
      .accessibilityText(`主题 ${themeLabel(theme)}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickTheme(theme))
  }

  @Builder
  fontChip(label: string, family: string) {
    Text(label)
      .fontSize(RR_FS_LABEL)
      .fontColor(this.fontFamily === family ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.fontFamily === family ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(this.fontFamily === family ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .stateStyles({ pressed: { opacity: 0.6 } })
      .accessibilityText(`字体 ${label}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickFont(family))
  }

  /** 音色 chip（设置面板）：选中即试听当前页 —— 官方无网页试听页，
   *  RockReader 自己就是最佳试听器（同一引擎，模拟器可出声）。
   *  2026-10-23 复评：凌飞哲未下载时 chip 明示「需下载」（原来是点了就
   *  createEngine 报错回退的死选项，没有任何下载路径）；下载中显示进度；
   *  首次点未下载音色进入「确认」态（两击确认，防误触），再点一次才发起。 */
  @Builder
  personChip(label: string, person: number) {
    Text(this.voiceBusyPerson === person
      ? (label + ' · ' + (this.voicePct >= 0 ? this.voicePct + '%' : '下载中'))
      : (this.voiceArmedPerson === person
        ? label + ' · 确认下载'
        : (this.prefs.isVoiceReady(person) ? label : label + ' · 需下载')))
      .fontSize(RR_FS_LABEL)
      .fontColor(this.ttsPerson === person ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.ttsPerson === person ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(this.ttsPerson === person ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .stateStyles({ pressed: { opacity: 0.6 } })
      .accessibilityText(this.voiceBusyPerson === person ? `音色 ${label} 下载中`
        : (this.prefs.isVoiceReady(person) ? `音色 ${label}` : `音色 ${label}，需要下载`))
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickPerson(person))
  }

  /** 语速 chip（设置面板）：选中态与音色/主题同视觉；改速下一段起生效（行头已标注） */
  @Builder
  speedChip(label: string, v: number) {
    Text(label)
      .fontSize(RR_FS_LABEL)
      .fontFamily('monospace')
      .fontColor(Math.abs(this.ttsSpeed - v) < 0.001 ? this.palette.bg : this.palette.text2)
      .backgroundColor(Math.abs(this.ttsSpeed - v) < 0.001 ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(Math.abs(this.ttsSpeed - v) < 0.001 ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .stateStyles({ pressed: { opacity: 0.6 } })
      .accessibilityText(`语速 ${label}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickTtsSpeed(v))
  }

  /** 选音色：落盘 + 热切换引擎 + 立即试听当前页（失败走 onErr 回退默认） */
  private pickPerson(person: number): void {
    if (person === this.ttsPerson) {
      return;
    }
    // 未下载的音色（凌飞哲 21）：不再「选了就报错回退」——
    // 第一击进入「确认下载」态（toast 明示：系统语音服务下载、消耗流量），
    // 第二击才真正发起（两击确认，防误触也防流量意外）。
    if (!this.prefs.isVoiceReady(person)) {
      if (this.voiceArmedPerson === person) {
        this.voiceArmedPerson = 0;
        this.runVoiceDownload(person);
      } else {
        this.voiceArmedPerson = person;
        promptAction.showToast({ message: '凌飞哲音色由系统语音服务下载（消耗流量），再点一次开始' });
      }
      return;
    }
    this.voiceArmedPerson = 0;
    this.prefs.setTtsPerson(person);
    this.ttsPerson = person;
    // setPerson 内部会停旧引擎并 shutdown；随后 startSpeak 用新音色重建
    this.tts.setPerson(person);
    this.startSpeak();
  }

  /** 跑下载：进度进 chip，完成自动选中试听，失败 toast 可重试（不落失败态，下次仍引导） */
  private runVoiceDownload(person: number): void {
    this.voiceBusyPerson = person;
    this.voicePct = -1;
    this.tts.downloadVoice(person,
      (pct: number) => {
        this.voicePct = pct;
      },
      (ok: boolean, msg: string) => {
        this.voiceBusyPerson = 0;
        this.voicePct = -1;
        if (ok) {
          this.prefs.markVoiceDownloaded(person, true);
          promptAction.showToast({ message: '音色下载完成' });
          this.pickPerson(person); // 直接选中并试听
        } else {
          promptAction.showToast({ message: msg + '，可重试' });
        }
      });
  }

  /**
   * 选语速（2026-10-22 P0-3）：落盘 + 引擎即时跟随。
   * ⚠️ CoreSpeechKit 的 speed 是 per-speak 参数 —— 正在播的段不变，
   * 下一段（或 seek/续读后的段）起生效。UI 文案如实标注，不装"立即生效"。
   */
  private pickTtsSpeed(v: number): void {
    this.prefs.setTtsSpeed(v);
    this.ttsSpeed = v;
    this.tts.setSpeed(v);
  }

  /** 设置抽屉：底出、不遮满（上半透出正文），改一下上面立刻跟着变 */
  @Builder
  settingsPanel() {
    Column() {
      Row() {
        Text('排版')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontColor(this.palette.text2)
        Blank()
        Text('边改边看')
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
        // 显式关闭键（2026-10-23 复评实测补）：面板内容总高会超过抽屉高度，
        // 「点上半透出的正文关闭」那条路可能被压成 0 像素 —— × 是兜底出路。
        Text('×')
          .fontSize(RR_FS_LABEL)
          .fontColor(this.palette.text2)
          .width(44)
          .height(44)
          .textAlign(TextAlign.Center)
          .accessibilityText('关闭设置')
          .onClick(() => {
            this.showSettings = false;
          })
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_SM })

      // 审查报告 B24：抽屉内容整体可滚 + 限高 —— 矮视口/横屏时"更多设置"不再被推出屏幕。
      // ⚠️ 2026-10-23 复评实测修正：4 行档位**也必须进 Scroll** —— 它们留在外面时
      //    固定占 ~457vp，加上限高 420 的 Scroll，面板总高超过抽屉，顶部关闭带被挤成 0。
      //    现在整面板只有头部固定，其余全滚 + layoutWeight 收缩，任何视口都关得掉。
      Scroll() {
        Column() {

          this.settingsRow('字号', LEVEL_MAX, 'font')
          this.settingsRow('行距', LEVEL_MAX, 'line')
          this.settingsRow('页边距', LEVEL_MAX, 'margin')
          this.settingsRow('字重', WEIGHT_MAX, 'weight')

      // A1：明示「排版只对这本书生效」+ 恢复全局出路（党哥拍板默认仅这一本）
      Row() {
        Text(this.book === null ? '排版跟随全局设置' : `排版仅对《${this.title}》生效`)
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.hasOverride) {
          Text('应用到所有书')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.accent)
            .height(34)
            .accessibilityText('把当前排版应用到所有书')
            .onClick(() => {
              // 把当前这本书的排版升格为全局默认（覆盖仍留着，其他书随后续）
              this.prefs.saveLevels(this.levels);
              this.prefs.saveTheme(this.theme);
              this.prefs.saveFontFamily(this.fontFamily);
              this.applyPrefsToLayout();
            })
          Text('恢复全局')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.accent)
            .height(34)
            .accessibilityText('恢复全局排版')
            .onClick(() => {
              if (this.book !== null) {
                this.prefs.clearBookOverride(this.book.id);
              }
              this.hasOverride = false;
              this.applyPrefsToLayout();
            })
        }
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_SM, bottom: RR_SP_SM })

      Row({ space: 8 }) {
        Text('主题')
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        // 四个主题横滚（与下面的字体行一致）：放不下的情况不会挤成一团
        Scroll() {
          Row({ space: 8 }) {
            // A2：自动放最前（档位循环同款：第一项是默认推荐）
            this.themeChip(THEME_AUTO)
            this.themeChip(THEME_DARK)
            this.themeChip(THEME_LIGHT)
            this.themeChip(THEME_SEPIA)
            this.themeChip(THEME_GREEN)
          }
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_3XL })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      Column() {
        Row() {
          Text('字体')
            .fontSize(RR_FS_BODY)
            .fontColor(this.palette.text)
          Blank()
          Text(this.fontFamily.length === 0 ? '系统默认' : this.fontFamily)
            .fontSize(RR_FS_MICRO)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ bottom: RR_SP_XL })

        Scroll() {
          Row({ space: 8 }) {
            this.fontChip('系统默认', '')
            ForEach(this.fontChoices(), (f: FontEntry) => {
              this.fontChip(f.displayName, f.familyName)
            }, (f: FontEntry) => 'fc-' + f.id)
          }
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_3XL })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      // 音色行（仅设备支持 TTS 时出现；点选即试听当前页）
      if (this.ttsSupported) {
        Column() {
          Row() {
            Text('音色')
              .fontSize(RR_FS_BODY)
              .fontColor(this.palette.text)
            Blank()
            Text('点选试听')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .margin({ bottom: RR_SP_XL })

          Scroll() {
            Row({ space: 8 }) {
              this.personChip('聆小珊（女）', 13)
              this.personChip('凌飞哲（男）', 21)
            }
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_3XL })
        .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

        // 语速行（2026-10-22 P0-3：语速从"存了不生效的断头路"接通为真控制）
        Column() {
          Row() {
            Text('语速')
              .fontSize(RR_FS_BODY)
              .fontColor(this.palette.text)
            Blank()
            Text('下一段起生效')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .margin({ bottom: RR_SP_XL })

          Scroll() {
            Row({ space: 8 }) {
              this.speedChip('0.5×', 0.5)
              this.speedChip('0.75×', 0.75)
              this.speedChip('1.0×', 1.0)
              this.speedChip('1.25×', 1.25)
              this.speedChip('1.5×', 1.5)
              this.speedChip('2.0×', 2.0)
            }
          }
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
        }
        .width('100%')
        .padding({ left: RR_SP_4XL, right: RR_SP_4XL, top: RR_SP_3XL, bottom: RR_SP_3XL })
        .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
      }

      Text('更多设置（字体下载 / 隐私）›')
        .fontSize(RR_FS_LABEL)
        .fontColor(this.palette.text2)
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .stateStyles({ pressed: { opacity: 0.6 } })
        .accessibilityText('更多设置')
        .onClick(() => {
          this.showSettings = false;
          this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
        })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.overlay)
    .borderRadius({ topLeft: 12, topRight: 12 })
    .border({ width: { top: 1, left: 1, right: 1 }, color: this.palette.line })
    .transition(TransitionEffect.translate({ y: SETTINGS_SLIDE_VP })
      .animation({ duration: PANEL_ANIM_MS, curve: Curve.FastOutSlowIn }))
    .onClick(() => {
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ---- 正文（点中间开菜单，点两侧翻页）----
      Column() {
        if (this.hint.length > 0) {
          Text(this.hint)
            .fontSize(RR_FS_LABEL)
            .fontColor(this.palette.text2)
            .margin({ top: RR_SP_VOID })
          // 审查报告 B7：明确告诉用户有重试出路（点击画面任意处 = 重试本章）
          Text('轻点屏幕重试，或用上方返回键回书架')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.text3)
            .margin({ top: RR_SP_XL })
        } else if (this.loading) {
          // 审查报告 B22：loading 之前是从不被读的死状态 —— 大书首屏一片空白像"点开打不开"
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.palette.text2)
            Text('正在打开…')
              .fontSize(RR_FS_META)
              .fontColor(this.palette.text3)
              .margin({ top: RR_SP_XL })
          }
          .width('100%')
          .margin({ top: RR_SP_TOP })
        } else {
          Text(this.pageText)
            .fontSize(this.fontSizeFp)
            .lineHeight(this.lineHeightVp)
            .fontFamily(this.fontFamily)      // '' = 系统默认；必须与 TextPaginator 测量时一致
            .fontWeight(this.fontWeightValue) // 必须来自档位表（测量与渲染共用，否则断行不一致）
            .fontColor(this.palette.text)
            .width('100%')
            .textAlign(TextAlign.Start)
            // 长按正文 ⇒ 摘录当前页（P0-2 三件套）。与单击（翻页/唤菜单）、
            // 横滑（翻页）不冲突：LongPressGesture 有独立的时长门槛（默认 500ms）
            .gesture(LongPressGesture({ repeat: false }).onAction(() => {
              this.openHighlightPanel();
            }))
        }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.marginVp,
        right: this.marginVp,
        top: HEADER_VP,
        bottom: FOOTER_VP
      })
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      .opacity(this.pageOpacity)
      .translate({ x: this.shiftX + this.dragX })
      .onAreaChange((oldValue: Area, newValue: Area) => {
        const width: number = newValue.width as number;
        const height: number = newValue.height as number;
        this.viewWidthVp = width;
        this.viewHeightVp = height;
        if (width <= 0 || height <= 0) {
          return;
        }
        if (!this.areaReady) {
          this.areaReady = true;
          this.laidOutWidthVp = width;
          this.laidOutHeightVp = height;
          if (this.chapterCount > 0) {
            this.openChapter(this.pendingChapter, this.pendingOffset);
            // 首帧兜底这条路径同样要补字数普查 —— 它才是绝大多数用户真正走进来的那条。
            // init() 里 601 行的 if (this.areaReady) 几乎恒不成立（布局晚于那条 await 链），
            // 于是加了这行之前：书打开了，但 census 一次都没跑，chapters.char_count 全空，
            // 进度退回「按章数」的虚高口径（实测 8.67% vs 真实 4.66%）。
            // surveyChars 内部有 surveying 幂等守卫，两处重复调用安全。
            this.surveyChars().catch((e: Error) => {
              hilog.warn(DOMAIN, TAG, 'surveyChars failed: %{public}s', JSON.stringify(e));
            });
          }
          return;
        }
        // 尺寸变了（旋转 / 分屏 / 系统字号缩放）→ 旧页表作废，按字符偏移原地重排。
        // 不做这一步的话，页表还是旧视口的，页面会overflow（最后一行被裁）。
        if (Math.abs(width - this.laidOutWidthVp) > 1 || Math.abs(height - this.laidOutHeightVp) > 1) {
          this.laidOutWidthVp = width;
          this.laidOutHeightVp = height;
          if (this.chapterCount > 0 && this.book !== null) {
            const keep: number = this.pages.length > 0 && this.pageIndex < this.pages.length
              ? this.pages[this.pageIndex].start
              : 0;
            this.openChapter(this.chapterIndex, keep);
          }
        }
      })
      // 读屏可达性：正文区对读屏用户念明操作方式（点击三区分屏的等效说明；
      // 翻页的无障碍替代路径 = 目录/标记/搜索跳转，均为带标签的真按钮）
      .accessibilityText('正文：点左边缘上一页，右边缘下一页，中间唤出菜单；也可用目录、标记、搜索跳转位置')
      .onClick((event: ClickEvent) => {
        const third: number = this.viewWidthVp / 3;
        if (this.showToc) {
          this.showToc = false;
          return;
        }
        if (this.showSettings) {
          this.showSettings = false;
          return;
        }
        if (this.showMenu) {
          this.showMenu = false;
          return;
        }
        if (this.hint.length > 0) {
          // 错误态出路（审查报告 B7）：点击 = 重试本章。不给出路的话，
          // "这一章读取失败" = 菜单/目录/返回全部开不出来，整本书读不了。
          if (this.chapterCount > 0 && this.book !== null) {
            this.openChapter(this.chapterIndex, 0);
          }
          return;
        }
        if (event.x < third) {
          this.turnPage(-1);
        } else if (event.x > third * 2) {
          this.turnPage(1);
        } else {
          this.showMenu = true;
        }
      })
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 12 })
          .onActionStart(() => {
            // 菜单/目录开着时整轮忽略：否则拖拽会把浮层和正文一起拖
            this.dragging = !this.showMenu && !this.showToc && !this.showSettings && this.hint.length === 0;
            this.dragX = 0;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (!this.dragging) {
              return;
            }
            this.dragX = this.dragOffsetOf(event.offsetX);
          })
          .onActionEnd((event: GestureEvent) => {
            if (!this.dragging) {
              return;
            }
            this.dragging = false;
            this.settleDrag(event.offsetX, event.velocityX);
          })
          .onActionCancel(() => {
            if (!this.dragging) {
              return;
            }
            this.dragging = false;
            this.getUIContext().animateTo({ duration: DRAG_BACK_MS, curve: Curve.EaseOut }, () => {
              this.dragX = 0;
            });
          })
      )

      // ---- 页脚（唯一常驻控件）----
      // 朗读激活时换成播放条（暂停/继续 + 段进度 + 停止），停播恢复章名/页码。
      // 高度不变（FOOTER_VP=30）：文字按钮 + responseRegion 撑热区，不新增浮层。
      Column() {
        if (this.speakActive) {
          // 播放条入场：从下方淡入（停播时章名/页码反向退场）—— 页脚是阅读页
          // 唯一常驻控件，朗读起停的"换脏器"不该是硬切换（2026-10-23 复评整改）
          Row() {
            Text(this.speakPaused ? '继续' : '暂停')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text)
              .responseRegion({ x: -8, y: -8, width: 56, height: 44 })
              .accessibilityText(this.speakPaused ? '继续朗读' : '暂停朗读')
              // 播放/暂停一拍即走：放大 1.15，EaseOut 归位（与保存脉冲同语言）
              .scale({ x: this.speakKick ? 1.15 : 1.0, y: this.speakKick ? 1.15 : 1.0 })
              .animation({ duration: 220, curve: Curve.EaseOut })
              .onClick(() => this.toggleSpeak())
            Text(this.speakPreparing ? '准备中' : this.speakProgress)
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            // 朗读定时：点按循环 关→15→30→60→关。显示剩余分钟（向上取整），
            // 未设档位显示「定时」。纯文本按钮（不新增图标资源），字号与播放条一致。
            Text(this.sleepMin === 0
              ? '定时'
              : (this.sleepLeft > 0 ? `${Math.ceil(this.sleepLeft / 60)}分` : `${this.sleepMin}分`))
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.sleepMin === 0 ? this.palette.text3 : this.palette.text)
              .responseRegion({ x: -6, y: -8, width: 60, height: 44 })
              .accessibilityText(this.sleepMin === 0 ? '设置朗读定时' : `朗读定时剩余${Math.ceil(this.sleepLeft / 60)}分钟`)
              .onClick(() => this.pickSleep())
            Text('停止')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text)
              .responseRegion({ x: -8, y: -8, width: 56, height: 44 })
              .accessibilityText('停止朗读')
              .onClick(() => this.stopSpeak())
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: 10 }))
            .animation({ duration: 180, curve: Curve.EaseOut }))
        } else {
          Row() {
            Text(this.chapterTitle)
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .transition(TransitionEffect.OPACITY
            .combine(TransitionEffect.translate({ y: -10 }))
            .animation({ duration: 180, curve: Curve.EaseOut }))
        }
      }
      .width('100%')
      .padding({ left: this.marginVp, right: this.marginVp, bottom: RR_SP_2XL })
      .width('100%')
      .height(FOOTER_VP)
      .justifyContent(FlexAlign.End)

      // ---- 浮层：点屏中间才出现 ----
      if (this.showMenu) {
        // 外层全屏包裹（继承 Stack 的 Bottom 对齐，铺满窗口）；
        // 内层才是菜单本体 —— 朗读时高度让出页脚 FOOTER_VP，bottomBar 随之抬起，
        // 页脚播放条（暂停/进度/停止）回到可点击区域。
        // 反例（2026-10-18 实测）：直接给菜单 Column 缩高 + Bottom 对齐 =
        // 顶部下移、底部不动，播放条照样被 bottomBar 尾部的空 onClick 吞。
        Column() {
          Column() {
            this.topBar()
            Blank()
            this.bottomBar()
          }
          .width('100%')
          .height(this.speakActive ? 'calc(100% - ' + FOOTER_VP + 'vp)' : '100%')
          .onClick(() => {
            this.showMenu = false;
          })
        }
        .width('100%')
        .height('100%')
        // 中央菜单整体渐入（2026-10-23 复评整改）：此前 showMenu 直接渲染、
        // 上下两栏瞬现——与目录抽屉/设置抽屉/摘录卡的转场语言不一致。
        // 方向性滑入在各栏 builder 内挂（topBar 自上、bottomBar 自下）
        .transition(TransitionEffect.OPACITY
          .animation({ duration: 160, curve: Curve.EaseOut }))
        // 自身对命中测试透明：让位出的页脚播放条区域要能点到 footer 的按钮
        // （Default 模式下全屏容器自身会吞掉落点 —— 2026-10-18 实测，
        // 不加这行播放条照样死区，只是不再被 bottomBar 盖而是被本层盖）
        .hitTestBehavior(HitTestMode.Transparent)
      }

      // ---- 目录（左抽屉：不铺满窗口，右侧留白透出正文，点右侧关闭）----
      if (this.showToc) {
        Row() {
          this.tocPanel()
          Column()
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.showToc = false;
            })
        }
        .width('100%')
        .height('100%')
      }

      // ---- 设置抽屉（底出、不遮满：上半透出正文，改一下上面立刻跟着变）----
      if (this.showSettings) {
        Column() {
          // 顶部关闭带：**固定最小高度**（原来是 layoutWeight(1)，会被长内容
          // 挤成 0 像素，面板铺满全屏且点不关 —— 2026-10-23 复评实测的坑）。
          Column()
            .width('100%')
            .height(SETTINGS_STRIP_VP)
            .onClick(() => {
              this.showSettings = false;
            })
          // 面板吃满剩余高度；内部 Scroll 用 layoutWeight 收缩，
          // 所以「更多设置」在任何视口都滚得到，关闭带也永远点在得到。
          Column() {
            this.settingsPanel()
          }
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
      }

      // ---- 摘录面板（P0-2）：居中卡片 + 半透明遮罩，点遮罩取消 ----
      if (this.showHighlight) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showHighlight = false;
            })
          Column() {
            Column()
              .layoutWeight(1)
              .onClick(() => {
                this.showHighlight = false;
              })
            this.highlightEditor()
            Column()
              .layoutWeight(1)
              .onClick(() => {
                this.showHighlight = false;
              })
          }
          .width('100%')
          .height('46%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
