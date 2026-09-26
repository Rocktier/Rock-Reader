/**
 * 书架页
 * 设计依据：docs/v1-design.md §8 —— 黑底白字、等宽数码、书封 0 圆角、卡片 12 圆角、空态不放营销文案
 * 主题：色板来自 common/Theme.ets（运行时切换，与系统深浅色解耦）
 *
 * 书架的分组/进度规则全部在 engine/shelf/ShelfRules.ets（纯逻辑、可单测），本页只做渲染与交互。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, promptAction } from '@kit.ArkUI';
import { BookDb } from '../data/BookDb';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { BookImporter, ImportResult, coverPathOf, removeBookFiles } from '../engine/importer/BookImporter';
import { reasonText } from '../engine/importer/ImportReason';
import {
  collectGroups,
  filterByStatus,
  GROUP_ALL,
  GROUP_UNFILED,
  filledCells,
  normalizeGroupName,
  percentText,
  toShelfItems,
  STATUS_ALL,
  STATUS_DONE,
  STATUS_READING,
  STATUS_UNREAD
} from '../engine/shelf/ShelfRules';
import { BookRecord, ShelfItem } from '../common/Types';
import { Palette, paletteOf, THEME_DARK, ThemeName } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/**
 * 当前隐私政策版本 —— **政策有实质变更时必须 +1**。
 * 用户已确认的版本存在 ReaderPrefs 里，小于这个值就会重新弹提示。
 * 改了 Privacy.ets 的正文就要动这里，别偷懒。
 */
const PRIVACY_VERSION: number = 1;

/** 编辑器/菜单的显示模式 */
const MODE_NONE: string = 'none';
const MODE_MENU: string = 'menu';
const MODE_RENAME: string = 'rename';
const MODE_GROUP: string = 'group';
/** 菜单内的「移除」二次确认（不弹系统 dialog —— 见 editorPanel 里的说明） */
const MODE_DELETE: string = 'delete';

/** 进度条格数（与「继续阅读」卡片一致） */
const CELLS: number = 10;

// reasonText 已抽到 engine/importer/ImportReason.ets：
// 它是纯映射（不碰 fileIo / UI），挪出去才能进 CI 单测 ——
// 那个"default 谎报导入失败"的 bug 就是靠测试守住的（见那边的文件说明）。

@Entry
@Component
struct Index {
  @State items: ShelfItem[] = [];
  @State groups: string[] = [];
  @State activeGroup: string = GROUP_ALL;
  /** 阅读状态筛选（未读 / 在读 / 已读），与分组是两个独立维度 */
  @State statusFilter: string = STATUS_ALL;
  @State resume: ShelfItem | null = null;
  @State busy: boolean = false;
  @State palette: Palette = paletteOf(THEME_DARK);
  // 「用其他应用打开」带进来的待导入 uri —— EntryAbility 收到后写进 AppStorage，这里接住。
  // 键名两边都写死（ArkUI 装饰器只接受字面量，抽不成常量），改要一起改。
  @StorageLink('pendingImportUri') @Watch('onIncomingFile') incomingUri: string = '';
  // 阅读页**写完进度库之后**发的信号（Reader.persistProgress 的 Promise.all 完成时 set）。
  // 没有它的话：返回书架时 onPageShow 的 load 会和写库竞态，进度条显示旧值（审核驳回第 3 条）。
  // 键名两边都写死（同上：装饰器只接受字面量），改要一起改。
  @StorageLink('progressSavedAt') @Watch('onProgressSaved') progressSavedAt: number = 0;

  /** 长按后弹出的菜单/输入框 */
  @State editorMode: string = MODE_NONE;
  @State editorBookId: string = '';
  @State editorText: string = '';

  /**
   * 首次启动的隐私政策提示（2026-09-26 审核驳回第 1 条）。
   * 政策有**实质变更**时把 PRIVACY_VERSION 加一 → 老用户会再次看到。
   */
  @State showPrivacyNotice: boolean = false;

  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();
  private theme: ThemeName = THEME_DARK;

