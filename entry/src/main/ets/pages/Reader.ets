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
import { router } from '@kit.ArkUI';
import { BookDb } from '../data/BookDb';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { BookRecord, ChapterRow, ReadingProgress } from '../common/Types';
import { BookSource, createBookSource } from '../engine/parser/BookSource';
import {
  fontSizeFpOf,
  fontWeightOf,
  layoutKey,
  LayoutLevels,
  LEVEL_MAX,
  lineHeightRatioOf,
  marginVpOf,
  WEIGHT_MAX
} from '../common/LayoutStyle';
import { PageRange, PageTable, pageOfChar } from '../engine/paginator/PageTableBuilder';
import { LayoutBox, PageCache, Paginator } from '../engine/paginator/Paginator';
import { FontStore } from '../data/FontStore';
import { MIN_SESSION_MS, ReadSession } from '../engine/stats/ReadStats';
import { FontEntry } from '../common/FontCatalog';
import { TextPaginator } from '../engine/paginator/TextPaginator';
import { Palette, paletteOf, themeLabel, THEME_DARK, THEME_GREEN, THEME_LIGHT, THEME_SEPIA, ThemeName } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';

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
  @Prop redColor: string = '';
  private onJump: (index: number) => void = () => {};

  build() {
    Row() {
      Text(this.title)
        .fontSize(13.5)
        .fontColor(this.current ? this.textColor : this.text2Color)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        // 无障碍：屏幕阅读器要能读出章名（AGC 审核会查）
        .accessibilityText(this.title)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 13, bottom: 13 })
    // 当前章 = 左侧红竖条。原来的序号列去掉了：它是"第几个条目"，与章名里作者写的
    // 「第N章」并列时数字对不上（版权页/序章也占号），真机反馈 #4 —— 只看数字必被误导；
    // 真实的位置指示由页脚 16/182 承担。
    .border({
      width: { left: 3 },
      color: this.current ? this.redColor : Color.Transparent
    })
    .onClick(() => this.onJump(this.index))
  }
}

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 页脚高度（vp）：正文可用高度要扣掉 */
const FOOTER_VP: number = 30;
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

@Entry
@Component
struct Reader {
  @State palette: Palette = paletteOf(THEME_DARK);
  @State title: string = '';
  @State chapterTitle: string = '';
  @State chapterIndex: number = 0;
  @State chapterCount: number = 0;
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

  aboutToAppear(): void {
    // 下载的字体**每次启动都要重新注册**（registerFont 只在进程内存活，不持久化）
    const store: FontStore = new FontStore(this.getUIContext().getHostContext() as Context);
    this.fontStore = store;
    this.registerLocalFonts(store);
    this.init();
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
    // **字体可能刚下载完** —— registerFont 只在进程内/本 UIContext 存活，
    // aboutToAppear 那次注册时字体还不存在；而设置页自己的注册不影响阅读页
    // （实测：下载后回来选楷体，正文毫无变化 —— 就是漏了这次补注册）。幂等，重复调用无害。
    if (this.fontStore === null) {
      this.fontStore = new FontStore(this.getUIContext().getHostContext() as Context);
    }
    this.registerLocalFonts(this.fontStore);
    this.applyPrefsToLayout();
  }

  /**
   * 把 prefs 的档位/主题/字体反映到当前页面；**变了才重排**，且按字符偏移复原位置（切档位不跳页）。
   *
   * 两个调用方：
   *   ① 从独立设置页返回（onPageShow）
   *   ② **阅读页内的设置抽屉**改档位（P11-2：边看边调，正文实时跟着变）
   * 两处共用同一段逻辑，避免"抽屉改了不生效 / 两边行为不一致"。
   */
  private applyPrefsToLayout(): void {
    const theme: ThemeName = this.prefs.getTheme();
    if (theme !== this.theme) {
      this.theme = theme;
      this.palette = paletteOf(theme);
      applyThemeToSystem(this.getUIContext().getHostContext() as Context, theme);
    }
    const family: string = this.prefs.getFontFamily();
    if (family !== this.fontFamily) {
      this.fontFamily = family;
      this.fontPath = this.fontStore === null ? '' : this.fontStore.uriForFamily(family);
    }
    hilog.info(DOMAIN, TAG, 'applyPrefs: family=[%{public}s] path=[%{public}s] key=%{public}s',
      this.fontFamily, this.fontPath, this.currentKey);
    // 抽屉里显示的档位跟着走（无论是否触发重排）
    this.levels = this.prefs.getLevels();
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
  }

