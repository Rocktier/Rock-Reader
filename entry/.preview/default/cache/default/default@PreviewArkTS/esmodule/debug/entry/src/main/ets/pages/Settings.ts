if (!("finalizeConstruction" in ViewPU.prototype)) {
    Reflect.set(ViewPU.prototype, "finalizeConstruction", () => { });
}
interface Settings_Params {
    palette?: Palette;
    levels?: LayoutLevels;
    theme?: ThemeName;
    fontFamily?: string;
    fontFamilies?: string[];
    downloadedIds?: string[];
    busyFontId?: string;
    fontNote?: string;
    prefs?: ReaderPrefs;
    fontStore?: FontStore | null;
}
import router from "@ohos:router";
import hilog from "@ohos:hilog";
import { ReaderPrefs } from "@bundle:com.rocktier.rockreader/entry/ets/data/ReaderPrefs";
import { clampLevel, LEVEL_MAX } from "@bundle:com.rocktier.rockreader/entry/ets/common/LayoutStyle";
import type { LayoutLevels } from "@bundle:com.rocktier.rockreader/entry/ets/common/LayoutStyle";
import { paletteOf, THEME_DARK, THEME_LIGHT } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import type { Palette, ThemeName } from "@bundle:com.rocktier.rockreader/entry/ets/common/Theme";
import { applyThemeToSystem } from "@bundle:com.rocktier.rockreader/entry/ets/common/SystemBar";
import { FontStore } from "@bundle:com.rocktier.rockreader/entry/ets/data/FontStore";
import { FONT_CATALOG, sizeTextOf } from "@bundle:com.rocktier.rockreader/entry/ets/common/FontCatalog";
import type { FontEntry } from "@bundle:com.rocktier.rockreader/entry/ets/common/FontCatalog";
const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';
const CHIP_SIZE: number = 44;
const CHIP_HEIGHT: number = 34;
/** 系统字体列表最多显示多少项（有些设备会返回几十项，取够用的量） */
const MAX_FONT_ITEMS: number = 40;
class Settings extends ViewPU {
    constructor(parent, params, __localStorage, elmtId = -1, paramsLambda = undefined, extraInfo) {
        super(parent, __localStorage, elmtId, extraInfo);
        if (typeof paramsLambda === "function") {
            this.paramsGenerator_ = paramsLambda;
        }
        this.__palette = new ObservedPropertyObjectPU(paletteOf(THEME_DARK), this, "palette");
        this.__levels = new ObservedPropertyObjectPU({ fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3 }, this, "levels");
        this.__theme = new ObservedPropertyObjectPU(THEME_DARK, this, "theme");
        this.__fontFamily = new ObservedPropertySimplePU('', this, "fontFamily");
        this.__fontFamilies = new ObservedPropertyObjectPU([], this, "fontFamilies");
        this.__downloadedIds = new ObservedPropertyObjectPU([], this, "downloadedIds");
        this.__busyFontId = new ObservedPropertySimplePU('', this, "busyFontId");
        this.__fontNote = new ObservedPropertySimplePU('', this, "fontNote");
        this.prefs = new ReaderPrefs();
        this.fontStore = null;
        this.setInitiallyProvidedValue(params);
        this.finalizeConstruction();
    }
    setInitiallyProvidedValue(params: Settings_Params) {
        if (params.palette !== undefined) {
            this.palette = params.palette;
        }
        if (params.levels !== undefined) {
            this.levels = params.levels;
        }
        if (params.theme !== undefined) {
            this.theme = params.theme;
        }
        if (params.fontFamily !== undefined) {
            this.fontFamily = params.fontFamily;
        }
        if (params.fontFamilies !== undefined) {
            this.fontFamilies = params.fontFamilies;
        }
        if (params.downloadedIds !== undefined) {
            this.downloadedIds = params.downloadedIds;
        }
        if (params.busyFontId !== undefined) {
            this.busyFontId = params.busyFontId;
        }
        if (params.fontNote !== undefined) {
            this.fontNote = params.fontNote;
        }
        if (params.prefs !== undefined) {
            this.prefs = params.prefs;
        }
        if (params.fontStore !== undefined) {
            this.fontStore = params.fontStore;
        }
    }
    updateStateVars(params: Settings_Params) {
    }
    purgeVariableDependenciesOnElmtId(rmElmtId) {
        this.__palette.purgeDependencyOnElmtId(rmElmtId);
        this.__levels.purgeDependencyOnElmtId(rmElmtId);
        this.__theme.purgeDependencyOnElmtId(rmElmtId);
        this.__fontFamily.purgeDependencyOnElmtId(rmElmtId);
        this.__fontFamilies.purgeDependencyOnElmtId(rmElmtId);
        this.__downloadedIds.purgeDependencyOnElmtId(rmElmtId);
        this.__busyFontId.purgeDependencyOnElmtId(rmElmtId);
        this.__fontNote.purgeDependencyOnElmtId(rmElmtId);
    }
    aboutToBeDeleted() {
        this.__palette.aboutToBeDeleted();
        this.__levels.aboutToBeDeleted();
        this.__theme.aboutToBeDeleted();
        this.__fontFamily.aboutToBeDeleted();
        this.__fontFamilies.aboutToBeDeleted();
        this.__downloadedIds.aboutToBeDeleted();
        this.__busyFontId.aboutToBeDeleted();
        this.__fontNote.aboutToBeDeleted();
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
    private __levels: ObservedPropertyObjectPU<LayoutLevels>;
    get levels() {
        return this.__levels.get();
    }
    set levels(newValue: LayoutLevels) {
        this.__levels.set(newValue);
    }
    private __theme: ObservedPropertyObjectPU<ThemeName>;
    get theme() {
        return this.__theme.get();
    }
    set theme(newValue: ThemeName) {
        this.__theme.set(newValue);
    }
    /** '' = 系统默认 */
    private __fontFamily: ObservedPropertySimplePU<string>;
    get fontFamily() {
        return this.__fontFamily.get();
    }
    set fontFamily(newValue: string) {
        this.__fontFamily.set(newValue);
    }
    private __fontFamilies: ObservedPropertyObjectPU<string[]>;
    get fontFamilies() {
        return this.__fontFamilies.get();
    }
    set fontFamilies(newValue: string[]) {
        this.__fontFamilies.set(newValue);
    }
    /** 已下载的字体 id */
    private __downloadedIds: ObservedPropertyObjectPU<string[]>;
    get downloadedIds() {
        return this.__downloadedIds.get();
    }
    set downloadedIds(newValue: string[]) {
        this.__downloadedIds.set(newValue);
    }
    /** 正在下载的字体 id（'' = 空闲） */
    private __busyFontId: ObservedPropertySimplePU<string>;
    get busyFontId() {
        return this.__busyFontId.get();
    }
    set busyFontId(newValue: string) {
        this.__busyFontId.set(newValue);
    }
    private __fontNote: ObservedPropertySimplePU<string>;
    get fontNote() {
        return this.__fontNote.get();
    }
    set fontNote(newValue: string) {
        this.__fontNote.set(newValue);
    }
    private prefs: ReaderPrefs;
    private fontStore: FontStore | null;
    aboutToAppear(): void {
        this.prefs.open(getContext(this) as Context);
        this.fontStore = new FontStore(getContext(this) as Context);
        this.levels = this.prefs.getLevels();
        this.theme = this.prefs.getTheme();
        this.fontFamily = this.prefs.getFontFamily();
        this.palette = paletteOf(this.theme);
        this.refreshFontState();
        this.registerLocalFonts();
        this.loadSystemFonts();
    }
    onPageShow(): void {
        this.loadSystemFonts();
    }
    /**
     * 列系统已装字体（**不内置字体文件 → 体积 0**）。
     * 用户若在系统里装了喜欢的字体（主题字体等），这里就能直接选到。
     * 用 UIContext 上的 Font（`@ohos.font` 的全局函数已废弃）。
     */
    private loadSystemFonts(): void {
        if (this.fontFamilies.length > 0) {
            return;
        }
        try {
            const list: string[] = this.getUIContext().getFont().getSystemFontList();
            const picked: string[] = [];
            for (let i: number = 0; i < list.length && picked.length < MAX_FONT_ITEMS; i++) {
                if (list[i].length > 0) {
                    picked.push(list[i]);
                }
            }
            this.fontFamilies = picked;
        }
        catch (e) {
            // 取不到就只显示「系统默认」—— 字体选择不是读书的必要条件，绝不因此报错
            hilog.warn(DOMAIN, TAG, 'getSystemFontList failed: %{public}s', JSON.stringify(e));
            this.fontFamilies = [];
        }
    }
    /** 已下载字体状态刷新 + 注册（registerFont 只在进程内存活，每次进页面都要确认一次） */
    private refreshFontState(): void {
        if (this.fontStore === null) {
            return;
        }
        const store: FontStore = this.fontStore;
        const list: FontEntry[] = store.downloaded();
        const ids: string[] = [];
        for (let i: number = 0; i < list.length; i++) {
            ids.push(list[i].id);
        }
        this.downloadedIds = ids;
    }
    private registerLocalFonts(): void {
        if (this.fontStore === null) {
            return;
        }
        const store: FontStore = this.fontStore;
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
    private pickFont(family: string): void {
        this.fontFamily = family;
        this.prefs.saveFontFamily(family);
        this.fontNote = '';
    }
    /**
     * 下载一款字体（**用户主动点击**才联网）。
     * 失败一律静默：只把状态写在字体区里，不弹窗、不拦路。
     */
    private async downloadFont(entry: FontEntry): Promise<void> {
        if (this.fontStore === null || this.busyFontId.length > 0) {
            return;
        }
        this.busyFontId = entry.id;
        this.fontNote = `正在下载 ${entry.displayName}（${sizeTextOf(entry.sizeBytes)}）…`;
        const store: FontStore = this.fontStore;
        const ok: boolean = await store.download(entry);
        if (ok) {
            this.refreshFontState();
            this.registerLocalFonts();
            this.pickFont(entry.familyName);
            this.fontNote = `${entry.displayName} 已就绪`;
        }
        else {
            this.fontNote = '下载未完成，可稍后再试';
        }
        this.busyFontId = '';
    }
    private removeFont(entry: FontEntry): void {
        if (this.fontStore === null) {
            return;
        }
        this.fontStore.remove(entry);
        if (this.fontFamily === entry.familyName) {
            this.pickFont('');
        }
        this.refreshFontState();
        this.fontNote = '';
    }
    private isDownloaded(id: string): boolean {
        return this.downloadedIds.indexOf(id) >= 0;
    }
    /** row: 'font' | 'line' | 'margin'；n: 档位序号 */
    private pick(row: string, n: number): void {
        const level: number = clampLevel(n);
        const next: LayoutLevels = {
            fontSizeLevel: row === 'font' ? level : this.levels.fontSizeLevel,
            lineHeightLevel: row === 'line' ? level : this.levels.lineHeightLevel,
            marginLevel: row === 'margin' ? level : this.levels.marginLevel
        };
        this.levels = next;
        this.prefs.saveLevels(next);
    }
    private pickTheme(theme: ThemeName): void {
        this.theme = theme;
        this.palette = paletteOf(theme);
        this.prefs.saveTheme(theme);
        // 同步系统层：浅色主题下必须把状态栏文字改成黑色，否则白底白字
        applyThemeToSystem(getContext(this) as Context, theme);
        this.loadSystemFonts();
    }
    private currentOf(row: string): number {
        if (row === 'font') {
            return this.levels.fontSizeLevel;
        }
        return row === 'line' ? this.levels.lineHeightLevel : this.levels.marginLevel;
    }
    levelRow(label: string, row: string, hint: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(194:5)", "entry");
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({ top: 16, bottom: 16 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(195:7)", "entry");
            Row.width('100%');
            Row.margin({ bottom: 10 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(196:9)", "entry");
            Text.fontSize(13.5);
            Text.fontColor(this.palette.text);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Settings.ets(199:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(hint);
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(200:9)", "entry");
            Text.fontSize(9.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(208:7)", "entry");
            Row.width('100%');
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const n = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`${n}`);
                    Text.debugLine("entry/src/main/ets/pages/Settings.ets(210:11)", "entry");
                    Text.fontSize(13);
                    Text.fontFamily('monospace');
                    Text.fontColor(this.currentOf(row) === n ? this.palette.bg : this.palette.text2);
                    Text.backgroundColor(this.currentOf(row) === n ? this.palette.text : this.palette.card);
                    Text.border({ width: 1, color: this.currentOf(row) === n ? this.palette.text : this.palette.line });
                    Text.borderRadius(0);
                    Text.width(CHIP_SIZE);
                    Text.height(CHIP_HEIGHT);
                    Text.textAlign(TextAlign.Center);
                    Text.onClick(() => this.pick(row, n));
                }, Text);
                Text.pop();
            };
            this.forEachUpdateFunction(elmtId, [1, 2, 3, 4, 5], forEachItemGenFunction, (n: number) => row + n, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        Column.pop();
    }
    fontChip(label: string, family: string, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(232:5)", "entry");
            Text.fontFamily(family);
            Text.fontSize(13);
            Text.fontColor(this.fontFamily === family ? this.palette.bg : this.palette.text2);
            Text.backgroundColor(this.fontFamily === family ? this.palette.text : this.palette.card);
            Text.border({ width: 1, color: this.fontFamily === family ? this.palette.text : this.palette.line });
            Text.borderRadius(0);
            Text.height(CHIP_HEIGHT);
            Text.padding({ left: 14, right: 14 });
            Text.onClick(() => this.pickFont(family));
        }, Text);
        Text.pop();
    }
    /** 字体：横向芯片列表（系统已装字体，**不内置字体文件 → 体积 0**） */
    fontSection(parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(247:5)", "entry");
            Column.width('100%');
            Column.alignItems(HorizontalAlign.Start);
            Column.padding({ top: 16, bottom: 16 });
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(248:7)", "entry");
            Row.width('100%');
            Row.margin({ bottom: 9 });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('字体');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(249:9)", "entry");
            Text.fontSize(13.5);
            Text.fontColor(this.palette.text);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Settings.ets(252:9)", "entry");
        }, Blank);
        Blank.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(this.fontFamily.length > 0 ? `${this.fontFamilies.length} 款可选` : '系统默认');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(253:9)", "entry");
            Text.fontSize(9.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
        }, Text);
        Text.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 预览：直接看这套字体在正文里的样子
            Text.create('思维力是孩子学习力的基础 ABC 123');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(262:7)", "entry");
            // 预览：直接看这套字体在正文里的样子
            Text.fontFamily(this.fontFamily);
            // 预览：直接看这套字体在正文里的样子
            Text.fontSize(15);
            // 预览：直接看这套字体在正文里的样子
            Text.fontColor(this.palette.text2);
            // 预览：直接看这套字体在正文里的样子
            Text.maxLines(1);
            // 预览：直接看这套字体在正文里的样子
            Text.textOverflow({ overflow: TextOverflow.Ellipsis });
            // 预览：直接看这套字体在正文里的样子
            Text.width('100%');
            // 预览：直接看这套字体在正文里的样子
            Text.padding({ bottom: 12 });
        }, Text);
        // 预览：直接看这套字体在正文里的样子
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Settings.ets(271:7)", "entry");
            Scroll.scrollable(ScrollDirection.Horizontal);
            Scroll.scrollBar(BarState.Off);
            Scroll.width('100%');
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 8 });
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(272:9)", "entry");
        }, Row);
        this.fontChip.bind(this)('系统默认', '');
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const family = _item;
                this.fontChip.bind(this)(family, family);
            };
            this.forEachUpdateFunction(elmtId, this.fontFamilies, forEachItemGenFunction, (family: string) => 'fam' + family, false, false);
        }, ForEach);
        ForEach.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const entry = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (this.isDownloaded(entry.id)) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.fontChip.bind(this)(entry.displayName, entry.familyName);
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                        });
                    }
                }, If);
                If.pop();
            };
            this.forEachUpdateFunction(elmtId, FONT_CATALOG, forEachItemGenFunction, (entry: FontEntry) => 'own' + entry.id, false, false);
        }, ForEach);
        ForEach.pop();
        Row.pop();
        Scroll.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // ---- 更多字体（按需下载，不占安装包体积）----
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(289:7)", "entry");
            // ---- 更多字体（按需下载，不占安装包体积）----
            Column.width('100%');
            // ---- 更多字体（按需下载，不占安装包体积）----
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('更多字体 · 下载后存本机');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(290:9)", "entry");
            Text.fontSize(10.5);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.margin({ top: 16, bottom: 4 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            ForEach.create();
            const forEachItemGenFunction = _item => {
                const entry = _item;
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Row.create();
                    Row.debugLine("entry/src/main/ets/pages/Settings.ets(297:11)", "entry");
                    Row.width('100%');
                    Row.padding({ top: 12, bottom: 12 });
                    Row.border({ width: { top: 1 }, color: this.palette.lineSoft });
                }, Row);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Column.create();
                    Column.debugLine("entry/src/main/ets/pages/Settings.ets(298:13)", "entry");
                    Column.alignItems(HorizontalAlign.Start);
                    Column.layoutWeight(1);
                }, Column);
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(entry.displayName);
                    Text.debugLine("entry/src/main/ets/pages/Settings.ets(299:15)", "entry");
                    Text.fontSize(13);
                    Text.fontColor(this.palette.text);
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(entry.desc);
                    Text.debugLine("entry/src/main/ets/pages/Settings.ets(302:15)", "entry");
                    Text.fontSize(10);
                    Text.fontColor(this.palette.text3);
                    Text.maxLines(1);
                    Text.textOverflow({ overflow: TextOverflow.Ellipsis });
                }, Text);
                Text.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(`${sizeTextOf(entry.sizeBytes)} · ${entry.license}`);
                    Text.debugLine("entry/src/main/ets/pages/Settings.ets(307:15)", "entry");
                    Text.fontSize(9);
                    Text.fontFamily('monospace');
                    Text.fontColor(this.palette.text3);
                    Text.margin({ top: 4 });
                }, Text);
                Text.pop();
                Column.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    Text.create(this.fontActionText(entry));
                    Text.debugLine("entry/src/main/ets/pages/Settings.ets(316:13)", "entry");
                    Text.fontSize(12);
                    Text.fontColor(this.isDownloaded(entry.id) ? this.palette.text3 : this.palette.text);
                    Text.padding({ left: 12, right: 12 });
                    Text.height(30);
                    Text.border({ width: 1, color: this.palette.line });
                    Text.onClick(() => {
                        if (this.isDownloaded(entry.id)) {
                            this.removeFont(entry);
                        }
                        else {
                            this.downloadFont(entry);
                        }
                    });
                }, Text);
                Text.pop();
                Row.pop();
                this.observeComponentCreation2((elmtId, isInitialRender) => {
                    If.create();
                    if (this.fontNote.length > 0 && this.busyFontId === entry.id) {
                        this.ifElseBranchUpdateFunction(0, () => {
                            this.observeComponentCreation2((elmtId, isInitialRender) => {
                                Text.create(this.fontNote);
                                Text.debugLine("entry/src/main/ets/pages/Settings.ets(335:13)", "entry");
                                Text.fontSize(10);
                                Text.fontColor(this.palette.text3);
                                Text.margin({ bottom: 8 });
                            }, Text);
                            Text.pop();
                        });
                    }
                    else {
                        this.ifElseBranchUpdateFunction(1, () => {
                        });
                    }
                }, If);
                If.pop();
            };
            this.forEachUpdateFunction(elmtId, FONT_CATALOG, forEachItemGenFunction, (entry: FontEntry) => 'dl' + entry.id, false, false);
        }, ForEach);
        ForEach.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            If.create();
            if (this.fontNote.length > 0 && this.busyFontId.length === 0) {
                this.ifElseBranchUpdateFunction(0, () => {
                    this.observeComponentCreation2((elmtId, isInitialRender) => {
                        Text.create(this.fontNote);
                        Text.debugLine("entry/src/main/ets/pages/Settings.ets(343:11)", "entry");
                        Text.fontSize(10);
                        Text.fontColor(this.palette.text3);
                        Text.margin({ top: 8 });
                    }, Text);
                    Text.pop();
                });
            }
            else {
                this.ifElseBranchUpdateFunction(1, () => {
                });
            }
        }, If);
        If.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('字体需联网下载一次；下载后存本机，不占安装包体积。断网时本节为空，不影响阅读。');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(349:9)", "entry");
            Text.fontSize(9);
            Text.fontColor(this.palette.text3);
            Text.margin({ top: 10 });
        }, Text);
        Text.pop();
        // ---- 更多字体（按需下载，不占安装包体积）----
        Column.pop();
        Column.pop();
    }
    private fontActionText(entry: FontEntry): string {
        if (this.busyFontId === entry.id) {
            return '下载中…';
        }
        return this.isDownloaded(entry.id) ? '移除' : '下载';
    }
    themeChip(label: string, value: ThemeName, parent = null) {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create(label);
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(371:5)", "entry");
            Text.fontSize(12.5);
            Text.fontColor(this.theme === value ? this.palette.bg : this.palette.text2);
            Text.backgroundColor(this.theme === value ? this.palette.text : this.palette.card);
            Text.border({ width: 1, color: this.theme === value ? this.palette.text : this.palette.line });
            Text.borderRadius(0);
            Text.height(CHIP_HEIGHT);
            Text.padding({ left: 18, right: 18 });
            Text.onClick(() => this.pickTheme(value));
        }, Text);
        Text.pop();
    }
    initialRender() {
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(383:5)", "entry");
            Column.width('100%');
            Column.height('100%');
            Column.backgroundColor(this.palette.bg);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create();
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(384:7)", "entry");
            Row.width('100%');
            Row.alignItems(VerticalAlign.Center);
            Row.padding({ left: 12, right: 18, top: 10, bottom: 12 });
            Row.border({ width: { bottom: 1 }, color: this.palette.lineSoft });
        }, Row);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('‹');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(385:9)", "entry");
            Text.fontSize(20);
            Text.fontColor(this.palette.text);
            Text.width(34);
            Text.height(34);
            Text.textAlign(TextAlign.Center);
            Text.onClick(() => router.back());
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('SETTINGS');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(392:9)", "entry");
            Text.fontSize(12);
            Text.fontFamily('monospace');
            Text.fontWeight(FontWeight.Bold);
            Text.fontColor(this.palette.text);
            Text.margin({ left: 6 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Blank.create();
            Blank.debugLine("entry/src/main/ets/pages/Settings.ets(398:9)", "entry");
        }, Blank);
        Blank.pop();
        Row.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            // 内容可能超过一屏（尤其加了字体下载区之后）→ 整段可滚动
            Scroll.create();
            Scroll.debugLine("entry/src/main/ets/pages/Settings.ets(406:7)", "entry");
            // 内容可能超过一屏（尤其加了字体下载区之后）→ 整段可滚动
            Scroll.layoutWeight(1);
            // 内容可能超过一屏（尤其加了字体下载区之后）→ 整段可滚动
            Scroll.scrollBar(BarState.Off);
            // 内容可能超过一屏（尤其加了字体下载区之后）→ 整段可滚动
            Scroll.align(Alignment.TopStart);
        }, Scroll);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(407:9)", "entry");
            Column.width('100%');
            Column.padding({ left: 22, right: 22, top: 18, bottom: 8 });
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('排版');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(408:11)", "entry");
            Text.fontSize(11);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.width('100%');
            Text.margin({ bottom: 4 });
        }, Text);
        Text.pop();
        this.levelRow.bind(this)('字号', 'font', `${this.levels.fontSizeLevel}/${LEVEL_MAX}`);
        this.levelRow.bind(this)('行距', 'line', `${this.levels.lineHeightLevel}/${LEVEL_MAX}`);
        this.levelRow.bind(this)('页边距', 'margin', `${this.levels.marginLevel}/${LEVEL_MAX}`);
        this.fontSection.bind(this)();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Divider.create();
            Divider.debugLine("entry/src/main/ets/pages/Settings.ets(421:9)", "entry");
            Divider.color(this.palette.lineSoft);
            Divider.margin({ top: 8, bottom: 8 });
        }, Divider);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('主题');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(425:9)", "entry");
            Text.fontSize(11);
            Text.fontFamily('monospace');
            Text.fontColor(this.palette.text3);
            Text.width('100%');
            Text.margin({ bottom: 12 });
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Row.create({ space: 10 });
            Row.debugLine("entry/src/main/ets/pages/Settings.ets(432:11)", "entry");
            Row.width('100%');
        }, Row);
        this.themeChip.bind(this)('深色', THEME_DARK);
        this.themeChip.bind(this)('浅色', THEME_LIGHT);
        Row.pop();
        Column.pop();
        // 内容可能超过一屏（尤其加了字体下载区之后）→ 整段可滚动
        Scroll.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Column.create();
            Column.debugLine("entry/src/main/ets/pages/Settings.ets(446:7)", "entry");
            Column.width('100%');
            Column.padding({ left: 22, right: 22, bottom: 26 });
            Column.alignItems(HorizontalAlign.Start);
        }, Column);
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('核心数据不联网');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(447:9)", "entry");
            Text.fontSize(12);
            Text.fontColor(this.palette.text2);
        }, Text);
        Text.pop();
        this.observeComponentCreation2((elmtId, isInitialRender) => {
            Text.create('书籍与进度全部在本机处理');
            Text.debugLine("entry/src/main/ets/pages/Settings.ets(450:9)", "entry");
            Text.fontSize(10);
            Text.fontColor(this.palette.text3);
            Text.margin({ top: 6 });
        }, Text);
        Text.pop();
        Column.pop();
        Column.pop();
    }
    rerender() {
        this.updateDirtyElements();
    }
    static getEntryName(): string {
        return "Settings";
    }
}
registerNamedRoute(() => new Settings(undefined, {}), "", { bundleName: "com.rocktier.rockreader", moduleName: "entry", pagePath: "pages/Settings", pageFullPath: "entry/src/main/ets/pages/Settings", integratedHsp: "false", moduleType: "followWithHap" });
