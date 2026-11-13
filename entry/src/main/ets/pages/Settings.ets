/**
 * 设置页
 * 设计依据：docs/v1-design.md §8 ——
 *  ① **一律不用滑块**：字号/行距/边距全是档位芯片（家族铁律）；
 *  ② 芯片 4vp / 卡片 16vp（华为官方圆角五档，2026-10-10 原生化后对齐）；
 *  ③ 文案只讲品牌承诺「核心数据不联网」，不提广告、不提联网开关（spec §8.5）。
 *
 * 数值唯一真源在 common/LayoutStyle.ets，本页**只写档位序号**。
 * 从阅读页进来：返回时阅读页会按字符偏移复原位置（切档位不跳页）。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReaderPrefs } from '../data/ReaderPrefs';
import {
  Palette, paletteOf, themeLabel,
  THEME_AUTO, THEME_DARK, THEME_GREEN, THEME_LIGHT, THEME_SEPIA, THEME_SYSTEM, ThemeName
} from '../common/Theme';
import { currentPalette } from '../common/ThemeRuntime';
import { formPadOf } from '../common/LayoutStyle';
import { FontStore } from '../data/FontStore';
import { BookDb } from '../data/BookDb';
import { rrExportBackup, rrImportBackup } from '../data/RrBackup';
import { common } from '@kit.AbilityKit';
import { FONT_CATALOG, FontEntry } from '../common/FontCatalog';
import { RR_FS_TITLE, RR_FS_HEADING, RR_FS_BODY, RR_FS_LABEL, RR_FS_META, RR_FS_DIGIT, RR_FS_MICRO, RR_SP_XS, RR_SP_SM, RR_SP_MD, RR_SP_LG, RR_SP_XL, RR_SP_2XL, RR_SP_3XL, RR_SP_4XL, RR_SP_5XL, RR_RADIUS_COVER } from '../theme/RrTokens';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const CHIP_SIZE: number = 44;
const CHIP_HEIGHT: number = 34;
/** 系统字体列表最多显示多少项（有些设备会返回几十项，取够用的量） */
const MAX_FONT_ITEMS: number = 40;
/** 设置页「全局默认主题」档位；与阅读页抽屉同一套顺序，标签统一走 themeLabel */
const THEME_CHOICES: ThemeName[] = [
  THEME_SYSTEM, THEME_AUTO, THEME_DARK, THEME_LIGHT, THEME_SEPIA, THEME_GREEN
];

@Entry
@Component
struct Settings {
  @State palette: Palette = paletteOf(THEME_LIGHT);
  /** 系统深浅（P0-1）：EntryAbility 写 AppStorage，@Watch 重算色板 */
  @StorageProp('systemDark') @Watch('onSystemDarkChanged') systemDark: boolean = false;
  @State theme: ThemeName = THEME_SYSTEM;
  /** TXT 正文净化（去广告） */
  @State purifyOn: boolean = true;
  /** 简繁：'off' | 's2t' | 't2s' */
  @State convertMode: string = 'off';
  /** '' = 系统默认 */
  @State fontFamily: string = '';
  @State fontFamilies: string[] = [];
  /** 已就位的内置字体 id */
  @State downloadedIds: string[] = [];
  /** 整库备份：结果说明 / 防重复点击 / 导入二次确认 */
  @State backupNote: string = '';
  @State backupBusy: boolean = false;
  @State importArmed: boolean = false;
  /**
   * 版心单侧补丁（vp）：P0-5 大屏适配。设置项在宽屏上拉满一行五六十个字，
   * 扫视困难且整页摊成扁带 —— 封顶 560vp 居中（formPadOf，CI 有单测）。
   * 0 = 手机竖屏 / 未测量，行为与旧版一致。
   */
  @State private padX: number = 0;

  private prefs: ReaderPrefs = new ReaderPrefs();
  private fontStore: FontStore | null = null;
  private db: BookDb = new BookDb();

  /** 系统深浅变了（控制中心切换）→ 只换色板，不动页面栈 / 滚动位置（P0-1） */
  private onSystemDarkChanged(): void {
    this.palette = currentPalette(this.theme);
  }

  aboutToAppear(): void {
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.fontStore = new FontStore(this.getUIContext().getHostContext() as Context);
    this.theme = this.prefs.getTheme();
    this.fontFamily = this.prefs.getFontFamily();
    this.purifyOn = this.prefs.isPurifyOn();
    this.convertMode = this.prefs.getConvertMode();
    this.palette = currentPalette(this.theme);
    this.refreshFontState();
    this.registerLocalFonts();
    this.loadSystemFonts();
  }