  aboutToDisappear(): void {
    this.persistProgress(true);
    this.flushSession();
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
      this.prefs.open(this.getUIContext().getHostContext() as Context);
      this.theme = this.prefs.getTheme();
      this.palette = paletteOf(this.theme);

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

      this.fontFamily = this.prefs.getFontFamily();
      this.fontPath = this.fontStore === null ? '' : this.fontStore.uriForFamily(this.fontFamily);
      this.chapters = await this.db.listChapters(book.id);
      this.chapterCount = this.chapters.length;
      if (this.chapterCount === 0) {
        this.hint = book.format === 'epub' ? '这本书的目录解析失败' : '这本书没有解析出章节';
        this.loading = false;
        return;
      }
      const progress: ReadingProgress | null = await this.db.getProgress(book.id);
      this.pendingChapter = progress === null ? 0 : Math.min(progress.chapterIndex, this.chapterCount - 1);
      this.pendingOffset = progress === null ? 0 : progress.charOffset;
      this.loading = false;
      if (this.areaReady) {
        this.openChapter(this.pendingChapter, this.pendingOffset);
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
    const marginVp: number = marginVpOf(levels.marginLevel);
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
    // 渲染用的量全部**从 box 派生**（而不是在这里再查一遍档位表）——
    // 否则渲染端与测量端就是两个各算一遍的真源，任何一处表值/换算改动都会悄悄分叉
    this.fontSizeFp = box.fontSizeFp;
    this.lineHeightVp = this.getUIContext().px2vp(box.lineHeightPx);
    this.marginVp = marginVpOf(levels.marginLevel);

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

  private showPage(index: number): void {
    if (this.pages.length === 0) {
      return;
    }
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
    this.bookPercent = this.chapterCount === 0
      ? 0
      : (this.chapterIndex + this.pagePercent) / this.chapterCount;
    this.persistProgress(false);
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
  // 跟手翻页（Nothing OS 5.0「可中断动效」：拖到哪停到哪，松手才决定）
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
    if (index === this.chapterIndex) {
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
    this.showSettings = false; // 与设置抽屉互斥
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
    this.showToc = false; // 与目录抽屉互斥
    this.levels = this.prefs.getLevels();
    this.showSettings = true;
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
    this.prefs.saveLevels(next);
    this.applyPrefsToLayout();
  }

  private pickTheme(theme: ThemeName): void {
    this.prefs.saveTheme(theme);
    this.applyPrefsToLayout();
  }

  private pickFont(family: string): void {
    hilog.info(DOMAIN, TAG, 'pickFont: %{public}s', family);
    this.prefs.saveFontFamily(family);
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
      AppStorage.setOrCreate('progressSavedAt', Date.now());
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
        .fontSize(20)
        .fontColor(this.palette.text)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .responseRegion({ x: -5, y: -5, width: 44, height: 44 })
        .onClick(() => this.getUIContext().getRouter().back())
      Text(this.title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 6 })
        .layoutWeight(1)
      Text(this.chapterCount > 0 ? `${this.chapterIndex + 1}/${this.chapterCount}` : '')
        .fontSize(9.5)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 12, right: 18, top: 10, bottom: 12 })
    .backgroundColor(this.palette.overlay)
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
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
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row() {
        // 视觉 34vp，热区 44vp：触摸标准 ≥44，用 responseRegion 上下各撑 5
        // （.+ accessibilityText：屏幕朗读要能说出按钮名字，AGC 审核会查）
        Text('上一章')
          .fontSize(12.5)
          .fontColor(this.chapterIndex <= 0 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .accessibilityText('上一章')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => this.jumpToChapter(this.chapterIndex - 1))
        Text('目录')
          .fontSize(12.5)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .accessibilityText('目录')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => {
            this.openToc();
          })
        Text('A a')
          .fontSize(12.5)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .accessibilityText('排版设置')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => {
            this.openSettings();
          })
        Text('下一章')
          .fontSize(12.5)
          .fontColor(this.chapterIndex >= this.chapterCount - 1 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .accessibilityText('下一章')
          .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
          .onClick(() => this.jumpToChapter(this.chapterIndex + 1))
      }
      .width('100%')
      .margin({ bottom: 14 })

      this.segBar(this.bookPercent)

