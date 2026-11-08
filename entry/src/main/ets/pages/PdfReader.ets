/**
 * PDF 阅读页（一期）。
 *
 * ── 为什么是**独立页面**，而不是塞进 Reader.ets ──
 * `Reader.ets` 整条管线吃的是「章内字符偏移」：分页由 `PageTableBuilder` 按字符算，
 * 进度存 `chapterIndex + charOffset`，摘录/书签/朗读高亮全都建立在这个坐标系上。
 * PDF 是**固定版式**，没有字符偏移这回事。硬塞进去只会让两套坐标系互相污染，
 * 所以单独一个页面，书架点击时**一个分支**分流过来。
 *
 * ── 为什么用 `PdfView` 组件，而不是像 JustPDF 那样自己光栅化 ──
 * 组件自带：缩放、连续滚动、单双页、**文字搜索高亮**、**文字选区**。
 * 自己光栅（Worker 里 `page.getCustomPagePixelMap()`）要多写 400+ 行手势，
 * 而且**做不出文字选区** —— 二期要做摘录就只能退回组件路线。体积上两者都是 0 KB。
 *
 * ── 页面口径（党哥 2026-11-05：我们的 PDF 就是论文和电子书文档） ──
 * 两类都是**有文字层**的，所以默认「适应宽度」：
 *   · 论文常是双栏，适应页面会小到看不清正文；
 *   · 电子书单栏，适应宽度也正好铺满手机屏。
 * 代价是长页需要纵向滚动 —— 连续滚动模式本来就是为这个设计的。
 *
 * ── 一期明确**不做**（防止范围蔓延） ──
 * 加密 PDF 输密码、OCR、文字重排、朗读、批注编辑、PDF 大纲目录。
 * 加密书在**导入时**就拒掉（见 PdfProbe），不会出现在书架里点开一片空白。
 */
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookDb } from '../data/BookDb';
import { BookRecord, ReadingProgress, ProgressSnapshot } from '../common/Types';
import { Palette, paletteOf, THEME_LIGHT } from '../common/Theme';
import { currentPalette } from '../common/ThemeRuntime';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { MIN_SESSION_MS, ReadSession } from '../engine/stats/ReadStats';
import {
  clampPage, pageLabel, parsePageInput, percentOfPage, startPageOf
} from '../engine/pdf/PdfPages';
import {
  RR_FS_TITLE, RR_FS_HEADING, RR_FS_BODY, RR_FS_META, RR_FS_DIGIT, RR_FS_MICRO,
  RR_SP_XS, RR_SP_SM, RR_SP_MD, RR_SP_LG, RR_SP_XL, RR_SP_2XL, RR_SP_3XL
} from '../theme/RrTokens';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const PHASE_LOADING: string = 'loading';
const PHASE_READY: string = 'ready';
const PHASE_FAILED: string = 'failed';

/**
 * 攒够几页才落一次进度盘。
 * 连续滚动模式下 `registerPageChangedListener` 每翻一页都会回调，
 * 300 页的论文快速滚到底会写 300 次库 —— 没必要，也不能完全等到退出才写
 * （被杀进程就丢）。折中 5 页。
 */
const PERSIST_EVERY_PAGES: number = 5;

/**
 * 路由参数。
 * ⚠️ 必须定义成 interface 再 `as` —— ArkTS 禁止 `params['bookId']` 这种索引访问
 * （`arkts-no-props-by-index`，编译期就拦）。Reader.ets 里是同一个写法。
 */
interface PdfReaderParams {
  bookId: string;
}

@Entry
@Component
struct PdfReader {
  @State private phase: string = PHASE_LOADING;
  @State private errText: string = '';
  @State private title: string = '';
  @State private total: number = 0;
  @State private pageIndex: number = 0;
  @State private palette: Palette = paletteOf(THEME_LIGHT);
  /** 系统深浅（P0-1）：EntryAbility 写 AppStorage，@Watch 重算色板 */
  @StorageProp('systemDark') @Watch('onSystemDarkChanged') systemDark: boolean = false;
  /** 跳页面板是否展开 */
  @State private showJump: boolean = false;
  @State private jumpText: string = '';
  @State private jumpHint: string = '';
  /** 搜索面板 */
  @State private showSearch: boolean = false;
  @State private searchText: string = '';
  @State private searchCount: number = 0;
  @State private searchIndex: number = 0;
  @State private searching: boolean = false;