  onPageShow(): void {
    // 主题/字体现在**也能在阅读页的抽屉里改** → 回来时重读，否则两页配色与字体会不一致
    this.prefs.reload();
    const theme: ThemeName = this.prefs.getTheme();
    if (theme !== this.theme) {
      this.theme = theme;
    }
    // 系统深浅可能在后台变了（P0-1）⇒ 无条件重算，不能只在 theme 变化时算
    this.palette = currentPalette(theme);
    this.fontFamily = this.prefs.getFontFamily();
    this.loadSystemFonts();
  }

  /**
   * 2.0.0 设置页选全局主题：写全局 + 同步所有书级覆盖的 theme 字段。
   *
   * 老用户升级后仍全黑的根因有**两层**（全局 `theme=dark` + `book_pref_*` 里的
   * `theme=dark`）；只写全局会被书级覆盖盖住 ⇒ 一步同步两层。
   * 不做静默迁移：用户不点就不改，尊重主动选深色的用户，也不需要迁移标记位。
   */
  private pickGlobalTheme(theme: ThemeName): void {
    this.prefs.saveTheme(theme);
    const books: number = this.prefs.applyThemeToAllBooks(theme);
    this.theme = this.prefs.getTheme();
    this.palette = currentPalette(this.theme);
    hilog.info(DOMAIN, TAG, 'global theme: %{public}s books=%{public}d', this.theme, books);
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
    } catch (e) {
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
    store.syncBuiltin();
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
    store.syncBuiltin();
    const list: FontEntry[] = store.downloaded();
    for (let i: number = 0; i < list.length; i++) {
      try {
        this.getUIContext().getFont().registerFont({
          familyName: list[i].familyName,
          // file:// uri：裸路径静默失败（字体切换不生效的根因，见 FontStore.uriOf）
          familySrc: store.uriOf(list[i])
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'registerFont failed: %{public}s', JSON.stringify(e));
      }
    }
  }

  private pickFont(family: string): void {
    this.fontFamily = family;
    this.prefs.saveFontFamily(family);
  }

  /** 整库备份：交给系统文件选择器挑位置，取消不算失败（不弹提示） */
  private async runExport(): Promise<void> {
    if (this.backupBusy) {
      return;
    }
    this.backupBusy = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await this.db.open(ctx);
      const r = await rrExportBackup(ctx, this.db);
      this.backupNote = r.text;
    } catch (e) {
      this.backupNote = '导出失败：' + JSON.stringify(e);
    }
    this.backupBusy = false;
  }