  aboutToAppear(): void {
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.applyTheme();
    // 启动时也同步一次系统层：默认深色时状态栏内容色就是白的，但显式设一次可保证
    // "上次退出时是浅色"的情况下状态栏文字块也是黑的（EntryAbility 设了 colorMode，这里兜一道底）
    applyThemeToSystem(this.getUIContext().getHostContext() as Context, this.theme);
    this.load();
    // 首次启动（或隐私政策升版后）提示阅读隐私政策 —— 合规硬性要求，见审核驳回第 1 条
    const agreed: number = this.prefs.getPrivacyAgreedVersion();
    hilog.info(DOMAIN, TAG, 'privacy agreed=%{public}d current=%{public}d show=%{public}s',
      agreed, PRIVACY_VERSION, String(agreed < PRIVACY_VERSION));
    this.showPrivacyNotice = agreed < PRIVACY_VERSION;
  }

  /** 阅读页进度写库完成 → 重拉书架数据（修"返回书架进度不刷新"，审核驳回第 3 条） */
  onProgressSaved(): void {
    hilog.info(DOMAIN, TAG, 'onProgressSaved fired, reloading shelf');
    this.load();
  }

  onPageShow(): void {
    // 从设置页返回：主题可能改了
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.prefs.reload();
    this.applyTheme();
    // **必须重新拉一次书籍与进度**（2026-09-26 审核驳回第 3 条修的就是这里）：
    // 以前只在 aboutToAppear 里 load 过一次，从阅读页返回书架时进度条不刷新，
    // 要杀掉应用重进才更新 —— 审核员实测到了。本地数据库查一次很快，直接重查最稳。
    this.load();
  }

  private applyTheme(): void {
    const theme: ThemeName = this.prefs.getTheme();
    if (theme !== this.theme) {
      this.theme = theme;
      this.palette = paletteOf(theme);
      // 主题变了必须同步系统层（状态栏文字颜色 + 系统深色模式），否则浅色下白字白底看不见
      applyThemeToSystem(this.getUIContext().getHostContext() as Context, theme);
    }
  }