  private book: BookRecord | null = null;
  private bookId: string = '';
  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();
  private controller: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  private pagesSincePersist: number = 0;
  private sessionStartAt: number = 0;
  private sessionPage: number = -1;
  /** loadDocument 是否已经成功（避免 onPageHide 时对空文档操作） */
  private loaded: boolean = false;

  /** 系统深浅变了（控制中心切换）→ 只换色板，不动页面栈 / 滚动位置（P0-1） */
  private onSystemDarkChanged(): void {
    this.palette = currentPalette(this.prefs.effectiveTheme(this.bookId));
  }

  aboutToAppear(): void {
    const ctx: Context = this.getUIContext().getHostContext() as Context;
    const params = this.getUIContext().getRouter().getParams() as PdfReaderParams;
    this.bookId = params !== null && params !== undefined && typeof params.bookId === 'string' ? params.bookId : '';
    // 主题与阅读页同源：`effectiveTheme` 是"这本书的覆盖优先、全局兜底"
    // （党哥 2026-10-25 拍板「仅这一本」）⇒ PDF 页不能另立一套规则，
    // 否则同一本书的文字版和 PDF 版会一深一浅。
    this.prefs.open(ctx);
    this.palette = currentPalette(this.prefs.effectiveTheme(this.bookId));
    if (this.bookId.length === 0) {
      this.phase = PHASE_FAILED;
      this.errText = '找不到这本书';
      return;
    }
    this.open();
  }

  private async open(): Promise<void> {
    try {
      await this.db.open(this.getUIContext().getHostContext() as Context);
      const b: BookRecord | null = await this.db.getBook(this.bookId);
      if (b === null) {
        this.phase = PHASE_FAILED;
        this.errText = '找不到这本书';
        return;
      }
      this.book = b;
      this.title = b.title;

      // 续读定位：chapterIndex 就是页码（见 PdfPages 顶部注释）。
      // ⚠️ 起始页要等 load 完拿到 total 才能最终确定 —— 用户可能换了一份同名 PDF、
      //    页数变了，旧页码会越界。所以这里只把两个线索都带上，夹紧交给 load。
      const p = await this.db.getProgress(this.bookId);
      let startPage: number = 0;
      let startPct: number = 0;
      if (p !== null && p !== undefined) {
        startPage = Number.isInteger(p.chapterIndex) && p.chapterIndex > 0 ? p.chapterIndex : -1;
        startPct = p.percent;
      }

      await this.load(startPage, startPct);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pdf open failed: %{public}s', JSON.stringify(e));
      this.phase = PHASE_FAILED;
      this.errText = '这本 PDF 打不开';
    }
  }