      Row() {
        Text(`${Math.round(this.bookPercent * 100)}%`)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 26 })
    .backgroundColor(this.palette.overlay)
    .border({ width: { top: 1 }, color: this.palette.lineSoft })
    .onClick(() => {
    })
  }

  @Builder
  tocPanel() {
    Column() {
      Row() {
        Text('CONTENTS')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.palette.text2)
        Blank()
        Text(this.tocQuery.length > 0
          ? `${this.tocFiltered.length}/${this.chapterCount}`
          : `${this.chapterCount}`)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 10 })

      // 章节搜索：三千章的书不必手滚着找
      Row() {
        Text('/')
          .fontSize(12)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .width(18)
        TextInput({ text: this.tocQuery, placeholder: '查找章节' })
          .fontSize(12.5)
          .fontColor(this.palette.text)
          .placeholderColor(this.palette.text3)
          .placeholderFont({ size: 12.5 })
          .caretColor(this.palette.red)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .padding(0)
          .height(36)
          .layoutWeight(1)
          .onChange((value: string) => {
            this.tocQuery = value;
            this.applyTocQuery(value);
          })
        if (this.tocQuery.length > 0) {
          Text('×')
            .fontSize(16)
            .fontColor(this.palette.text3)
            .width(26)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.tocQuery = '';
              this.applyTocQuery('');
            })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      if (this.tocFiltered.length === 0) {
        Text(this.tocQuery.length > 0 ? '没有匹配的章节' : '这本书没有解析出章节')
          .fontSize(12)
          .fontColor(this.palette.text3)
          .margin({ top: 30 })
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
                redColor: this.palette.red,
                onJump: (i: number) => this.jumpToChapter(i)
              })
            }
          }, (item: ChapterRow) => 'ch' + item.index)
        }
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

  /** 一行档位芯片（0 圆角、选中反白 —— 与独立设置页同一套视觉） */
  @Builder
  chipRow(kind: string, max: number) {
    Row({ space: 8 }) {
      ForEach(this.rangeOf(max), (n: number) => {
        Text(`${n}`)
          .fontSize(13)
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
          .fontSize(13.5)
          .fontColor(this.palette.text)
        Blank()
        Text(`${this.levelOf(kind)}/${max}`)
          .fontSize(9.5)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: 10 })
      this.chipRow(kind, max)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
  }

  @Builder
  themeChip(theme: ThemeName) {
    Text(themeLabel(theme))
      .fontSize(12.5)
      .fontColor(this.theme === theme ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.theme === theme ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(this.theme === theme ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: 16, right: 16 })
      .textAlign(TextAlign.Center)
      .accessibilityText(`主题 ${themeLabel(theme)}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickTheme(theme))
  }

  @Builder
  fontChip(label: string, family: string) {
    Text(label)
      .fontSize(12.5)
      .fontColor(this.fontFamily === family ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.fontFamily === family ? this.palette.text : this.palette.card)
      .borderWidth(1)
      .borderColor(this.fontFamily === family ? this.palette.text : this.palette.line)
      .height(34)
      .padding({ left: 16, right: 16 })
      .textAlign(TextAlign.Center)
      .maxLines(1)
      .accessibilityText(`字体 ${label}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickFont(family))
  }

  /** 设置抽屉：底出、不遮满（上半透出正文），改一下上面立刻跟着变 */
  @Builder
  settingsPanel() {
    Column() {
      Row() {
        Text('排版')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.palette.text2)
        Blank()
        Text('边改边看')
          .fontSize(9.5)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 4 })

      this.settingsRow('字号', LEVEL_MAX, 'font')
      this.settingsRow('行距', LEVEL_MAX, 'line')
      this.settingsRow('页边距', LEVEL_MAX, 'margin')
      this.settingsRow('字重', WEIGHT_MAX, 'weight')

      Row({ space: 8 }) {
        Text('主题')
          .fontSize(13.5)
          .fontColor(this.palette.text)
        // 四个主题横滚（与下面的字体行一致）：放不下的情况不会挤成一团
        Scroll() {
          Row({ space: 8 }) {
            this.themeChip(THEME_DARK)
            this.themeChip(THEME_LIGHT)
            this.themeChip(THEME_SEPIA)
            this.themeChip(THEME_GREEN)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      Column() {
        Row() {
          Text('字体')
            .fontSize(13.5)
            .fontColor(this.palette.text)
          Blank()
          Text(this.fontFamily.length === 0 ? '系统默认' : this.fontFamily)
            .fontSize(9.5)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .margin({ bottom: 10 })

        Scroll() {
          Row({ space: 8 }) {
            this.fontChip('系统默认', '')
            ForEach(this.fontChoices(), (f: FontEntry) => {
              this.fontChip(f.displayName, f.familyName)
            }, (f: FontEntry) => 'fc-' + f.id)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      Text('更多设置（字体下载 / 隐私）›')
        .fontSize(12.5)
        .fontColor(this.palette.text2)
        .width('100%')
        .height(48)
        .textAlign(TextAlign.Center)
        .accessibilityText('更多设置')
        .onClick(() => {
          this.showSettings = false;
          this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
        })
    }
    .width('100%')
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
            .fontSize(13)
            .fontColor(this.palette.text2)
            .margin({ top: 60 })
        } else {
          Text(this.pageText)
            .fontSize(this.fontSizeFp)
            .lineHeight(this.lineHeightVp)
            .fontFamily(this.fontFamily)      // '' = 系统默认；必须与 TextPaginator 测量时一致
            .fontWeight(this.fontWeightValue) // 必须来自档位表（测量与渲染共用，否则断行不一致）
            .fontColor(this.palette.text)
            .width('100%')
            .textAlign(TextAlign.Start)
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

      // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
      Column() {
        Row() {
          Text(this.chapterTitle)
            .fontSize(9.5)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '')
            .fontSize(9.5)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
        }
        .width('100%')
        .padding({ left: this.marginVp, right: this.marginVp, bottom: 12 })
      }
      .width('100%')
      .height(FOOTER_VP)
      .justifyContent(FlexAlign.End)

      // ---- 浮层：点屏中间才出现 ----
      if (this.showMenu) {
        Column() {
          this.topBar()
          Blank()
          this.bottomBar()
        }
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.showMenu = false;
        })
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
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showSettings = false;
            })
          this.settingsPanel()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
