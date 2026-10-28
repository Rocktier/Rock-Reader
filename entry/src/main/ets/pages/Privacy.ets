/**
 * 隐私政策页（2026-09-23 新增）
 *
 * 上架硬性要求：应用内必须可查看隐私政策 —— 且**断网时也能看**（外部链接做不到这点）。
 * 正文与外部真源一致：https://www.91hym.cn/devs/756.html#privacy
 * （同一篇文章还含用户协议 `#agreement` 与数据权利 `#rights`），
 * 但**这里是不带 markdown 的纯文本**（ArkUI 直接渲染，不引任何解析）。
 *
 * ⚠️ 2026-10-20 起该页扩为 **Rock 家族通用页**（一篇覆盖 Rock阅读 + Rock私记 两款，
 * 与 Rock私记 共用同一个链接），所以这里的正文也从"Rock阅读 专属版"改为"家族版"。
 * 应用内只放隐私政策章；用户协议 / 数据权利只在网页侧提供。
 *
 * 两条不能动的口径（党哥 2026-09-18 定）：
 *  ① 只讲品牌承诺「核心数据不联网」，**不提广告开关、不引导用户去关广告**；
 *  ② 但**政策本身必须如实写明联网与广告**（合规是合规，应用内不引导是另一件事）。
 *
 * 文案改动必须同步回那篇文章 —— 两处不一致，上架时就是"政策与实现不符"的拒审理由。
 */
import { Palette, paletteOf, THEME_DARK } from '../common/Theme';
import { formPadOf } from '../common/LayoutStyle';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { RR_FS_TITLE, RR_FS_LABEL, RR_FS_META, RR_SP_MD, RR_SP_LG, RR_SP_XL, RR_SP_2XL, RR_SP_3XL, RR_SP_4XL, RR_SP_6XL } from '../theme/RrTokens';

/** 段落：一段一元素，标题行以 '#' 开头（渲染时加粗并留上间距） */
const PRIVACY_LINES: Array<string> = [
  '#一、我们收集什么',
  '不收集任何个人信息。',
  '两款应用都没有账号、没有登录、没有云端同步。我们不知道你是谁，',
  '也无法把你的任何数据关联到你这个人。',
  '#二、你的数据存在哪里',
  '全部存在你的设备本地（应用沙箱内），不会离开你的设备。',
  'Rock阅读：',
  '· 导入的书籍：应用沙箱（从你选中的文件复制一份）',
  '· 阅读进度：设备本地数据库',
  '· 设置（字号、行距、主题、字体、朗读偏好）：设备本地偏好存储',
  '· 字体文件：随应用内置，安装即在你的设备上',
  'Rock私记（日记内容经 AES-256-GCM 加密后存储）：',
  '· 日记正文与索引：应用沙箱，密钥由你的主密码派生，只存在于内存中；',
  '· 心情与图片：应用沙箱（图片单独加密存储，正文只保存引用）；',
  '· 设置（字号、主题等）：设备本地偏好存储；',
  '· 备份文件：由你主动导出到你自选的目录，同样经过加密。',
  '以上任何一项都不会上传。卸载应用 = 该应用的上述数据全部删除；',
  '你也可以在应用内删除单本书 / 单篇日记，同时删除它的副本与相关记录。',
  '#三、我们联网吗',
  '不联网。两款应用都没有任何需要联网的功能：',
  '· Rock阅读：书籍由你从本地导入，字体已内置在应用里，',
  '　阅读、目录、搜索、统计与朗读全部在你的设备上完成；',
  '· Rock私记：写日记、看日历、搜索、导出备份、语音转文字，全部在你的设备上完成。',
  'Rock阅读 的朗读使用设备自带的语音合成能力，在你的设备上完成，',
  '不会把书本内容发送到任何服务器。（个别朗读音色由系统提供，',
  '首次使用时可能需要下载语音资源；下载的是语音模型本身，不包含你的任何数据，',
  '下载完成后朗读依旧离线进行。）',
  '我们也没有申请网络权限（见第四节）—— 这不是"默认关闭"，',
  '而是应用本身不具备联网能力。',
  '#四、我们申请了哪些权限',
  'Rock阅读：不申请任何权限。',
  'Rock私记：只申请麦克风一项权限，用于「语音转文字」——你按下录音按钮说话，',
  '系统把它转成文字插进日记正文。除此之外两款应用都不申请任何权限：',
  '没有网络、位置、通讯录、相机、短信、通话记录、日历、健康数据、',
  '设备标识符等任何权限。',
  '关于麦克风，我们说明白：',
  '· 只有你主动点「语音」按钮时才申请，且授权后也不会自动开启；',
  '· 识别用的是设备自带的离线语音识别，声音在你的设备上转成文字，不联网；',
  '· 录音本身不会被保存，也不会单独存成音频文件，',
  '　只有转出来的文字会写进你的日记（与手写的文字同样加密存储）；',
  '· 你拒绝授权也能正常使用全部其他功能。',
  '关于你的文件：',
  '· Rock阅读：导入书籍通过系统文件选择器完成，是你主动挑选的那一个文件，',
  '　应用只读取它并复制一份到沙箱；',
  '· Rock私记：插入图片、导出与导入备份，也都通过系统文件选择器完成，',
  '　是你主动指定的那一个文件或位置。',
  '两款应用都不会扫描、读取或上传你设备上的其他任何文件。',
  '#五、第三方 SDK 与开源素材',
  '当前版本不含任何第三方 SDK，也不含任何广告服务与数据统计服务。',
  'Rock阅读 内置字体基于思源宋体（Noto Serif SC）做 GB2312 子集而来，',
  '以 SIL OFL 1.1 授权发布，可免费商用；原字体的版权归其原作者所有。',
  'Rock私记 未内置任何第三方字体或素材。',
  '#六、数据出境',
  '不存在。你的数据不出设备，我们也没有任何服务器可接收。',
  '#七、未成年人',
  '两款应用都不提供个性化推荐，不基于用户画像推送内容。',
  '未成年人使用不产生额外数据收集。',
  '#八、你的权利',
  '· 查看与导出：数据就在设备上，应用内可直接查看（Rock私记 还可随时修改）；',
  '　Rock阅读 如需导出，可在卸载前通过系统文件管理访问应用目录；',
  '　Rock私记 可在应用内导出加密备份（.rkdbak）或导出为 TXT / Markdown；',
  '· 删除：Rock阅读 可在应用内删除单本书及其记录；',
  '　Rock私记 可在应用内删除单篇日记；卸载应用可删除该应用全部数据；',
  '· 无需任何操作：两款应用都不具备联网能力，因此没有需要撤回的授权。',
  '#九、政策更新',
  '如本政策发生实质性变更，会在应用内及上架页面更新。',
  '若不同意，可停止使用并卸载（卸载会删除全部本地数据）。',
  '#十、联系我们',
  '如对本政策有疑问，或需要行使上述权利，可通过邮件联系：',
  'danglei328@163.com',
  '我们会在合理期限内答复。'
];