  private async load(startPage: number, startPct: number): Promise<void> {
    const b: BookRecord | null = this.book;
    if (b === null) {
      return;
    }
    try {
      // ⚠️ initPageIndex 是 0 基。文档明确支持带初始页 ⇒ 续读不用自己滚到位置。
      const r: pdfService.ParseResult = await this.controller.loadDocument(b.path, '', Math.max(0, startPage));
      if (r !== pdfService.ParseResult.PARSE_SUCCESS) {
        this.phase = PHASE_FAILED;
        this.errText = r === pdfService.ParseResult.PARSE_ERROR_PASSWORD
          ? '这本 PDF 有密码，暂时打不开'
          : '这本 PDF 文件损坏了';
        return;
      }
      this.loaded = true;
      this.total = this.controller.getPageCount();
      // 页码优先、percent 兜底，并按真实总页数夹紧（换过同名文件时旧页码会越界）
      this.pageIndex = startPageOf(startPage, startPct, this.total);
      // 注册翻页回调：连续滚动时每进入一页都会触发
      this.controller.registerPageChangedListener((idx: number) => {
        this.onPageChanged(idx);
      });
      this.phase = PHASE_READY;
      this.sessionStartAt = Date.now();
      this.sessionPage = this.pageIndex;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'pdf load failed: %{public}s', JSON.stringify(e));
      this.phase = PHASE_FAILED;
      this.errText = '这本 PDF 打不开';
    }
  }

  private onPageChanged(idx: number): void {
    if (!Number.isInteger(idx) || idx < 0) {
      return;
    }
    if (idx === this.pageIndex) {
      return;
    }
    this.pageIndex = clampPage(idx, this.total);
    this.pagesSincePersist++;
    if (this.pagesSincePersist >= PERSIST_EVERY_PAGES) {
      this.persistProgress(false);
    }
  }

  /**
   * 写进度。**两个写库都完成后**才发 AppStorage 信号 —— 书架靠这个信号刷新进度条。
   * 这条纪律是从 Reader 那边抄来的（2026-09-26 审核驳回第 3 条的根因：
   * fire-and-forget 导致返回书架时查库跑在写入前面，进度显示 0%）。
   */
  private persistProgress(force: boolean): void {
    const b: BookRecord | null = this.book;
    if (b === null || !this.loaded || this.total <= 0) {
      return;
    }
    if (!force && this.pagesSincePersist < PERSIST_EVERY_PAGES) {
      return;
    }
    this.pagesSincePersist = 0;
    const p: ReadingProgress = {
      bookId: b.id,
      chapterIndex: this.pageIndex,
      charOffset: 0,
      percent: percentOfPage(this.pageIndex, this.total),
      updatedAt: Date.now()
    };
    Promise.all([
      this.db.saveProgress(p),
      this.db.touchLastRead(b.id, p.updatedAt)
    ]).then(() => {
      const snap: ProgressSnapshot = { bookId: p.bookId, percent: p.percent };
      AppStorage.setOrCreate('progressSaved', snap);
      AppStorage.setOrCreate('progressSavedAt', p.updatedAt);
    }).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pdf persist failed: %{public}s', e.message);
    });
  }

  /** 阅读时长：与 Reader 共用 `read_sessions` 表，统计页不用为 PDF 单独开一套 */
  private flushSession(): void {
    const started: number = this.sessionStartAt;
    const page: number = this.sessionPage;
    this.sessionStartAt = 0;
    this.sessionPage = -1;
    const b: BookRecord | null = this.book;
    if (b === null || started <= 0 || page < 0) {
      return;
    }
    const now: number = Date.now();
    if (now - started < MIN_SESSION_MS) {
      return;
    }
    const s: ReadSession = { bookId: b.id, chapterIndex: page, startAt: started, endAt: now };
    this.db.addSession(s).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'pdf save session failed: %{public}s', e.message);
    });
  }

  // ── 搜索 ──────────────────────────────────────────────────────────
  //
  // 论文场景的关键能力：找一个术语、一个公式编号在哪页。
  // `searchKey` 是**组件自带**的：除了返回匹配总数，还会把全文命中处高亮出来，
  // 再多一层"上一个/下一个"用 `setSearchIndex` 在命中之间跳 —— 缩放与滚动由组件管，
  // 我们不用自己算坐标。

  private doSearch(text: string): void {
    const t: string = text.trim();
    this.searchText = text;
    if (t.length === 0) {
      this.controller.clearSearch();
      this.searchCount = 0;
      this.searchIndex = 0;
      this.searching = false;
      return;
    }
    this.searching = true;
    // 回调参数是**匹配总数**（不是页码）。搜完自动落到第一个命中。
    this.controller.searchKey(t, (count: number) => {
      this.searching = false;
      const n: number = Number.isInteger(count) && count > 0 ? count : 0;
      this.searchCount = n;
      if (n > 0) {
        this.controller.setSearchIndex(0);
        this.searchIndex = 0;
      } else {
        this.searchIndex = 0;
      }
    });
  }

  /** 在命中之间循环跳（delta = ±1） */
  private searchStep(delta: number): void {
    const n: number = this.searchCount;
    if (n <= 0) {
      return;
    }
    // 循环而不是夹在两端：读到最后一个命中时再按"下一个"回到第一个，
    // 比"点了没反应"好（这也是各家阅读器的通例）
    const next: number = (this.searchIndex + delta + n) % n;
    this.controller.setSearchIndex(next);
    this.searchIndex = next;
  }

  private closeSearch(): void {
    this.showSearch = false;
    this.searching = false;
    this.searchCount = 0;
    this.searchIndex = 0;
    this.searchText = '';
    // 关面板 = 不搜了，把页面上的高亮清掉（否则满屏黄条留在书上）
    try {
      this.controller.clearSearch();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'closeSearch clearSearch failed');
    }
  }

  private jumpTo(text: string): void {
    const idx: number = parsePageInput(text, this.total);
    if (idx < 0) {
      // 输错就停在原地，只给提示 —— 不"猜个最近的"跳过去
      this.jumpHint = this.total > 0 ? ('请输入 1 ~ ' + this.total + ' 之间的页码') : '页数还没读出来';
      return;
    }
    this.jumpHint = '';
    this.showJump = false;
    this.jumpText = '';
    this.controller.goToPage(idx);
    this.pageIndex = idx;
    this.persistProgress(true);
  }

  onPageShow(): void {
    // 回前台重开计时（onPageHide 已清 0）
    if (this.loaded && this.sessionStartAt === 0) {
      this.sessionStartAt = Date.now();
      this.sessionPage = this.pageIndex;
    }
  }

  onPageHide(): void {
    this.persistProgress(true);
    this.flushSession();
  }

  aboutToDisappear(): void {
    this.persistProgress(true);
    this.flushSession();
    // 必须释放：文档原话「重复 loadDocument 不支持，后续调用前必须先 releaseDocument」。
    // 不释放的话，再次打开同一本书会冲突（要么空白，要么直接抛）。
    if (this.loaded) {
      try {
        this.controller.releaseDocument();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'pdf releaseDocument failed (ignored)');
      }
      this.loaded = false;
    }
  }

  /**
   * 系统返回键：先收浮层，再退出。
   * 与 Reader.ets 的 `onBackPress` 同一套语义（那个是 1.0.11 刚修好的）。
   */
  onBackPress(): boolean {
    if (this.showSearch) {
      this.closeSearch();
      return true;
    }
    if (this.showJump) {
      this.showJump = false;
      this.jumpHint = '';
      return true;
    }
    return false;
  }

  // ── UI ────────────────────────────────────────────────────────────

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
        .accessibilityText('返回')
        .onClick(() => this.getUIContext().getRouter().back())
      Column() {
        Text(this.title)
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('PDF')
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: RR_SP_MD })
      Text(this.total > 0 ? pageLabel(this.pageIndex, this.total) : '')
        .fontSize(RR_FS_META)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: RR_SP_2XL, right: RR_SP_3XL, top: RR_SP_XL, bottom: RR_SP_MD })
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
  }

  @Builder
  loadingView() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(this.palette.text3)
      Text('正在打开…')
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text3)
        .margin({ top: RR_SP_MD })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  failedView() {
    Column() {
      Text('打不开')
        .fontSize(RR_FS_HEADING)
        .fontColor(this.palette.text)
      Text(this.errText)
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text3)
        .margin({ top: RR_SP_SM })
        .textAlign(TextAlign.Center)
      Text('返回书架')
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text)
        .margin({ top: RR_SP_2XL })
        .padding({ left: RR_SP_2XL, right: RR_SP_2XL, top: RR_SP_SM, bottom: RR_SP_SM })
        .border({ width: 1, color: this.palette.line })
        .borderRadius(4)
        .onClick(() => this.getUIContext().getRouter().back())
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
  }

  @Builder
  pdfContent() {
    // ⚠️ PdfView 的五个参数在 d.ts 里都是**必填**（无 `?`），少给一个编译就过不了。
    PdfView({
      controller: this.controller,
      pageLayout: pdfService.PageLayout.LAYOUT_SINGLE,
      // 连续滚动：论文长页多，翻页式会让人一直点；连续滚动才像"看文档"
      isContinuous: true,
      showScroll: true,
      // 适应宽度：论文双栏的关键（适应页面会把正文缩到看不清）
      pageFit: pdfService.PageFit.FIT_WIDTH
    })
      .width('100%')
      .layoutWeight(1)
      // PDF 页面本身是白的，深色主题下这里会出现一块亮区 ——
      // 一期先保持原色（护眼只对文字书生效，多数阅读器也这么做）
      .backgroundColor(this.palette.bg)
  }

  @Builder
  bottomBar() {
    Row() {
      Text(this.total > 0 ? pageLabel(this.pageIndex, this.total) : '')
        .fontSize(RR_FS_DIGIT)
        .fontFamily('monospace')
        .fontColor(this.palette.text2)
      Blank()
      Text('搜索')
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text2)
        .padding({ left: RR_SP_LG, right: RR_SP_LG, top: RR_SP_XS, bottom: RR_SP_XS })
        .border({ width: 1, color: this.palette.line })
        .borderRadius(4)
        .margin({ right: RR_SP_MD })
        .onClick(() => {
          this.searchText = '';
          this.searchCount = 0;
          this.searchIndex = 0;
          this.searching = false;
          this.showSearch = true;
        })
      Text('跳页')
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text2)
        .padding({ left: RR_SP_LG, right: RR_SP_LG, top: RR_SP_XS, bottom: RR_SP_XS })
        .border({ width: 1, color: this.palette.line })
        .borderRadius(4)
        .onClick(() => {
          this.jumpText = '';
          this.jumpHint = '';
          this.showJump = true;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: RR_SP_2XL, right: RR_SP_2XL, top: RR_SP_SM, bottom: RR_SP_SM })
    .border({ width: { top: 1 }, color: this.palette.lineSoft })
  }

  @Builder
  searchPanel() {
    Column() {
      Row() {
        Text('在书里找')
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        Blank()
        Text('关闭')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .onClick(() => this.closeSearch())
      }
      .width('100%')

      Row() {
        TextInput({ text: this.searchText, placeholder: '关键词，如「注意力机制」' })
          .layoutWeight(1)
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
          .backgroundColor(this.palette.card)
          .borderRadius(4)
          .padding({ left: RR_SP_MD, right: RR_SP_MD, top: RR_SP_SM, bottom: RR_SP_SM })
          .onChange((v: string) => {
            this.searchText = v;
          })
          .onSubmit(() => this.doSearch(this.searchText))
        Text('查找')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.bg)
          .backgroundColor(this.palette.text)
          .padding({ left: RR_SP_LG, right: RR_SP_LG, top: RR_SP_SM, bottom: RR_SP_SM })
          .borderRadius(4)
          .margin({ left: RR_SP_SM })
          .onClick(() => this.doSearch(this.searchText))
      }
      .width('100%')
      .margin({ top: RR_SP_MD })

      // ⚠️ 条件里**就地读 @State**（本仓最贵的一条：
      //   条件表达式藏进 getter/方法体，ArkUI V1 的依赖插桩追不到，界面就不刷新）
      if (this.searching) {
        Text('搜索中…')
          .fontSize(RR_FS_MICRO)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_SM })
      } else if (this.searchCount > 0) {
        Row() {
          Text((this.searchIndex + 1) + ' / ' + this.searchCount + ' 处')
            .fontSize(RR_FS_MICRO)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
          Blank()
          Text('上一个')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.text2)
            .padding({ left: RR_SP_MD, right: RR_SP_MD, top: RR_SP_XS, bottom: RR_SP_XS })
            .border({ width: 1, color: this.palette.line })
            .borderRadius(4)
            .onClick(() => this.searchStep(-1))
          Text('下一个')
            .fontSize(RR_FS_META)
            .fontColor(this.palette.text2)
            .padding({ left: RR_SP_MD, right: RR_SP_MD, top: RR_SP_XS, bottom: RR_SP_XS })
            .border({ width: 1, color: this.palette.line })
            .borderRadius(4)
            .margin({ left: RR_SP_SM })
            .onClick(() => this.searchStep(1))
        }
        .width('100%')
        .margin({ top: RR_SP_SM })
        .alignItems(VerticalAlign.Center)
      } else if (this.searchText.trim().length > 0) {
        Text('没有找到')
          .fontSize(RR_FS_MICRO)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_SM })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: RR_SP_2XL, right: RR_SP_2XL, top: RR_SP_2XL, bottom: RR_SP_2XL })
    .backgroundColor(this.palette.bg)
    .border({ width: { bottom: 1 }, color: this.palette.line })
  }

  @Builder
  jumpPanel() {
    /**
     * 版式与 searchPanel() 必须保持一致（2026-11-05 党哥定）：
     * 第一行「标题 … 关闭」，第二行「输入框 + 主操作按钮」。
     * 原先这个面板把「取消」放在底部一排、搜索把「关闭」放在右上角，
     * 同一个「退出面板」的动作出现两种叫法、两个位置 —— 属于无谓的不一致。
     */
    Column() {
      Row() {
        Text('跳到第几页')
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        Blank()
        Text('关闭')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text3)
          .onClick(() => {
            this.showJump = false;
            this.jumpHint = '';
          })
      }
      .width('100%')

      Row() {
        TextInput({ text: this.jumpText, placeholder: '页码，例如 12 或 65%' })
          .type(InputType.Number)
          .layoutWeight(1)
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
          .backgroundColor(this.palette.card)
          .borderRadius(4)
          .padding({ left: RR_SP_MD, right: RR_SP_MD, top: RR_SP_SM, bottom: RR_SP_SM })
          .onChange((v: string) => {
            this.jumpText = v;
            this.jumpHint = '';
          })
          .onSubmit(() => this.jumpTo(this.jumpText))
        Text('跳转')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.bg)
          .backgroundColor(this.palette.text)
          .padding({ left: RR_SP_LG, right: RR_SP_LG, top: RR_SP_SM, bottom: RR_SP_SM })
          .borderRadius(4)
          .margin({ left: RR_SP_SM })
          .onClick(() => this.jumpTo(this.jumpText))
      }
      .width('100%')
      .margin({ top: RR_SP_MD })

      if (this.jumpHint.length > 0) {
        Text(this.jumpHint)
          .fontSize(RR_FS_MICRO)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_SM })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: RR_SP_2XL, right: RR_SP_2XL, top: RR_SP_2XL, bottom: RR_SP_2XL })
    .backgroundColor(this.palette.bg)
    .border({ width: { bottom: 1 }, color: this.palette.line })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.topBar()
        if (this.phase === PHASE_LOADING) {
          this.loadingView()
        } else if (this.phase === PHASE_FAILED) {
          this.failedView()
        } else {
          this.pdfContent()
        }
        if (this.phase === PHASE_READY) {
          this.bottomBar()
        }
      }
      .width('100%')
      .height('100%')

      /**
       * 搜索 / 跳页两个面板**一律贴顶**，不贴底。
       * 原因（2026-11-05 云真机实测）：键盘是**覆盖式**弹出（不改变窗口高度），
       * 面板贴在底部时，它的下半截正好被键盘盖住 —— 跳页盖住「跳转」，
       * 搜索盖住「上一个 / 下一个」。贴顶则与键盘永不相交。
       * 用 position 绝对定位而非撑满高度的容器：容器只有面板那么高，不会挡住下方 PDF。
       * 两个面板必须同进同出，别只修一个（另一处会被当成"没问题"漏掉）。
       */
      if (this.showSearch || this.showJump) {
        Column() {
          if (this.showSearch) {
            this.searchPanel()
          } else {
            this.jumpPanel()
          }
        }
        .width('100%')
        .position({ x: 0, y: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