  private async load(): Promise<void> {
    try {
      await this.db.open(this.getUIContext().getHostContext() as Context);
      const list: BookRecord[] = await this.db.listBooks();
      const percents: Map<string, number> = await this.db.listAllProgress();
      // 组装交给 ShelfRules.toShelfItems：缺进度与 NaN 都记 0，脏数据漏不进进度条
      const built: ShelfItem[] = toShelfItems(list, percents);
      this.items = built;
      this.groups = collectGroups(list);
      if (this.activeGroup !== GROUP_ALL && this.groups.indexOf(this.activeGroup) < 0) {
        // 分组被删空了 → 回到全部，避免停在空列表
        this.activeGroup = GROUP_ALL;
      }
      this.resume = built.length > 0 ? built[0] : null;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load shelf failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 先按分组筛，再按阅读状态筛（两个维度独立） */
  private visibleItems(): ShelfItem[] {
    if (this.activeGroup === GROUP_ALL) {
      return filterByStatus(this.items, this.statusFilter);
    }
    const grouped: ShelfItem[] = [];
    for (let i = 0; i < this.items.length; i++) {
      const it: ShelfItem = this.items[i];
      if (normalizeGroupName(it.book.groupName) === this.activeGroup) {
        grouped.push(it);
      }
    }
    return filterByStatus(grouped, this.statusFilter);
  }

  /**
   * 「用其他应用打开」一本书 → 直接导入。
   * 这是导入的**保底入口**：系统 picker 不显示 .mobi/.azw3，但用户可以在文件管理器或
   * 微信里长按那本书 → 用其他应用打开 → 选 RockReader。
   */
  onIncomingFile(): void {
    const uri: string = this.incomingUri;
    if (uri.length === 0) {
      return;
    }
    // 立刻清掉：否则下次任何 AppStorage 同步都会重复导入同一本
    AppStorage.setOrCreate('pendingImportUri', '');
    this.importUri(uri);
  }

  private async importUri(uri: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    try {
      const importer = new BookImporter(this.db, this.getUIContext().getHostContext() as Context);
      const result: ImportResult = await importer.importFromUri(uri);
      const msg = reasonText(result.reason);
      if (msg.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: msg });
      }
      await this.load();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'import uri failed: %{public}s', JSON.stringify(e));
    } finally {
      this.busy = false;
    }
  }

  private async onImport(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    let result: ImportResult = { ok: false, reason: 'CANCELLED', book: null };
    let threw: boolean = false;
    try {
      const importer = new BookImporter(this.db, this.getUIContext().getHostContext() as Context);
      result = await importer.pickAndImport();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'import failed: %{public}s', JSON.stringify(e));
      threw = true;
    }
    // ⚠️ **刷新必须放在 try 之外**：导入是"一本一落库"的，抛异常时前面几本**已经进书架了**；
    // 原来把 `load()` 写在 try 里，异常一旦发生它就被跳过 —— 书在库里、界面却没刷新、
    // 还弹一句"导入失败"，用户看到的就是"明明导入成功了却报失败"（2026-09-23 反馈）。
    await this.load();
    // 文案也不再一律说"失败"：异常只代表"有文件没走完"，已经进去的照样在书架里
    const msg: string = threw ? '有文件导入失败，已导入的在书架里' : reasonText(result.reason);
    if (msg.length > 0) {
      this.getUIContext().getPromptAction().showToast({ message: msg });
    }
    this.busy = false;
  }

  private openEditor(mode: string, item: ShelfItem): void {
    hilog.info(DOMAIN, TAG, 'openEditor: mode=%{public}s id=%{public}s', mode, item.book.id);
    this.editorBookId = item.book.id;
    this.editorMode = mode;
    this.editorText = mode === MODE_RENAME ? item.book.title : normalizeGroupName(item.book.groupName);
  }

  private closeEditor(): void {
    this.editorMode = MODE_NONE;
    this.editorBookId = '';
    this.editorText = '';
  }

  private async submitEditor(): Promise<void> {
    const id: string = this.editorBookId;
    const text: string = this.editorText;
    const mode: string = this.editorMode;
    this.closeEditor();
    try {
      if (mode === MODE_RENAME) {
        const title: string = text.trim();
        if (title.length > 0) {
          await this.db.renameBook(id, title);
        }
      } else if (mode === MODE_GROUP) {
        await this.db.setBookGroup(id, normalizeGroupName(text));
      }
      await this.load();
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'shelf edit failed: %{public}s', JSON.stringify(e));
      this.getUIContext().getPromptAction().showToast({ message: '操作失败' });
    }
  }

  private async doDelete(book: BookRecord): Promise<void> {
    // 兜底：拿不到书就直接返回 —— 否则会去删一个空 id，看起来"点了没反应"
    if (book.id.length === 0) {
      hilog.error(DOMAIN, TAG, 'doDelete aborted: empty book id');
      return;
    }
    try {
      hilog.info(DOMAIN, TAG, 'doDelete start: id=%{public}s path=%{public}s', book.id, book.path);
      // 先删库（书架立刻干净），再清沙箱文件（书副本 + 预切章目录）。
      // 顺序反过来会在中途失败时留下"文件没了、书还在书架上"的脏状态
      await this.db.deleteBook(book.id);
      hilog.info(DOMAIN, TAG, 'doDelete: db row removed, cleaning files');
      removeBookFiles(book);
      await this.load();
      hilog.info(DOMAIN, TAG, 'doDelete done: id=%{public}s', book.id);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete failed: %{public}s', JSON.stringify(e));
    }
  }

  private openBook(book: BookRecord): void {
    this.getUIContext().getRouter().pushUrl({ url: 'pages/Reader', params: { bookId: book.id } });
  }

  @Builder
  cellBar(percent: number, barHeight: number) {
    Row({ space: 2 }) {
      ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (i: number) => {
        Row()
          .layoutWeight(1)
          .height(barHeight)
          .backgroundColor(filledCells(percent, CELLS) > i ? this.palette.text : this.palette.line)
      }, (i: number) => 'c' + i)
    }
    .width('100%')
  }

  @Builder
  bookCover(book: BookRecord, size: number) {
    // 有封面图就渲染图；没有（TXT / EPUB 没写封面 / 抽图失败）才回退首字占位。
    // 注意：@Builder 里**只能写 UI 组件语法** —— 不能先 `const cover = ...` 再判断
    // （ArkTS 会报 "Only UI component syntax can be written here"），所以这里调用两次
    if (coverPathOf(book).length > 0) {
      // ⚠️ `Image` 加载沙箱里的文件**必须带 `file://` 前缀** —— 传裸路径不报错、也不显示，
      // 只是默默空白。这与 `registerFont` / `loadFontSync` 是同一条规则（字体那次就是这么坑的），
      // 本项目在"自定义字体"和"封面图"上各踩了一次。
      Image('file://' + coverPathOf(book))
        .width(size)
        .height(size * 1.4)
        // Contain：各书封面比例不一，绝不裁切（把书名裁掉是最难看的失败）
        .objectFit(ImageFit.Contain)
        .backgroundColor(this.palette.cover)
        .borderRadius(0)
        // ⚠️ **必须关掉 Image 自带的拖拽（默认 true）**：长按时它会先被识别成"准备拖拽"，
        // 把父级 Column 的 LongPressGesture 抢走 —— 症状是**有封面的书长按弹不出菜单**，
        // 而没有封面（首字占位走 Column 分支）的书一切正常。
        // 2026-09-22 实测：0 字节封面（加载失败、无内容可拖）长按正常，真封面加载出来后才坏，
        // 所以曾误判成"MOBI/AZW3 格式的问题"（其实是封面渲染带出来的）。
        // 书架封面本来也不该被拖走 —— 否则会出现"半透明图片跟着手指飘"的怪效果。
        .draggable(false)
    } else {
      Column() {
        Text(book.title.length > 0 ? book.title.substring(0, 1) : '书')
          .fontSize(size * 0.42)
          .fontColor(this.palette.text3)
          .fontWeight(FontWeight.Bold)
      }
      .width(size)
      .height(size * 1.4)
      .backgroundColor(this.palette.cover)
      .borderRadius(0)                       // 书封 0 圆角（已确认）
      .justifyContent(FlexAlign.Center)
    }
  }

  @Builder
  resumeCard(item: ShelfItem) {
    Row({ space: 14 }) {
      this.bookCover(item.book, 58)
      Column({ space: 6 }) {
        // 说清楚这张卡片是干嘛的 —— 没有它，用户会以为这是"多出来的一本书"（真机反馈 #2）
        Text('继续阅读')
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .letterSpacing(1)
        Text(item.book.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.book.format.toUpperCase())
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
        this.cellBar(item.percent, 2)
        Text(percentText(item.percent))
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(14)
    .borderRadius(12)                      // 卡片 12 圆角
    .backgroundColor(this.palette.card)
    .borderWidth(1)
    .borderColor(this.palette.line)
    .onClick(() => this.openBook(item.book))
  }

  @Builder
  /**
   * 分组芯片。选中态**必须在 Builder 内部读 `this.activeGroup`**：
   * @Builder 按值传参不驱动刷新（抽屉档位那个 bug 就是这么来的，见 findings）。
   * 原来写成 `groupChip(name, active)` —— 点分组时选中框不会动。
   */
  groupChip(name: string) {
    Text(name)
      .fontSize(11)
      .fontFamily('monospace')
      .fontColor(this.activeGroup === name ? this.palette.bg : this.palette.text3)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor(this.activeGroup === name ? this.palette.text : 'rgba(0,0,0,0)')
      .borderWidth(1)
      .borderColor(this.activeGroup === name ? this.palette.text : this.palette.line)
      // 视觉约 21vp（11pt + 上下 5 padding），远小于触摸标准 44 → 热区必须撑开
      .accessibilityText(`分组 ${name}`)
      .responseRegion({ x: 0, y: -12, width: '100%', height: 44 })
      .onClick(() => {
        this.activeGroup = name;
      })
  }

  @Builder
  statusChip(label: string, status: string) {
    Text(label)
      .fontSize(11)
      .fontFamily('monospace')
      .fontColor(this.statusFilter === status ? this.palette.bg : this.palette.text3)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor(this.statusFilter === status ? this.palette.text : 'rgba(0,0,0,0)')
      .borderWidth(1)
      .borderColor(this.statusFilter === status ? this.palette.text : this.palette.line)
      // 同 groupChip：视觉约 21vp，热区撑到 44；朗读要说出筛选名
      .accessibilityText(`筛选 ${label}`)
      .responseRegion({ x: 0, y: -12, width: '100%', height: 44 })
      .onClick(() => {
        this.statusFilter = status;
      })
  }

  @Builder
  editorPanel() {
    Column() {
      Column({ space: 12 }) {
        if (this.editorMode === MODE_MENU) {
          Text('管理这本书')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text)
            .alignSelf(ItemAlign.Start)
          this.menuButton('重命名', MODE_RENAME)
          this.menuButton('移动到分组', MODE_GROUP)
          this.menuButton('移除', MODE_DELETE)
        } else if (this.editorMode === MODE_DELETE) {
          Text('移除这本书？')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text)
            .alignSelf(ItemAlign.Start)
          Text('只会从书架移除，不会删除你的原文件。')
            .fontSize(12)
            .fontColor(this.palette.text2)
            .alignSelf(ItemAlign.Start)
          Row({ space: 10 }) {
            // 视觉约 29vp（13pt 文字 + 上下 8 padding），热区补到 44
            Text('取消')
              .fontSize(13)
              .fontColor(this.palette.text3)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .borderWidth(1)
              .borderColor(this.palette.line)
              .accessibilityText('取消')
              .responseRegion({ x: 0, y: -8, width: '100%', height: 44 })
              .onClick(() => this.closeEditor())
            Text('移除')
              .fontSize(13)
              .fontColor(this.palette.bg)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor(this.palette.red)
              .accessibilityText('移除这本书')
              .responseRegion({ x: 0, y: -8, width: '100%', height: 44 })
              .onClick(() => {
                // 顺序要紧：closeEditor() 会清空 editorBookId —— 先把书取出来再关。
                // 这里不用系统的 promptAction.showDialog：它不受我们的色板控制，
                // 且按钮 index 语义在不同平台上不一致（真机反馈 #5 排查中确认的两个坑）。
                const target: BookRecord = this.bookOf(this.editorBookId);
                hilog.info(DOMAIN, TAG, 'remove confirmed: id=%{public}s', target.id);
                this.closeEditor();
                if (target.id.length === 0) {
                  return;
                }
                this.doDelete(target);
              })
          }
          .width('100%')
        } else {
          Text(this.editorMode === MODE_RENAME ? '重命名' : '移动到分组')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text)
            .alignSelf(ItemAlign.Start)
          TextInput({ placeholder: this.editorMode === MODE_RENAME ? '书名' : '分组名', text: this.editorText })
            .fontSize(14)
            .fontColor(this.palette.text)
            .backgroundColor(this.palette.bg)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .onChange((value: string) => {
              this.editorText = value;
            })
          if (this.editorMode === MODE_GROUP) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.groups, (g: string) => {
                Text(g === GROUP_UNFILED ? '移出分组' : g)
                  .fontSize(11)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text)
                  .padding({ left: 9, right: 9, top: 5, bottom: 5 })
                  .borderRadius(10)
                  .borderWidth(1)
                  .borderColor(this.palette.line)
                  .margin({ right: 8, bottom: 8 })
                  .onClick(() => {
                    this.editorText = g;
                  })
              }, (g: string) => 'g' + g)
            }
            .width('100%')
          }
          Row({ space: 10 }) {
            Text('取消')
              .fontSize(13)
              .fontColor(this.palette.text3)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .borderWidth(1)
              .borderColor(this.palette.line)
              .onClick(() => this.closeEditor())
            Text('确定')
              .fontSize(13)
              .fontColor(this.palette.bg)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor(this.palette.text)
              .onClick(() => {
                this.submitEditor();
              })
          }
          .width('100%')
        }
      }
      .width('86%')
      .padding(18)
      .borderRadius(12)
      // 用 overlay（≈92% 主题底色，**不透明**）而不是 card（3%，几乎全透明）：
      // 卡片盖在深色遮罩上，背景一透明，文字就会跟着遮罩走 ——
      // 深色主题是白字所以没事，一切到护眼主题（深褐字）就彻底看不见了（真机反馈 #5）
      .backgroundColor(this.palette.overlay)
      .borderWidth(1)
      .borderColor(this.palette.line)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#CC000000')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  menuButton(label: string, nextMode: string) {
    Text(label)
      .fontSize(14)
      // 用主题的 red（浅底上的红更深，保证「移除」这类危险操作在护眼主题下也看得清）
      .fontColor(nextMode === MODE_DELETE ? this.palette.red : this.palette.text)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: 10, bottom: 10 })
      // 视觉约 34vp → 热区补到 44；朗读要说出菜单项名字
      .accessibilityText(label)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => {
        if (nextMode === MODE_DELETE) {
          this.editorMode = MODE_DELETE;
        } else {
          this.editorMode = nextMode;
          if (nextMode === MODE_RENAME) {
            this.editorText = this.bookOf(this.editorBookId).title;
          } else {
            this.editorText = normalizeGroupName(this.bookOf(this.editorBookId).groupName);
          }
        }
      })
  }

  private bookOf(id: string): BookRecord {
    for (let i = 0; i < this.items.length; i++) {
      if (this.items[i].book.id === id) {
        return this.items[i].book;
      }
    }
    const empty: BookRecord = {
      id: '', title: '', author: '', format: '', path: '', size: 0,
      addedAt: 0, lastReadAt: 0, groupName: ''
    };
    return empty;
  }

  build() {
    Stack() {
      Column() {
        // 顶部
        Row() {
          Text($r('app.string.shelf_title'))
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette.text)
          Text(`${this.items.length} 本`)
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .margin({ left: 10 })
          Blank()
          Text('▤')
            .fontSize(13)
            .fontColor(this.palette.text)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderWidth(1)
            .borderColor(this.palette.line)
            // 视觉 30，热区 46：30vp 的点击目标太小（触摸标准 ≥44）
            .responseRegion({ x: -8, y: -8, width: 46, height: 46 })
            .margin({ left: 8 })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/Stats' });
            })
          Text('Aa')
            .fontSize(13)
            .fontColor(this.palette.text)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .responseRegion({ x: -8, y: -8, width: 46, height: 46 })
            .margin({ left: 8 })
            .onClick(() => {
              this.getUIContext().getRouter().pushUrl({ url: 'pages/Settings' });
            })
          Text(this.busy ? '···' : '＋')
            .fontSize(15)
            .fontColor(this.palette.text)
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .responseRegion({ x: -8, y: -8, width: 46, height: 46 })
            .margin({ left: 8 })
            .onClick(() => {
              this.onImport();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 10, bottom: 14 })

        // 分组筛选（只有存在两个及以上分组时才出现，避免只有「未分组」时白占一行）
        if (this.groups.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              this.groupChip(GROUP_ALL)
              ForEach(this.groups, (g: string) => {
                this.groupChip(g)
                // 键含选中态：键不变 item 不重建，选中样式就不更新
              }, (g: string) => 'chip' + g + (g === this.activeGroup ? '-on' : '-off'))
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          .margin({ bottom: 8 })
        }

        // 阅读状态筛选（未读 / 在读 / 已读）
        if (this.items.length > 0) {
          Row({ space: 8 }) {
            this.statusChip('全部', STATUS_ALL)
            this.statusChip('未读', STATUS_UNREAD)
            this.statusChip('在读', STATUS_READING)
            this.statusChip('已读', STATUS_DONE)
          }
          .width('100%')
          .margin({ bottom: 12 })
        }

        // 继续阅读只在「全部」时显示：它是快捷入口，不是列表项 ——
        // 筛「未读」时顶部还杵着一张在读的书，会让人以为状态判定错了（真机反馈 #2：
        // 用户正是因此以为那本 EPUB 同时出现在未读/在读/已读里）
        if (this.resume !== null && this.activeGroup === GROUP_ALL && this.statusFilter === STATUS_ALL) {
          this.resumeCard(this.resume)
          Row()
            .height(14)
        }

        // 书架网格
        if (this.items.length === 0) {
          // 空态放 slogan：这片空白唯一的作用，就是让人记住我们是谁。
          // 不是营销文案 —— 是品牌承诺（党哥 2026-09-23 定「主句 + 副句」两句）。
          // 主句讲"本地、不上传"，副句讲"断网完整"，两句合起来才是完整的承诺。
          Column({ space: 8 }) {
            Text('书在你手上，哪儿也不去')
              .fontSize(14)
              .fontColor(this.palette.text2)
            Text('断网也能读完整本书')
              .fontSize(11)
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Grid() {
              ForEach(this.visibleItems(), (item: ShelfItem) => {
                GridItem() {
                  Column({ space: 6 }) {
                    this.bookCover(item.book, 88)
                    Text(item.book.title)
                      .fontSize(11.5)
                      .fontColor(this.palette.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    this.cellBar(item.percent, 2)
                    Row() {
                      Text(item.book.format.toUpperCase())
                        .fontSize(9)
                        .fontFamily('monospace')
                        .fontColor(this.palette.text3)
                      Blank()
                      Text(percentText(item.percent))
                        .fontSize(9)
                        .fontFamily('monospace')
                        .fontColor(this.palette.text3)
                    }
                    .width('100%')
                  }
                  .width('100%')
                  // 无障碍：屏幕阅读器要能读出书名（AGC 审核会查可交互组件的朗读标签）
                  .accessibilityText(item.book.title)
                  .onClick(() => this.openBook(item.book))
                  .gesture(LongPressGesture().onAction(() => this.openEditor(MODE_MENU, item)))
                }
              }, (item: ShelfItem) => item.book.id)
            }
            .columnsTemplate('1fr 1fr 1fr')
            .columnsGap(14)
            .rowsGap(16)
            .width('100%')
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)           // 不出现滚动条（家族规则）
        }

        Row() {
          Text('LOCAL ONLY')
            .fontSize(9)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
        }
        .width('100%')
        .padding({ bottom: 16, top: 8 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.palette.bg)
      .padding({ left: 22, right: 22 })

      if (this.editorMode !== MODE_NONE) {
        this.editorPanel()
      }

      // 首次启动的隐私政策提示（合规硬性要求：必须显著提示用户阅读隐私政策）
      if (this.showPrivacyNotice) {
        this.privacyNotice()
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 隐私政策提示弹窗（首次启动 / 政策升版后出现）
   *
   * 三个设计取舍：
   *  ① **不提供"不同意"**：本应用不收集任何个人信息，无需取得同意，只需"提示阅读"；
   *     给拒绝按钮反而让"零数据收集"这件事显得可疑。
   *  ② **不放外链**：应用零联网，打不开浏览器。完整版走应用内 Privacy 页（断网也能看）。
   *  ③ **记版本号而非布尔**：政策实质变更时 PRIVACY_VERSION +1，老用户会再看到。
   */
  @Builder
  privacyNotice() {
    // ⚠️ 必须是 Stack 不是 Column：遮罩要占满 100% 高度，
    // 用 Column 的话卡片会排在遮罩**下面**（跑到屏幕外），实测只露出第一行字。
    Stack() {
      // 遮罩：吃掉点击，避免误触后面的书架
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .opacity(0.6)

      Column() {
        Text('PRIVACY')
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .margin({ bottom: 10 })

        Text('关于你的隐私')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette.text)
          .margin({ bottom: 14 })

        Column() {
          Text('· 不收集任何个人信息，没有账号、没有登录')
          Text('· 书籍与进度只存在你的设备里，不上传')
          Text('· 不申请任何权限，不具备联网能力')
          Text('· 卸载应用即删除全部数据')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .margin({ bottom: 16 })

        Text('完整版见应用内「设置 → 关于 → 隐私政策」')
          .fontSize(11)
          .fontColor(this.palette.text3)
          .width('100%')
          .margin({ bottom: 18 })

        Row({ space: 10 }) {
          Text('查看完整版')
            .fontSize(13)
            .fontColor(this.palette.text2)
            .border({ width: 1, color: this.palette.line })
            .borderRadius(6)
            .height(40)
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Center)
            .onClick(() => {
              router.pushUrl({ url: 'pages/Privacy' });
            })
          Text('我知道了')
            .fontSize(13)
            .fontColor(this.palette.bg)
            .backgroundColor(this.palette.text)
            .borderRadius(6)
            .height(40)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.prefs.setPrivacyAgreedVersion(PRIVACY_VERSION);
              this.showPrivacyNotice = false;
            })
        }
        .width('100%')
      }
      .width('86%')
      .padding({ left: 22, right: 22, top: 24, bottom: 22 })
      .backgroundColor(this.palette.card)
      .borderRadius(14)
      .border({ width: 1, color: this.palette.line })
    }
    .width('100%')
    .height('100%')
  }
}