@Entry
@Component
struct Privacy {
  @State palette: Palette = paletteOf(THEME_DARK);
  /**
   * 版心单侧补丁（vp）：P0-5 大屏适配。宽屏上政策正文拉满 1000+vp 一行
   * 五六十个字，根本读不动 —— 封顶 560vp 居中（formPadOf，CI 有单测）。
   * 0 = 手机竖屏 / 还没测到视口，行为与旧版一致。
   */
  @State private padX: number = 0;
  private prefs: ReaderPrefs = new ReaderPrefs();

  aboutToAppear(): void {
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.palette = paletteOf(this.prefs.getTheme());
  }

  onPageShow(): void {
    this.prefs.reload();
    this.palette = paletteOf(this.prefs.getTheme());
  }

  @Builder
  /** 段落渲染：'#' 开头当小标题，其余当正文（行数固定，不用 LazyForEach） */
  lineView(text: string) {
    if (text.indexOf('#') === 0) {
      Text(text.substring(1))
        .fontSize(RR_FS_LABEL)
        .fontColor(this.palette.text)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: RR_SP_3XL, bottom: RR_SP_MD })
    } else {
      Text(text)
        .fontSize(RR_FS_META)
        .fontColor(this.palette.text2)
        .width('100%')
        .margin({ bottom: RR_SP_LG })
    }
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
        Text('PRIVACY')
          .fontSize(RR_FS_META)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: RR_SP_MD })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: RR_SP_2XL, right: RR_SP_3XL, top: RR_SP_XL, bottom: RR_SP_2XL })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      Scroll() {
        Column() {
          ForEach(PRIVACY_LINES, (line: string) => {
            this.lineView(line)
          // key 用序号：正文里可能有重复段落，拿内容当 key 会冲突（ForEach 键必须唯一）
          }, (line: string, idx: number) => 'p' + idx)
        }
        .width('100%')
        .padding({ left: RR_SP_4XL + this.padX, right: RR_SP_4XL + this.padX, top: RR_SP_2XL, bottom: RR_SP_6XL })
        .alignItems(HorizontalAlign.Start)
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    // 视口宽（vp）→ 版心补丁；旋转 / 分屏会自动重算（与 Reader.ets 同款 onAreaChange）
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.padX = formPadOf(newValue.width as number);
    })
  }
}
