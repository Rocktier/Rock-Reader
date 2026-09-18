if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Index_Params {
    books?: BookRecord[];
    resume?: BookRecord | null;
    resumePercent?: number;
    busy?: boolean;
    palette?: Palette;
    db?: BookDb;
    prefs?: ReaderPrefs;
    theme?: ThemeName;
}
import hilog from "@ohos:hilog";
import router from "@ohos:router";
import promptAction from "@ohos:promptAction";
import { BookDb } from "@bundle:com.rocktier.rockreader/entry/ets/data/BookDb";
import { ReaderPrefs } from "@bundle:com.rocktier.rockreader/entry/ets/data/ReaderPrefs";
import { BookImporter } from "@bundle:com.rocktier.rockreader/entry/ets/engine/importer/BookImporter";
import type { ImportResult } from "@bundle:com.rocktier.rockreader/entry/ets/engine/importer/BookImporter";
import type { BookRecord, ReadingProgress } from '../common/Types';
import { paletteOf, THEME_DARK } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import type { Palette, ThemeName } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import { applyThemeToSystem } from "@bundle:com.rocktier.rockreader/entry/ets/common/SystemBar";
const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';
function reasonText(reason: string): string {
    switch (reason) {
        case 'CANCELLED':
            return '';
        case 'NOT_SUPPORTED':
            return '只支持 TXT 与 EPUB';
        case 'TOO_LARGE':
            return '文件太大';
        case 'EMPTY':
            return '文件是空的';
        case 'COPY_FAILED':
            return '读取文件失败';
        case 'PARSE_FAILED':
            return '已导入，但目录解析失败';
        default:
            return '导入失败';
    }
}
class Index extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__books = new ObservedPropertyObjectPU([], this, "books");
        this.__resume = new ObservedPropertyObjectPU(null, this, "resume");
        this.__resumePercent = new ObservedPropertySimplePU(0, this, "resumePercent");
        this.__busy = new ObservedPropertySimplePU(false, this, "busy");
        this.__palette = new ObservedPropertyObjectPU(paletteOf(THEME_DARK), this, "palette");
        this.db = new BookDb();
        this.prefs = new ReaderPrefs();
        this.theme = THEME_DARK;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Index_Params) {
        if (params.books !== undefined) {
            this.books = params.books;
        }
        if (params.resume !== undefined) {
            this.resume = params.resume;
        }
        if (params.resumePercent !== undefined) {
            this.resumePercent = params.resumePercent;
        }
        if (params.busy !== undefined) {
            this.busy = params.busy;
        }
        if (params.palette !== undefined) {
            this.palette = params.palette;
        }
        if (params.db !== undefined) {
            this.db = params.db;
        }
        if (params.prefs !== undefined) {
            this.prefs = params.prefs;
        }
        if (params.theme !== undefined) {
            this.theme = params.theme;
        }
    }
    updateStateVars(params: Index_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__books.purgeDependencyOnElmtId(rmElmtId);
        this.__resume.purgeDependencyOnElmtId(rmElmtId);
        this.__resumePercent.purgeDependencyOnElmtId(rmElmtId);
        this.__busy.purgeDependencyOnElmtId(rmElmtId);
        this.__palette.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__books.aboutToBeDeleted();
        this.__resume.aboutToBeDeleted();
        this.__resumePercent.aboutToBeDeleted();
        this.__busy.aboutToBeDeleted();
        this.__palette.aboutToBeDeleted();
        SubscriberManager.Get().delete(this.id__());
        this.aboutToBeDeletedInternal();
    }
    private __books: ObservedPropertyObjectPU<BookRecord[]>;
    get books() {
        return this.__books.get();
    }
    set books(newValue: BookRecord[]) {
        this.__books.set(newValue);
    }
    private __resume: ObservedPropertyObjectPU<BookRecord | null>;
    get resume() {
        return this.__resume.get();
    }
    set resume(newValue: BookRecord | null) {
        this.__resume.set(newValue);
    }
    private __resumePercent: ObservedPropertySimplePU<number>;
    get resumePercent() {
        return this.__resumePercent.get();
    }
    set resumePercent(newValue: number) {
        this.__resumePercent.set(newValue);
    }
    private __busy: ObservedPropertySimplePU<boolean>;
    get busy() {
        return this.__busy.get();
    }
    set busy(newValue: boolean) {
        this.__busy.set(newValue);
    }
    private __palette: ObservedPropertyObjectPU<Palette>;
    get palette() {
        return this.__palette.get();
    }
    set palette(newValue: Palette) {
        this.__palette.set(newValue);
    }
    private db: BookDb;
    private prefs: ReaderPrefs;
    private theme: ThemeName;
    aboutToAppear(): void {
        this.prefs.open(getContext(this) as Context);
        this.applyTheme();
        // 启动时也同步一次系统层：默认深色时状态栏内容色就是白的，但显式设一次可保证
        // "上次退出时是浅色"的情况下状态栏文字块也是黑的（EntryAbility 设了 colorMode，这里兜一道底）
        applyThemeToSystem(getContext(this) as Context, this.theme);
        this.load();
    }
    onPageShow(): void {
        // 从设置页返回：主题可能改了
        this.prefs.open(getContext(this) as Context);
        this.prefs.reload();
        this.applyTheme();
    }
    private applyTheme(): void {
        const theme: ThemeName = this.prefs.getTheme();
        if (theme !== this.theme) {
            this.theme = theme;
            this.palette = paletteOf(theme);
            // 主题变了必须同步系统层（状态栏文字颜色 + 系统深色模式），否则浅色下白字白底看不见
            applyThemeToSystem(getContext(this) as Context, theme);
        }
    }
    private async load(): Promise<void> {
        try {
            await this.db.open(getContext(this) as Context);
            const list = await this.db.listBooks();
            this.books = list;
            if (list.length > 0) {
                this.resume = list[0];
                const p: ReadingProgress | null = await this.db.getProgress(list[0].id);
                this.resumePercent = p === null ? 0 : p.percent;
            }
            else {
                this.resume = null;
                this.resumePercent = 0;
            }
        }
        catch (e) {
            hilog.error(DOMAIN, TAG, 'load shelf failed: %{public}s', JSON.stringify(e));
        }
    }
    private async onImport(): Promise<void> {
        if (this.busy) {
            return;
        }
        this.busy = true;
        try {
            const importer = new BookImporter(this.db, getContext(this) as Context);
            const result: ImportResult = await importer.pickAndImport();
            const msg = reasonText(result.reason);
            if (msg.length > 0) {
                promptAction.showToast({ message: msg });
            }
            await this.load();
        }
        catch (e) {
            hilog.error(DOMAIN, TAG, 'import failed: %{public}s', JSON.stringify(e));
            promptAction.showToast({ message: '导入失败' });
        }
        finally {
            this.busy = false;
        }
    }
    private confirmDelete(book: BookRecord): void {
        promptAction.showDialog({
            title: book.title,
            message: '从书架移除这本书？（不会删除你的原文件）',
            buttons: [
                { text: '取消', color: '#A6A6A6' },
                { text: '移除', color: '#FF4A3D' }
            ]
        }).then((res: promptAction.ShowDialogSuccessResponse) => {
            if (res.index === 1) {
                this.doDelete(book);
            }
        });
    }
    private async doDelete(book: BookRecord): Promise<void> {
        try {
            await this.db.deleteBook(book.id);
            await this.load();
        }
        catch (e) {
            hilog.error(DOMAIN, TAG, 'delete failed: %{public}s', JSON.stringify(e));
        }
    }
    private openBook(book: BookRecord): void {
        router.pushUrl({ url: 'pages/Reader', params: { bookId: book.id } });
    }
    bookCover(book: BookRecord, size: number, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(145:5)", "entry");
            Column.width(size);
            Column.height(size * 1.4);
            Column.backgroundColor(this.palette.cover);
            Column.borderRadius(0);
            Column.justifyContent(FlexAlign.Center);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(book.title.length > 0 ? book.title.substring(0, 1) : '书');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(146:7)", "entry");
            Text.fontSize(size * 0.42);
            Text.fontColor(this.palette.text3);
            Text.fontWeight(FontWeight.Bold);
        }, Text);
        Text.pop();
        Column.pop();
    }
    resumeCard(book: BookRecord, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 14 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(160:5)", "entry");
            Row.width('100%');
            Row.padding(14);
            Row.borderRadius(12);
            Row.backgroundColor(this.palette.card);
            Row.borderWidth(1);
            Row.borderColor(this.palette.line);
            Row.onClick(() => this.openBook(book));
        }, Row);
        this.bookCover.bind(this)(book, 58);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create({ space: 6 });
            Column.debugLine("entry/src/main/ets/pages/Index.ets(162:7)", "entry");
            Column.alignItems(HorizontalAlign.Start);
            Column.layoutWeight(1);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(book.title);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(163:9)", "entry");
            Text.fontSize(15);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.palette.text);
            Text.maxLines(1);
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(book.format.toUpperCase());
            Text.debugLine("entry/src/main/ets/pages/Index.ets(169:9)", "entry");
            Text.fontSize(10);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 2 });
            Row.debugLine("entry/src/main/ets/pages/Index.ets(173:9)", "entry");
            Row.width('100%');
            Row.margin({ top: 6 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const i = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.debugLine("entry/src/main/ets/pages/Index.ets(175:13)", "entry");
                    Row.layoutWeight(1);
                    Row.height(2);
                    Row.backgroundColor(this.resumePercent * 10 > i ? this.palette.text : this.palette.line);
                }, Row);
                Row.pop();
            };
            this.forEachUpdateFunction(elmtId, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], forEachItemGenFunction, (i: number) => 'rp' + i, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${Math.round(this.resumePercent * 100)}%`);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(183:9)", "entry");
            Text.fontSize(9);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Column.pop();
        Row.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Index.ets(201:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor(this.palette.bg);
            Column.padding({ left: 22, right: 22 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 顶部
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(203:7)", "entry");
            // 顶部
            Row.width('100%');
            // 顶部
            Row.alignItems(VerticalAlign.Center);
            // 顶部
            Row.padding({ top: 10, bottom: 18 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create({ "id": 16777224, "type": 10003, params: [], "bundleName": "com.rocktier.rockreader", "moduleName": "entry" });
            Text.debugLine("entry/src/main/ets/pages/Index.ets(204:9)", "entry");
            Text.fontSize(22);
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.palette.text);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(`${this.books.length} 本`);
            Text.debugLine("entry/src/main/ets/pages/Index.ets(208:9)", "entry");
            Text.fontSize(11);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.margin({ left: 10 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(213:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('Aa');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(214:9)", "entry");
            Text.fontSize(13);
            Text.fontColor(this.palette.text);
            Text.width(30);
            Text.height(30);
            Text.textAlign(TextAlign.Center);
            Text.borderWidth(1);
            Text.borderColor(this.palette.line);
            Text.margin({ left: 8 });
            Text.onClick(() => {
                router.pushUrl({ url: 'pages/Settings' });
            });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.busy ? '···' : '＋');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(226:9)", "entry");
            Text.fontSize(15);
            Text.fontColor(this.palette.text);
            Text.width(30);
            Text.height(30);
            Text.textAlign(TextAlign.Center);
            Text.borderWidth(1);
            Text.borderColor(this.palette.line);
            Text.margin({ left: 8 });
            Text.onClick(() => {
                this.onImport();
            });
        }, Text);
        Text.pop();
        // 顶部
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 继续阅读
            if (this.resume !== null) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.resumeCard.bind(this)(ObservedObject.GetRawObject(this.resume));
                });
            }
            // 书架网格
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            // 书架网格
            if (this.books.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Column.create();
                        Column.debugLine("entry/src/main/ets/pages/Index.ets(250:9)", "entry");
                        Column.width('100%');
                        Column.layoutWeight(1);
                        Column.justifyContent(FlexAlign.Center);
                    }, Column);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create({ "id": 16777222, "type": 10003, params: [], "bundleName": "com.rocktier.rockreader", "moduleName": "entry" });
                        Text.debugLine("entry/src/main/ets/pages/Index.ets(251:11)", "entry");
                        Text.fontSize(13);
                        Text.fontColor(this.palette.text3);
                    }, Text);
                    Text.pop();
                    Column.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Scroll.create();
                        Scroll.debugLine("entry/src/main/ets/pages/Index.ets(259:9)", "entry");
                        Scroll.layoutWeight(1);
                        Scroll.scrollBar(BarState.Off);
                    }, Scroll);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Grid.create();
                        Grid.debugLine("entry/src/main/ets/pages/Index.ets(260:11)", "entry");
                        Grid.columnsTemplate('1fr 1fr 1fr');
                        Grid.columnsGap(14);
                        Grid.rowsGap(16);
                        Grid.width('100%');
                    }, Grid);
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        ForEach.create();
                        const forEachItemGenFunction = _item => {
                            const item = _item;
                            {
                                const itemCreation2 = (elmtId, isInitialRender) => {
                                    GridItem.create(() => { }, false);
                                    GridItem.debugLine("entry/src/main/ets/pages/Index.ets(262:15)", "entry");
                                };
                                const observedDeepRender = () => {
                                    this.observeComponentCreation2(itemCreation2, GridItem);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Column.create({ space: 7 });
                                        Column.debugLine("entry/src/main/ets/pages/Index.ets(263:17)", "entry");
                                        Column.width('100%');
                                        Column.onClick(() => this.openBook(item));
                                        globalThis.Gesture.create(GesturePriority.Low);
                                        LongPressGesture.create();
                                        LongPressGesture.onAction(() => this.confirmDelete(item));
                                        LongPressGesture.pop();
                                        globalThis.Gesture.pop();
                                    }, Column);
                                    this.bookCover.bind(this)(item, 88);
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(item.title);
                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(265:19)", "entry");
                                        Text.fontSize(11.5);
                                        Text.fontColor(this.palette.text);
                                        Text.maxLines(1);
                                        Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                                    }, Text);
                                    Text.pop();
                                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                                        Text.create(item.format.toUpperCase());
                                        Text.debugLine("entry/src/main/ets/pages/Index.ets(270:19)", "entry");
                                        Text.fontSize(9);
                                        Text.fontFamily('monospace');
                                        Text.fontColor(this.palette.text3);
                                    }, Text);
                                    Text.pop();
                                    Column.pop();
                                    GridItem.pop();
                                };
                                observedDeepRender();
                            }
                        };
                        this.forEachUpdateFunction(elmtId, this.books, forEachItemGenFunction, (item: BookRecord) => item.id, false, false);
                    }, ForEach);
                    ForEach.pop();
                    Grid.pop();
                    Scroll.pop();
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Index.ets(290:7)", "entry");
            Row.width('100%');
            Row.padding({ bottom: 16, top: 8 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('LOCAL ONLY');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(291:9)", "entry");
            Text.fontSize(9);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Index.ets(295:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('v1.0.0');
            Text.debugLine("entry/src/main/ets/pages/Index.ets(296:9)", "entry");
            Text.fontSize(9);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Index";
    }
}
registerNamedRoute(() => new Index(undefined, {}), "", { bundleName: "com.rocktier.rockreader", moduleName: "entry", pagePath: "pages/Index", pageFullPath: "entry/src/main/ets/pages/Index", integratedHsp: "false", moduleType: "followWithHap" });