  /** 导入会整库覆盖 ⇒ 两次点击才执行，不用弹窗、不引新 Kit */
  private async runImport(): Promise<void> {
    if (this.backupBusy) {
      return;
    }
    if (!this.importArmed) {
      this.importArmed = true;
      this.backupNote = '导入会替换当前书架上的全部书与记录。确认请再点一次。';
      return;
    }
    this.importArmed = false;
    this.backupBusy = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      await this.db.open(ctx);
      const r = await rrImportBackup(ctx, this.db);
      this.backupNote = r.text.length > 0 ? r.text : '';
    } catch (e) {
      this.backupNote = '导入失败：' + JSON.stringify(e);
    }
    this.backupBusy = false;
  }

  private isDownloaded(id: string): boolean {
    return this.downloadedIds.indexOf(id) >= 0;
  }

  private pickPurify(on: boolean): void {
    this.purifyOn = on;
    this.prefs.setPurify(on);
  }

  private pickConvert(mode: string): void {
    this.convertMode = mode;
    this.prefs.setConvertMode(mode);
  }

  /** 正文处理：去广告（净化）+ 简繁转换 */
  @Builder
  textSection() {
    Column() {
      // 净化开关
      //
      // ⚠️ 「开 / 关」是这一项的**状态**（读法是「正文去广告：开」），不是操作区，
      //    所以紧跟标签、不钉行尾。理由（第一性原理，2026-11-13）：
      //    行宽 560vp 是「连续文字」的可读宽度，键值行的自然宽度只有 ~320vp。
      //    把状态钉在行尾 ⇒ 中间那段空白是 `560 − 标签 − 状态` 的**减法余数**，
      //    不是被设计的间距（实测 PC 446vp / 平板 443vp）。
      //    余数应当落在**行尾**（那里空着只是"这一行到这儿为止"），
      //    落在键与值**中间**就会被读成断裂。手机 320vp 行宽下两者恰好重合，
      //    所以旧写法在手机上一直是对的 —— 这是"只在宽屏才暴露"的缺陷。
      Column() {
        Row({ space: RR_SP_LG }) {
          Text('正文去广告')
            .fontSize(RR_FS_BODY)
            .fontColor(this.palette.text)
          Text(this.purifyOn ? '开' : '关')
            .fontSize(RR_FS_META)
            .fontFamily('monospace')
            .fontColor(this.purifyOn ? this.palette.bg : this.palette.text2)
            .backgroundColor(this.purifyOn ? this.palette.text : this.palette.card)
            .border({ width: 1, color: this.purifyOn ? this.palette.text : this.palette.line })
            .borderRadius(RR_RADIUS_COVER)
            .height(CHIP_HEIGHT)
            .padding({ left: RR_SP_3XL, right: RR_SP_3XL })
            .accessibilityText('正文去广告：' + (this.purifyOn ? '开' : '关'))
            .onClick(() => this.pickPurify(!this.purifyOn))
        }
        .alignItems(VerticalAlign.Center)
        Text('自动删除 TXT 里的站点水印、公众号推广与网址')
          .fontSize(RR_FS_DIGIT)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_XS })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: RR_SP_2XL, bottom: RR_SP_2XL })

      // 简繁
      Column() {
        Text('简繁')
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        Row({ space: 8 }) {
          ForEach([['off', '不转换'], ['s2t', '简→繁'], ['t2s', '繁→简']], (it: string[]) => {
            Text(it[1])
              .fontSize(RR_FS_META)
              .fontFamily('monospace')
              .fontColor(this.convertMode === it[0] ? this.palette.bg : this.palette.text2)
              .backgroundColor(this.convertMode === it[0] ? this.palette.text : this.palette.card)
              .border({ width: 1, color: this.convertMode === it[0] ? this.palette.text : this.palette.line })
              .borderRadius(RR_RADIUS_COVER)
              .height(CHIP_HEIGHT)
              .padding({ left: RR_SP_2XL, right: RR_SP_2XL })
              // 视觉 CHIP_HEIGHT(34) < 触摸标准 44 → 热区上下各撑 5；朗读要说出"简繁 不转换"
              .stateStyles({ pressed: { opacity: 0.6 } })
              .accessibilityText(`简繁 ${it[1]}`)
              .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
              .onClick(() => this.pickConvert(it[0]))
          }, (it: string[]) => 'c' + it[0])
        }
        .width('100%')
        .margin({ top: RR_SP_XL })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ bottom: RR_SP_2XL })
    }
    .width('100%')
  }

  @Builder
  fontChip(label: string, family: string) {
    Text(label)
      .fontFamily(family)                  // 用该字体本身渲染，直接看效果
      .fontSize(RR_FS_LABEL)
      .fontColor(this.fontFamily === family ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.fontFamily === family ? this.palette.text : this.palette.card)
      .border({ width: 1, color: this.fontFamily === family ? this.palette.text : this.palette.line })
      .borderRadius(RR_RADIUS_COVER)
      .height(CHIP_HEIGHT)
      .padding({ left: RR_SP_2XL, right: RR_SP_2XL })
      .stateStyles({ pressed: { opacity: 0.6 } })
      .accessibilityText(`字体 ${label}`)
      .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
      .onClick(() => this.pickFont(family))
  }

  /** 字体：横向芯片列表（系统已装字体 + 内置宋体；**首版零联网，无可下载款**） */
  @Builder
  fontSection() {
    Column() {
      // 字体：值（「N 款可选」/「系统默认」）是标签的补语，紧跟标签。
      // 同「正文去广告」：宽屏下 `Blank()` 会把它推到 440vp 之外。
      Row({ space: RR_SP_LG }) {
        Text('字体')
          .fontSize(RR_FS_BODY)
          .fontColor(this.palette.text)
        Text(this.fontFamily.length > 0 ? `${this.fontFamilies.length} 款可选` : '系统默认')
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: RR_SP_LG })

      // 预览：直接看这套字体在正文里的样子
      Text('思维力是孩子学习力的基础 ABC 123')
        .fontFamily(this.fontFamily)
        .fontSize(RR_FS_HEADING)
        .fontColor(this.palette.text2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ bottom: RR_SP_2XL })

      Scroll() {
        Row({ space: 8 }) {
          this.fontChip('系统默认', '')
          ForEach(this.fontFamilies, (family: string) => {
            this.fontChip(family, family)
          }, (family: string) => 'fam' + family)
          ForEach(FONT_CATALOG, (entry: FontEntry) => {
            if (this.isDownloaded(entry.id)) {
              this.fontChip(entry.displayName, entry.familyName)
            }
          }, (entry: FontEntry) => 'own' + entry.id)
        }
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // 字体全部内置在 HAP 里：没有下载通道、没有联网代码（2026-11-12 清理）
      Text('字体已内置在应用里，断网可用。\n换字体不需要下载，也不需要联网。')
        .fontSize(RR_FS_MICRO)
        .fontColor(this.palette.text3)
        .margin({ top: RR_SP_XL })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: RR_SP_3XL, bottom: RR_SP_3XL })
  }

  /** 书库备份：把「书 + 进度 + 书签 + 摘录」搬走，断网可用、零权限 */
  @Builder
  backupSection() {
    Column() {
      Text('书库备份')
        .fontSize(RR_FS_BODY)
        .fontColor(this.palette.text)
        .width('100%')
        .margin({ bottom: RR_SP_LG })

      Text('把书、阅读进度、书签和摘录打包成一个文件，由你选地方保存。\n' +
        '重装或换机后导入即可还原；导入会替换当前书架。')
        .fontSize(RR_FS_DIGIT)
        .fontColor(this.palette.text3)
        .width('100%')
        .margin({ bottom: RR_SP_XL })

      Row({ space: 8 }) {
        Text(this.backupBusy ? '正在处理…' : '导出整库备份')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text)
          .padding({ left: RR_SP_2XL, right: RR_SP_2XL })
          .height(34)
          .border({ width: 1, color: this.palette.line })
          .accessibilityText('导出整库备份')
          .onClick(() => this.runExport())
        Text(this.importArmed ? '确认导入（替换当前书架）' : '从备份导入')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text)
          .padding({ left: RR_SP_2XL, right: RR_SP_2XL })
          .height(34)
          .border({ width: 1, color: this.palette.line })
          .accessibilityText(this.importArmed ? '确认导入，替换当前书架' : '从备份导入')
          .onClick(() => this.runImport())
      }
      .width('100%')
      .margin({ bottom: RR_SP_XL })

      if (this.backupNote.length > 0) {
        Text(this.backupNote)
          .fontSize(RR_FS_DIGIT)
          .fontColor(this.palette.text2)
          .width('100%')
          .margin({ bottom: RR_SP_XL })
      }

      Text('备份不含阅读设置（字号、主题留在本机）。全程不联网，不申请任何权限。')
        .fontSize(RR_FS_MICRO)
        .fontColor(this.palette.text3)
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: RR_SP_3XL, bottom: RR_SP_3XL })
  }

  build() {
    Column() {
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
        Text('SETTINGS')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: RR_SP_MD })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      // 大屏：顶栏必须跟内容区对齐（否则标题飘在窗口最左、内容却在版心里，错位 200+vp）
      .padding({
        left: RR_SP_2XL + this.padX, right: RR_SP_3XL + this.padX,
        top: RR_SP_XL, bottom: RR_SP_2XL
      })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      // P0-2（2026-11-08）：作用域写在标题下 —— 与阅读页抽屉的「本书排版」
      // 一眼分得开。这里是全局默认，对所有书生效；那一处只对当前这本书生效。
      Text('全局默认 · 对所有书生效')
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text3)
        .width('100%')
        .padding({
          left: RR_SP_2XL + this.padX, right: RR_SP_3XL + this.padX,
          top: RR_SP_SM, bottom: RR_SP_SM
        })

      // 内容可能超过一屏（加上书库备份区）→ 整段可滚动
      Scroll() {
        Column() {
          // 排版档位已移到**阅读页的抽屉**：那里改一下正文立刻跟着变（能边看边调），
          // 本页只留"与正文内容/资源相关"的设置，避免同一项两处维护。
          //
          // ⚠️ 显式断行（2026-11-06）：字号从 10 提到 11 之后这句在 3x 屏上放不下，
          //    自动换行会把结尾的字甩成孤字单独一行 —— 内容没丢，但看着像排版事故。
          //    断点规则：每行不超过 ~24 字，前半说"有什么可调"、后半说"去哪调"。
          // 2026-11-08 P0-2：入口已从 `A a` 改名「本书排版」，说明必须同步；
          // 并补一句作用域 —— 阅读页抽屉是**每本书覆盖**，本页标题的「全局默认」只管本页这些项。
          Text('字号 / 行距 / 边距 / 字重\n在阅读页里调：点屏幕中间 → 本书排版\n那里改的是当前这本书，可应用到所有书')
            .fontSize(RR_FS_DIGIT)
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ bottom: RR_SP_2XL })

          // 2.0.0：全局默认主题。老用户「整页黑」有两层根因，这里一步同步两层。
          Text('主题 · 全局默认')
            .fontSize(RR_FS_BODY)
            .fontColor(this.palette.text)
            .width('100%')
            .margin({ bottom: RR_SP_LG })

          // ⚠️ 不用带参 @Builder：V1 下参数不追踪 @State，选中态会定死。
          //    内联在 ForEach 里直接读 this.theme；Flex 换行让 6 档全部可见，
          //    不用横向 Scroll 把选项藏起来（HIG：别让用户猜还有更多）。
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(THEME_CHOICES, (t: ThemeName) => {
              Text(themeLabel(t))
                .fontSize(RR_FS_LABEL)
                .fontColor(this.theme === t ? this.palette.bg : this.palette.text2)
                .backgroundColor(this.theme === t ? this.palette.text : this.palette.card)
                .border({ width: 1, color: this.theme === t ? this.palette.text : this.palette.line })
                .borderRadius(RR_RADIUS_COVER)
                .height(CHIP_HEIGHT)
                .padding({ left: RR_SP_2XL, right: RR_SP_2XL })
                .margin({ right: RR_SP_SM, bottom: RR_SP_SM })
                .stateStyles({ pressed: { opacity: 0.6 } })
                .accessibilityText('全局主题：' + themeLabel(t))
                .responseRegion({ x: 0, y: -5, width: '100%', height: 44 })
                .onClick(() => this.pickGlobalTheme(t))
            }, (t: ThemeName) => t)
          }
          .width('100%')
          .margin({ bottom: RR_SP_LG })

          Text('改动会同时应用到所有已读的书\n阅读页「本书排版」只改当前这一本')
            .fontSize(RR_FS_DIGIT)
            .fontColor(this.palette.text3)
            .width('100%')
            .margin({ bottom: RR_SP_2XL })

          this.textSection()

          this.fontSection()

          this.backupSection()

          // 「关于」入口：隐私政策在里面（上架要求应用内可查看），
          // 入口名写"关于"而不是"隐私政策" —— 用户找的是"这是什么应用"，顺路才看政策。
          Row() {
            Text('关于')
              .fontSize(RR_FS_LABEL)
              .fontColor(this.palette.text)
            Blank()
            Text('›')
              .fontSize(RR_FS_HEADING)
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .padding({ top: RR_SP_3XL, bottom: RR_SP_2XL })
          .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
          .accessibilityText('关于本应用与隐私政策')
          .onClick(() => {
            router.pushUrl({ url: 'pages/About' });
          })
          .responseRegion({ x: 0, y: -4, width: '100%', height: 52 })
        }
        .width('100%')
        .padding({ left: RR_SP_4XL + this.padX, right: RR_SP_4XL + this.padX, top: RR_SP_3XL, bottom: RR_SP_LG })
        .alignItems(HorizontalAlign.Start)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)

      Column() {
        // 底部这块是"用户一定会扫到的位置" → 放 slogan（党哥 2026-09-23 定）。
        // 承诺细节（核心数据不联网 / 书籍与进度在本机）已迁到「关于」页，本页不重复。
        Text('书在你手上，哪儿也不去')
          .fontSize(RR_FS_META)
          .fontColor(this.palette.text2)
        Text('断网也能读完整本书')
          .fontSize(RR_FS_DIGIT)
          .fontColor(this.palette.text3)
          .margin({ top: RR_SP_MD })
      }
      .width('100%')
      .padding({ left: RR_SP_4XL + this.padX, right: RR_SP_4XL + this.padX, bottom: RR_SP_5XL })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    // 视口宽（vp）→ 版心补丁；旋转 / 分屏自动重算
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.padX = formPadOf(newValue.width as number, RR_SP_4XL);
    })
  }
}
