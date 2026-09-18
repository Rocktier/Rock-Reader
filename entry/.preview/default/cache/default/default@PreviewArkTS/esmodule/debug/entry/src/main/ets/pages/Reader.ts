if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Reader_Params {
    palette?: Palette;
    title?: string;
    chapterTitle?: string;
    chapterIndex?: number;
    chapterCount?: number;
    pageIndex?: number;
    pageCount?: number;
    pagePercent?: number;
    bookPercent?: number;
    pageText?: string;
    showMenu?: boolean;
    showToc?: boolean;
    hint?: string;
    loading?: boolean;
    pageOpacity?: number;
    shiftX?: number;
    fontSizeFp?: number;
    lineHeightVp?: number;
    marginVp?: number;
    fontFamily?: string;
    db?: BookDb;
    prefs?: ReaderPrefs;
    book?: BookRecord | null;
    chapters?: ChapterRow[];
    source?: BookSource | null;
    chapterText?: string;
    pages?: PageRange[];
    fontStore?: FontStore | null;
    fontPath?: string;
    paginator?: Paginator;
    cache?: PageCache;
    theme?: ThemeName;
    currentKey?: string;
    viewWidthVp?: number;
    viewHeightVp?: number;
    laidOutWidthVp?: number;
    laidOutHeightVp?: number;
    areaReady?: boolean;
    pendingChapter?: number;
    pendingOffset?: number;
    pagesSincePersist?: number;
}
import hilog from "@ohos:hilog";
import router from "@ohos:router";
import { BookDb } from "@bundle:com.rocktier.rockreader/entry/ets/data/BookDb";
import { ReaderPrefs } from "@bundle:com.rocktier.rockreader/entry/ets/data/ReaderPrefs";
import type { BookRecord, ChapterRow, ReadingProgress } from '../common/Types';
import { createBookSource } from "@bundle:com.rocktier.rockreader/entry/ets/engine/parser/BookSource";
import type { BookSource } from "@bundle:com.rocktier.rockreader/entry/ets/engine/parser/BookSource";
import { fontSizeFpOf, layoutKey, lineHeightRatioOf, marginVpOf } from "@bundle:com.rocktier.rockreader/entry/ets/common/LayoutStyle";
import type { LayoutLevels } from "@bundle:com.rocktier.rockreader/entry/ets/common/LayoutStyle";
import { pageOfChar } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/PageTableBuilder";
import type { PageRange, PageTable } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/PageTableBuilder";
import { PageCache } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/Paginator";
import type { LayoutBox, Paginator } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/Paginator";
import { FontStore } from "@bundle:com.rocktier.rockreader/entry/ets/data/FontStore";
import type { FontEntry } from '../common/FontCatalog';
import { TextPaginator } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/TextPaginator";
import { paletteOf, THEME_DARK } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import type { Palette, ThemeName } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import { applyThemeToSystem } from "@bundle:com.rocktier.rockreader/entry/ets/common/SystemBar";
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
class Reader extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__palette = new ObservedPropertyObjectPU(paletteOf(THEME_DARK), this, "palette");
        this.__title = new ObservedPropertySimplePU('', this, "title");
        this.__chapterTitle = new ObservedPropertySimplePU('', this, "chapterTitle");
        this.__chapterIndex = new ObservedPropertySimplePU(0, this, "chapterIndex");
        this.__chapterCount = new ObservedPropertySimplePU(0, this, "chapterCount");
        this.__pageIndex = new ObservedPropertySimplePU(0, this, "pageIndex");
        this.__pageCount = new ObservedPropertySimplePU(0, this, "pageCount");
        this.__pagePercent = new ObservedPropertySimplePU(0, this, "pagePercent");
        this.__bookPercent = new ObservedPropertySimplePU(0, this, "bookPercent");
        this.__pageText = new ObservedPropertySimplePU('', this, "pageText");
        this.__showMenu = new ObservedPropertySimplePU(false, this, "showMenu");
        this.__showToc = new ObservedPropertySimplePU(false, this, "showToc");
        this.__hint = new ObservedPropertySimplePU('', this, "hint");
        this.__loading = new ObservedPropertySimplePU(true, this, "loading");
        this.__pageOpacity = new ObservedPropertySimplePU(1, this, "pageOpacity");
        this.__shiftX = new ObservedPropertySimplePU(0, this, "shiftX");
        this.__fontSizeFp = new ObservedPropertySimplePU(18, this, "fontSizeFp");
        this.__lineHeightVp = new ObservedPropertySimplePU(34.2, this, "lineHeightVp");
        this.__marginVp = new ObservedPropertySimplePU(20, this, "marginVp");
        this.__fontFamily = new ObservedPropertySimplePU('', this, "fontFamily");
        this.db = new BookDb();
        this.prefs = new ReaderPrefs();
        this.book = null;
        this.chapters = [];
        this.source = null;
        this.chapterText = '';
        this.pages = [];
        this.fontStore = null;
        this.fontPath = '';
        this.paginator = new TextPaginator();
        this.cache = new PageCache(4);
        this.theme = THEME_DARK;
        this.currentKey = '';
        this.viewWidthVp = 0;
        this.viewHeightVp = 0;
        this.laidOutWidthVp = 0;
        this.laidOutHeightVp = 0;
        this.areaReady = false;
        this.pendingChapter = 0;
        this.pendingOffset = 0;
        this.pagesSincePersist = 0;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Reader_Params) {
        if (params.palette !== undefined) {
            this.palette = params.palette;
        }
        if (params.title !== undefined) {
            this.title = params.title;
        }
        if (params.chapterTitle !== undefined) {
            this.chapterTitle = params.chapterTitle;
        }
        if (params.chapterIndex !== undefined) {
            this.chapterIndex = params.chapterIndex;
        }
        if (params.chapterCount !== undefined) {
            this.chapterCount = params.chapterCount;
        }
        if (params.pageIndex !== undefined) {
            this.pageIndex = params.pageIndex;
        }
        if (params.pageCount !== undefined) {
            this.pageCount = params.pageCount;
        }
        if (params.pagePercent !== undefined) {
            this.pagePercent = params.pagePercent;
        }
        if (params.bookPercent !== undefined) {
            this.bookPercent = params.bookPercent;
        }
        if (params.pageText !== undefined) {
            this.pageText = params.pageText;
        }
        if (params.showMenu !== undefined) {
            this.showMenu = params.showMenu;
        }
        if (params.showToc !== undefined) {
            this.showToc = params.showToc;
        }
        if (params.hint !== undefined) {
            this.hint = params.hint;
        }
        if (params.loading !== undefined) {
            this.loading = params.loading;
        }
        if (params.pageOpacity !== undefined) {
            this.pageOpacity = params.pageOpacity;
        }
        if (params.shiftX !== undefined) {
            this.shiftX = params.shiftX;
        }
        if (params.fontSizeFp !== undefined) {
            this.fontSizeFp = params.fontSizeFp;
        }
        if (params.lineHeightVp !== undefined) {
            this.lineHeightVp = params.lineHeightVp;
        }
        if (params.marginVp !== undefined) {
            this.marginVp = params.marginVp;
        }
        if (params.fontFamily !== undefined) {
            this.fontFamily = params.fontFamily;
        }
        if (params.db !== undefined) {
            this.db = params.db;
        }
        if (params.prefs !== undefined) {
            this.prefs = params.prefs;
        }
        if (params.book !== undefined) {
            this.book = params.book;
        }
        if (params.chapters !== undefined) {
            this.chapters = params.chapters;
        }
        if (params.source !== undefined) {
            this.source = params.source;
        }
        if (params.chapterText !== undefined) {
            this.chapterText = params.chapterText;
        }
        if (params.pages !== undefined) {
            this.pages = params.pages;
        }
        if (params.fontStore !== undefined) {
            this.fontStore = params.fontStore;
        }
        if (params.fontPath !== undefined) {
            this.fontPath = params.fontPath;
        }
        if (params.paginator !== undefined) {
            this.paginator = params.paginator;
        }
        if (params.cache !== undefined) {
            this.cache = params.cache;
        }
        if (params.theme !== undefined) {
            this.theme = params.theme;
        }
        if (params.currentKey !== undefined) {
            this.currentKey = params.currentKey;
        }
        if (params.viewWidthVp !== undefined) {
            this.viewWidthVp = params.viewWidthVp;
        }
        if (params.viewHeightVp !== undefined) {
            this.viewHeightVp = params.viewHeightVp;
        }
        if (params.laidOutWidthVp !== undefined) {
            this.laidOutWidthVp = params.laidOutWidthVp;
        }
        if (params.laidOutHeightVp !== undefined) {
            this.laidOutHeightVp = params.laidOutHeightVp;
        }
        if (params.areaReady !== undefined) {
            this.areaReady = params.areaReady;
        }
        if (params.pendingChapter !== undefined) {
            this.pendingChapter = params.pendingChapter;
        }
        if (params.pendingOffset !== undefined) {
            this.pendingOffset = params.pendingOffset;
        }
        if (params.pagesSincePersist !== undefined) {
            this.pagesSincePersist = params.pagesSincePersist;
        }
    }
    updateStateVars(params: Reader_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__palette.purgeDependencyOnElmtId(rmElmtId);
        this.__title.purgeDependencyOnElmtId(rmElmtId);
        this.__chapterTitle.purgeDependencyOnElmtId(rmElmtId);
        this.__chapterIndex.purgeDependencyOnElmtId(rmElmtId);
        this.__chapterCount.purgeDependencyOnElmtId(rmElmtId);
        this.__pageIndex.purgeDependencyOnElmtId(rmElmtId);
        this.__pageCount.purgeDependencyOnElmtId(rmElmtId);
        this.__pagePercent.purgeDependencyOnElmtId(rmElmtId);
        this.__bookPercent.purgeDependencyOnElmtId(rmElmtId);
        this.__pageText.purgeDependencyOnElmtId(rmElmtId);
        this.__showMenu.purgeDependencyOnElmtId(rmElmtId);
        this.__showToc.purgeDependencyOnElmtId(rmElmtId);
        this.__hint.purgeDependencyOnElmtId(rmElmtId);
        this.__loading.purgeDependencyOnElmtId(rmElmtId);
        this.__pageOpacity.purgeDependencyOnElmtId(rmElmtId);
        this.__shiftX.purgeDependencyOnElmtId(rmElmtId);
        this.__fontSizeFp.purgeDependencyOnElmtId(rmElmtId);
        this.__lineHeightVp.purgeDependencyOnElmtId(rmElmtId);
        this.__marginVp.purgeDependencyOnElmtId(rmElmtId);
        this.__fontFamily.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__palette.aboutToBeDeleted();
        this.__title.aboutToBeDeleted();
        this.__chapterTitle.aboutToBeDeleted();
        this.__chapterIndex.aboutToBeDeleted();
        this.__chapterCount.aboutToBeDeleted();
        this.__pageIndex.aboutToBeDeleted();
        this.__pageCount.aboutToBeDeleted();
        this.__pagePercent.aboutToBeDeleted();
        this.__bookPercent.aboutToBeDeleted();
        this.__pageText.aboutToBeDeleted();
        this.__showMenu.aboutToBeDeleted();
        this.__showToc.aboutToBeDeleted();
        this.__hint.aboutToBeDeleted();
        this.__loading.aboutToBeDeleted();
        this.__pageOpacity.aboutToBeDeleted();
        this.__shiftX.aboutToBeDeleted();
        this.__fontSizeFp.aboutToBeDeleted();
        this.__lineHeightVp.aboutToBeDeleted();
        this.__marginVp.aboutToBeDeleted();
        this.__fontFamily.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __palette: ObservedPropertyObjectPU<Palette>;
    get palette() {
        return this.__palette.get();
    }
    set palette(newValue: Palette) {
        this.__palette.set(newValue);
    }
    private __title: ObservedPropertySimplePU<string>;
    get title() {
        return this.__title.get();
    }
    set title(newValue: string) {
        this.__title.set(newValue);
    }
    private __chapterTitle: ObservedPropertySimplePU<string>;
    get chapterTitle() {
        return this.__chapterTitle.get();
    }
    set chapterTitle(newValue: string) {
        this.__chapterTitle.set(newValue);
    }
    private __chapterIndex: ObservedPropertySimplePU<number>;
    get chapterIndex() {
        return this.__chapterIndex.get();
    }
    set chapterIndex(newValue: number) {
        this.__chapterIndex.set(newValue);
    }
    private __chapterCount: ObservedPropertySimplePU<number>;
    get chapterCount() {
        return this.__chapterCount.get();
    }
    set chapterCount(newValue: number) {
        this.__chapterCount.set(newValue);
    }
    private __pageIndex: ObservedPropertySimplePU<number>;
    get pageIndex() {
        return this.__pageIndex.get();
    }
    set pageIndex(newValue: number) {
        this.__pageIndex.set(newValue);
    }
    private __pageCount: ObservedPropertySimplePU<number>;
    get pageCount() {
        return this.__pageCount.get();
    }
    set pageCount(newValue: number) {
        this.__pageCount.set(newValue);
    }
    private __pagePercent: ObservedPropertySimplePU<number>;
    get pagePercent() {
        return this.__pagePercent.get();
    }
    set pagePercent(newValue: number) {
        this.__pagePercent.set(newValue);
    }
    private __bookPercent: ObservedPropertySimplePU<number>;
    get bookPercent() {
        return this.__bookPercent.get();
    }
    set bookPercent(newValue: number) {
        this.__bookPercent.set(newValue);
    }
    private __pageText: ObservedPropertySimplePU<string>;
    get pageText() {
        return this.__pageText.get();
    }
    set pageText(newValue: string) {
        this.__pageText.set(newValue);
    }
    private __showMenu: ObservedPropertySimplePU<boolean>;
    get showMenu() {
        return this.__showMenu.get();
    }
    set showMenu(newValue: boolean) {
        this.__showMenu.set(newValue);
    }
    private __showToc: ObservedPropertySimplePU<boolean>;
    get showToc() {
        return this.__showToc.get();
    }
    set showToc(newValue: boolean) {
        this.__showToc.set(newValue);
    }
    private __hint: ObservedPropertySimplePU<string>;
    get hint() {
        return this.__hint.get();
    }
    set hint(newValue: string) {
        this.__hint.set(newValue);
    }
    private __loading: ObservedPropertySimplePU<boolean>;
    get loading() {
        return this.__loading.get();
    }
    set loading(newValue: boolean) {
        this.__loading.set(newValue);
    }
    /**
     * 不能叫 opacity —— ArkUI 的 CustomComponent 自带 opacity(value) 属性方法，
     * 同名字段会报 10505001（Type 'number' is not assignable to ...CommonAttribute）。
     */
    private __pageOpacity: ObservedPropertySimplePU<number>;
    get pageOpacity() {
        return this.__pageOpacity.get();
    }
    set pageOpacity(newValue: number) {
        this.__pageOpacity.set(newValue);
    }
    private __shiftX: ObservedPropertySimplePU<number>;
    get shiftX() {
        return this.__shiftX.get();
    }
    set shiftX(newValue: number) {
        this.__shiftX.set(newValue);
    }
    /** 渲染参数：必须与排版参数同源（唯一真源 = common/LayoutStyle） */
    private __fontSizeFp: ObservedPropertySimplePU<number>;
    get fontSizeFp() {
        return this.__fontSizeFp.get();
    }
    set fontSizeFp(newValue: number) {
        this.__fontSizeFp.set(newValue);
    }
    private __lineHeightVp: ObservedPropertySimplePU<number>;
    get lineHeightVp() {
        return this.__lineHeightVp.get();
    }
    set lineHeightVp(newValue: number) {
        this.__lineHeightVp.set(newValue);
    }
    private __marginVp: ObservedPropertySimplePU<number>;
    get marginVp() {
        return this.__marginVp.get();
    }
    set marginVp(newValue: number) {
        this.__marginVp.set(newValue);
    }
    /** '' = 系统默认字体；非空时渲染与测量都必须用同一个族名 */
    private __fontFamily: ObservedPropertySimplePU<string>;
    get fontFamily() {
        return this.__fontFamily.get();
    }
    set fontFamily(newValue: string) {
        this.__fontFamily.set(newValue);
    }
    private db: BookDb;
    private prefs: ReaderPrefs;
    private book: BookRecord | null;
    private chapters: ChapterRow[];
    private source: BookSource | null;
    private chapterText: string;
    private pages: PageRange[];
    private fontStore: FontStore | null;
    /** 当前字体（下载字体）在沙箱里的路径；系统字体为 '' */
    private fontPath: string;
    private paginator: Paginator;
    private cache: PageCache;
    private theme: ThemeName;
    private currentKey: string;
    private viewWidthVp: number;
    private viewHeightVp: number;
    /** 上一次排版时的视口（vp）；用于识别"旋转/分屏/字号缩放"导致的尺寸变化 */
    private laidOutWidthVp: number;
    private laidOutHeightVp: number;
    private areaReady: boolean;
    /** 首屏：拿到视口尺寸后再排版 */
    private pendingChapter: number;
    private pendingOffset: number;
    private pagesSincePersist: number;
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
            }
            catch (e) {
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
        if (next !== this.currentKey) {
            const keep: number = this.pages.length > 0 ? this.pages[this.pageIndex].start : 0;
            this.openChapter(this.chapterIndex, keep);
        }
    }
    onPageHide(): void {
        this.persistProgress(true);
    }
    aboutToDisappear(): void {
        this.persistProgress(true);
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
            this.source = createBookSource(book);
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
        }
        catch (e) {
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
    /** 打开某章并定位到某个字符偏移（内部会按签名查缓存，命中则不重排） */
    private openChapter(index: number, charOffset: number): void {
        if (this.source === null || index < 0 || index >= this.chapters.length) {
            return;
        }
        const levels: LayoutLevels = this.prefs.getLevels();
        const box: LayoutBox = this.boxOf(levels);
        const chapter: ChapterRow = this.chapters[index];
        this.hint = '';
        let text: string = '';
        try {
            text = this.source.chapterText(chapter);
        }
        catch (e) {
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
            }
            catch (e) {
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
        Context.animateTo({
            duration: FADE_OUT_MS,
            curve: Curve.EaseIn,
            onFinish: () => {
                if (chapterIndex !== this.chapterIndex) {
                    this.openChapter(chapterIndex, pageIndex < 0 ? -1 : 0);
                    if (pageIndex >= 0 && pageIndex !== this.pageIndex) {
                        this.showPage(pageIndex);
                    }
                }
                else {
                    this.showPage(pageIndex);
                }
                this.shiftX = dir * FADE_SHIFT_VP;
                Context.animateTo({ duration: FADE_IN_MS, curve: Curve.EaseOut }, () => {
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
    topBar(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(413:5)", "entry");
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
            Row.padding({ left: 12, right: 18, top: 10, bottom: 12 });
            Row.backgroundColor(this.palette.bg);
            Row.border({ width: { bottom: 1 }, color: this.palette.lineSoft });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(414:7)", "entry");
            Text.fontSize(20);
            Text.fontColor(this.palette.text);
            Text.width(34);
            Text.height(34);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => router.back());
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.title);
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(421:7)", "entry");
            Text.fontSize(13);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.palette.text);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            Text.margin({ left: 6 });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.chapterCount > 0 ? `${this.chapterIndex + 1}/${this.chapterCount}` : '');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(429:7)", "entry");
            Text.fontSize(9.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
    }
    segBar(percent: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 2 });
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(443:5)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const i = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.debugLine("entry/src/main/ets/pages/Reader.ets(445:9)", "entry");
                    Row.layoutWeight(1);
                    Row.height(2);
                    Row.backgroundColor(percent * 10 > i ? this.palette.text : this.palette.line);
                }, Row);
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], forEachItemGenFunction, (i: number) => 'seg' + i, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
    }
    bottomBar(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Reader.ets(456:5)", "entry");
            Column.width('100%');
            Column.padding({ left: 18, right: 18, top: 16, bottom: 26 });
            Column.backgroundColor(this.palette.bg);
            Column.border({ width: { top: 1 }, color: this.palette.lineSoft });
            Column.onClick(() => {
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(457:7)", "entry");
            Row.width('100%');
            Row.margin({ bottom: 10 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.chapterTitle);
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(458:9)", "entry");
            Text.fontSize(10);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(465:9)", "entry");
            Text.fontSize(10);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(473:7)", "entry");
            Row.width('100%');
            Row.margin({ bottom: 14 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('上一章');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(474:9)", "entry");
            Text.fontSize(12.5);
            Text.fontColor(this.chapterIndex <= 0 ? this.palette.text3 : this.palette.text);
            Text.height(34);
            Text.layoutWeight(1);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => this.jumpToChapter(this.chapterIndex - 1));
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('目录');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(481:9)", "entry");
            Text.fontSize(12.5);
            Text.fontColor(this.palette.text);
            Text.height(34);
            Text.layoutWeight(1);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => {
                this.showToc = true;
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('A a');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(490:9)", "entry");
            Text.fontSize(12.5);
            Text.fontColor(this.palette.text);
            Text.height(34);
            Text.layoutWeight(1);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => {
                router.pushUrl({ url: 'pages/Settings' });
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('下一章');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(499:9)", "entry");
            Text.fontSize(12.5);
            Text.fontColor(this.chapterIndex >= this.chapterCount - 1 ? this.palette.text3 : this.palette.text);
            Text.height(34);
            Text.layoutWeight(1);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => this.jumpToChapter(this.chapterIndex + 1));
        }, Text);
        Text.pop();
        Row.pop();
        this.segBar.bind(this)(this.bookPercent);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(512:7)", "entry");
            Row.width('100%');
            Row.margin({ top: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${Math.round(this.bookPercent * 100)}%`);
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(513:9)", "entry");
            Text.fontSize(9);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
    }
    tocPanel(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Reader.ets(531:5)", "entry");
            Column.width('100%');
            Column.height('62%');
            Column.backgroundColor(this.palette.bg);
            Column.borderRadius({ topLeft: 12, topRight: 12 });
            Column.border({ width: { top: 1, left: 1, right: 1 }, color: this.palette.line });
            Column.onClick(() => {
            });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(532:7)", "entry");
            Row.width('100%');
            Row.padding({ left: 20, right: 20, top: 16, bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('CONTENTS');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(533:9)", "entry");
            Text.fontSize(11);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text2);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Reader.ets(537:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.chapterCount}`);
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(538:9)", "entry");
            Text.fontSize(10);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            List.create();
            List.debugLine("entry/src/main/ets/pages/Reader.ets(546:7)", "entry");
            List.width('100%');
            List.layoutWeight(1);
            List.scrollBar(BarState.Off);
            List.divider({ strokeWidth: 1, color: this.palette.lineSoft });
        }, List);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const item = _item;
                {
                    const itemCreation = (elmtId, isInitialRender) => {
                        ViewStackProcessor.StartGetAccessRecordingFor(elmtId);
                        ListItem.create(deepRenderFunction, true);
                        if (!isInitialRender) {
                            ListItem.pop();
                        }
                        ViewStackProcessor.StopGetAccessRecording();
                    };
                    const itemCreation2 = (elmtId, isInitialRender) => {
                        ListItem.create(deepRenderFunction, true);
                        ListItem.debugLine("entry/src/main/ets/pages/Reader.ets(548:11)", "entry");
                    };
                    const deepRenderFunction = (elmtId, isInitialRender) => {
                        itemCreation(elmtId, isInitialRender);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Row.create();
                            Row.debugLine("entry/src/main/ets/pages/Reader.ets(549:13)", "entry");
                            Row.width('100%');
                            Row.padding({ left: 20, right: 20, top: 13, bottom: 13 });
                            Row.onClick(() => this.jumpToChapter(item.index));
                        }, Row);
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(`${item.index + 1}`);
                            Text.debugLine("entry/src/main/ets/pages/Reader.ets(550:15)", "entry");
                            Text.fontSize(9.5);
                            Text.fontFamily('monospace');
                            Text.fontColor(item.index === this.chapterIndex ? this.palette.red : this.palette.text3);
                            Text.width(30);
                        }, Text);
                        Text.pop();
                        this.observeComponentCreation2((elmtId, isInitialRender) => {
                            Text.create(item.title);
                            Text.debugLine("entry/src/main/ets/pages/Reader.ets(555:15)", "entry");
                            Text.fontSize(13.5);
                            Text.fontColor(item.index === this.chapterIndex ? this.palette.text : this.palette.text2);
                            Text.maxLines(1);
                            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                            Text.layoutWeight(1);
                        }, Text);
                        Text.pop();
                        Row.pop();
                        ListItem.pop();
                    };
                    this.observeComponentCreation2(itemCreation2, ListItem);
                    ListItem.pop();
                }
            };
            this.forEachUpdateFunction(elmtId, this.chapters, forEachItemGenFunction, (item: ChapterRow) => 'ch' + item.index, false, false);
        }, ForEach);
        ForEach.pop();
        List.pop();
        Column.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Stack.create({ alignContent: Alignment.Bottom });
            Stack.debugLine("entry/src/main/ets/pages/Reader.ets(583:5)", "entry");
            Stack.width('100%');
            Stack.height('100%');
            Stack.backgroundColor(this.palette.bg);
        }, Stack);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Reader.ets(585:7)", "entry");
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.width('100%');
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.height('100%');
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.padding({
                left: this.marginVp,
                right: this.marginVp,
                top: HEADER_VP,
                bottom: FOOTER_VP
            });
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.alignItems(HorizontalAlign.Start);
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.clip(true);
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.opacity(this.pageOpacity);
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.translate({ x: this.shiftX });
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.onAreaChange((oldValue: Area, newValue: Area) => {
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
            });
            // ---- 正文（点中间开菜单，点两侧翻页）----
            Column.onClick((event: ClickEvent) => {
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
                }
                else if (event.x > third * 2) {
                    this.turnPage(1);
                }
                else {
                    this.showMenu = true;
                }
            });
            globalThis.Gesture.create(GesturePriority.Low);
            PanGesture.create({ direction: PanDirection.Horizontal, distance: 12 });
            PanGesture.onActionEnd((event: GestureEvent) => {
                if (this.showMenu || this.showToc || this.hint.length > 0) {
                    return;
                }
                const threshold: number = this.viewWidthVp * SWIPE_RATIO;
                if (event.offsetX <= -threshold) {
                    this.turnPage(1);
                }
                else if (event.offsetX >= threshold) {
                    this.turnPage(-1);
                }
            });
            PanGesture.pop();
            globalThis.Gesture.pop();
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.hint.length > 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.hint);
                        Text.debugLine("entry/src/main/ets/pages/Reader.ets(587:11)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(this.palette.text2);
                        Text.margin({ top: 60 });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.pageText);
                        Text.debugLine("entry/src/main/ets/pages/Reader.ets(592:11)", "entry");
                        Text.fontSize(this.fontSizeFp);
                        Text.lineHeight(this.lineHeightVp);
                        Text.fontFamily(this.fontFamily);
                        Text.fontColor(this.palette.text);
                        Text.width('100%');
                        Text.textAlign(TextAlign.Start);
                    }, Text);
                    Text.pop();
                });
            }
        }, If);
        If.pop();
        // ---- 正文（点中间开菜单，点两侧翻页）----
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Reader.ets(680:7)", "entry");
            // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
            Column.width('100%');
            // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
            Column.height(FOOTER_VP);
            // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
            Column.justifyContent(FlexAlign.End);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Reader.ets(681:9)", "entry");
            Row.width('100%');
            Row.padding({ left: this.marginVp, right: this.marginVp, bottom: 12 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.chapterTitle);
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(682:11)", "entry");
            Text.fontSize(9.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            Text.layoutWeight(1);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.pageCount > 0 ? `${this.pageIndex + 1}/${this.pageCount}` : '');
            Text.debugLine("entry/src/main/ets/pages/Reader.ets(689:11)", "entry");
            Text.fontSize(9.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        // ---- 页脚（唯一常驻控件，极克制：等宽章名 + 页码）----
        Column.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // ---- 浮层：点屏中间才出现 ----
            if (this.showMenu) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Reader.ets(703:9)", "entry");
                        Column.width('100%');
                        Column.height('100%');
                        Column.onClick(() => {
                            this.showMenu = false;
                        });
                    }, Column);
                    this.topBar.bind(this)();
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Blank.create();
                        Blank.debugLine("entry/src/main/ets/pages/Reader.ets(705:11)", "entry");
                    }, Blank);
                    Blank.pop();
                    this.bottomBar.bind(this)();
                    Column.pop();
                });
            }
            // ---- 目录 ----
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // ---- 目录 ----
            if (this.showToc) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Reader.ets(717:9)", "entry");
                        Column.width('100%');
                        Column.height('100%');
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Reader.ets(718:11)", "entry");
                        Column.width('100%');
                        Column.layoutWeight(1);
                        Column.onClick(() => {
                            this.showToc = false;
                        });
                    }, Column);
                    Column.pop();
                    this.tocPanel.bind(this)();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        Stack.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Reader";
    }
}
registerNamedRoute(() => new Reader(undefined, {}), "", { bundleName: "com.rocktier.rockreader", moduleName: "entry", pagePath: "pages/Reader", pageFullPath: "entry/src/main/ets/pages/Reader", integratedHsp: "false", moduleType: "followWithHap" });
