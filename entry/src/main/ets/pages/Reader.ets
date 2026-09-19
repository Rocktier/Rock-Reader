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
import { fontSizeFpOf, fontWeightOf, layoutKey, LayoutLevels, lineHeightRatioOf, marginVpOf } from '../common/LayoutStyle';
import { PageRange, PageTable, pageOfChar } from '../engine/paginator/PageTableBuilder';
import { LayoutBox, PageCache, Paginator } from '../engine/paginator/Paginator';
import { FontStore } from '../data/FontStore';
import { MIN_SESSION_MS, ReadSession } from '../engine/stats/ReadStats';
import { FontEntry } from '../common/FontCatalog';
import { TextPaginator } from '../engine/paginator/TextPaginator';
import { Palette, paletteOf, THEME_DARK, ThemeName } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';

interface ReaderParams {
  bookId: string;
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
/** 判定为翻页的滑动距离比例（屏宽的倍数） */
const SWIPE_RATIO: number = 0.12;

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
  /** 上一次排版时的视口（vp）；用于识别"旋转/分屏/字号缩放"导致的尺寸变化 */
  private laidOutWidthVp: number = 0;
  private laidOutHeightVp: number = 0;
  private areaReady: boolean = false;
  /** 首屏：拿到视口尺寸后再排版 */
  private pendingChapter: number = 0;
  private pendingOffset: number = 0;
  private pagesSincePersist: number = 0;

  aboutToAppear(): void {
    // 下载的字体**每次启动都要重新注册**（registerFont 只在进程内存活，不持久化）
    const store: FontStore = new FontStore(getContext(this) as Context);
    this.fontStore = store;
    this.registerLocalFonts(store);
    this.init();
  }

  /** 把已下载字体注册进 ArkUI（渲染用）；测量端由 TextPaginator 用文件路径单独挂 */
  private registerLocalFonts(store: FontStore): void {
    const list: FontEntry[] = store.downloaded();
    for (let i: number = 0; i < list.length; i++) {
      try {
        this.getUIContext().getFont().registerFont({
          familyName: list[i].familyName,
          familySrc: store.pathOf(list[i])
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'registerFont failed: %{public}s', JSON.stringify(e));
      }
    }
  }

  onPageShow(): void {
    // 从设置页返回：主题/档位可能变了 → 变了才重排，并按字符偏移复原位置（切档位不跳页）
    this.prefs.open(getContext(this) as Context);
    this.prefs.reload();
    const theme: ThemeName = this.prefs.getTheme();
    if (theme !== this.theme) {
      this.theme = theme;
      this.palette = paletteOf(theme);
      applyThemeToSystem(getContext(this) as Context, theme);
    }
    this.fontFamily = this.prefs.getFontFamily();
    this.fontPath = this.fontStore === null ? '' : this.fontStore.pathForFamily(this.fontFamily);
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
      const params = router.getParams() as ReaderParams;
      this.prefs.open(getContext(this) as Context);
      this.theme = this.prefs.getTheme();
      this.palette = paletteOf(this.theme);

      await this.db.open(getContext(this) as Context);
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
      this.fontPath = this.fontStore === null ? '' : this.fontStore.pathForFamily(this.fontFamily);
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

  /** 由档位 + 视口算出这一套排版参数（唯一真源，测量与渲染共用） */
  private boxOf(levels: LayoutLevels): LayoutBox {
    const fontSizePx: number = fp2px(fontSizeFpOf(levels.fontSizeLevel));
    const lineHeightPx: number = fontSizePx * lineHeightRatioOf(levels.lineHeightLevel);
    const marginVp: number = marginVpOf(levels.marginLevel);
    const widthPx: number = vp2px(Math.max(1, this.viewWidthVp - marginVp * 2));
    const heightPx: number = vp2px(Math.max(1, this.viewHeightVp - FOOTER_VP - HEADER_VP));
    return {
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

    this.chapterIndex = index;
    this.chapterTitle = chapter.title;
    this.chapterText = text;
    this.fontSizeFp = fontSizeFpOf(levels.fontSizeLevel);
    this.lineHeightVp = px2vp(box.lineHeightPx);
    this.marginVp = marginVpOf(levels.marginLevel);

    const cacheKey: string = index + '|' + box.signature;
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
    animateTo({
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
        animateTo({ duration: FADE_IN_MS, curve: Curve.EaseOut }, () => {
          this.shiftX = 0;
          this.pageOpacity = 1;
        });
      }
    }, () => {
      this.pageOpacity = 0;
      this.shiftX = -dir * FADE_SHIFT_VP;
    });
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
    this.tocQuery = '';
    this.tocFiltered = this.chapters;
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
      return;
    }
    this.tocFiltered = this.chapters.filter(
      (c: ChapterRow) => c.title.toLowerCase().indexOf(key) >= 0
    );
  }

  // ------------------------------------------------------------------
  // 进度
  // ------------------------------------------------------------------

  private persistProgress(force: boolean): void {
    if (this.book === null || this.chapterCount === 0) {
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
    this.db.saveProgress(p).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'save progress failed: %{public}s', e.message);
    });
    this.db.touchLastRead(this.book.id, p.updatedAt).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'touch lastRead failed: %{public}s', e.message);
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
        .onClick(() => router.back())
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
    .backgroundColor(this.palette.bg)
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
        Text('上一章')
          .fontSize(12.5)
          .fontColor(this.chapterIndex <= 0 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => this.jumpToChapter(this.chapterIndex - 1))
        Text('目录')
          .fontSize(12.5)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openToc();
          })
        Text('A a')
          .fontSize(12.5)
          .fontColor(this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
        Text('下一章')
          .fontSize(12.5)
          .fontColor(this.chapterIndex >= this.chapterCount - 1 ? this.palette.text3 : this.palette.text)
          .height(34)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
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
    .backgroundColor(this.palette.bg)
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
          ForEach(this.tocFiltered, (item: ChapterRow) => {
            ListItem() {
              Row() {
                Text(`${item.index + 1}`)
                  .fontSize(9.5)
                  .fontFamily('monospace')
                  .fontColor(item.index === this.chapterIndex ? this.palette.red : this.palette.text3)
                  .width(30)
                Text(item.title)
                  .fontSize(13.5)
                  .fontColor(item.index === this.chapterIndex ? this.palette.text : this.palette.text2)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')
              .padding({ left: 20, right: 20, top: 13, bottom: 13 })
              .onClick(() => this.jumpToChapter(item.index))
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
    .width('100%')
    .height('62%')
    .backgroundColor(this.palette.bg)
    .borderRadius({ topLeft: 12, topRight: 12 })
    .border({ width: { top: 1, left: 1, right: 1 }, color: this.palette.line })
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
      .translate({ x: this.shiftX })
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
          .onActionEnd((event: GestureEvent) => {
            if (this.showMenu || this.showToc || this.hint.length > 0) {
              return;
            }
            const threshold: number = this.viewWidthVp * SWIPE_RATIO;
            if (event.offsetX <= -threshold) {
              this.turnPage(1);
            } else if (event.offsetX >= threshold) {
              this.turnPage(-1);
            }
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

      // ---- 目录 ----
      if (this.showToc) {
        Column() {
          Column()
            .width('100%')
            .layoutWeight(1)
            .onClick(() => {
              this.showToc = false;
            })
          this.tocPanel()
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
