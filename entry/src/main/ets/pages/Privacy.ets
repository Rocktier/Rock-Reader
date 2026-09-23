/**
 * 隐私政策页（2026-09-23 新增）
 *
 * 上架硬性要求：应用内必须可查看隐私政策 —— 此前只躺在私有仓的草稿里，用户看不见。
 * 正文与 `harmony-docs/apps/RockReader/docs/privacy-policy-draft.md` 一致，
 * 但**这里是不带 markdown 的纯文本**（ArkUI 直接渲染，不引任何解析）。
 *
 * 两条不能动的口径（党哥 2026-09-18 定）：
 *  ① 只讲品牌承诺「核心数据不联网」，**不提广告开关、不引导用户去关广告**；
 *  ② 但**政策本身必须如实写明联网与广告**（合规是合规，应用内不引导是另一件事）。
 *
 * 文案改动必须同步回那份草稿 —— 两处不一致，上架时就是"政策与实现不符"的拒审理由。
 */
import { Palette, paletteOf, THEME_DARK } from '../common/Theme';
import { ReaderPrefs } from '../data/ReaderPrefs';

/** 段落：一段一元素，标题行以 '#' 开头（渲染时加粗并留上间距） */
const PRIVACY_LINES: Array<string> = [
  '#一、我们收集什么',
  '不收集任何个人信息。',
  'Rock阅读没有账号、没有登录、没有云端同步。我们不知道你是谁，也无法把你的任何数据关联到你这个人。',
  '#二、你的数据存在哪里',
  '全部存在你的设备本地（应用沙箱内），不会离开你的设备：',
  '· 导入的书籍：应用沙箱（从你选中的文件复制一份）',
  '· 阅读进度：设备本地数据库',
  '· 设置（字号、行距、主题、字体）：设备本地偏好存储',
  '· 已下载的字体文件：应用沙箱',
  '以上任何一项都不会上传。卸载应用 = 上述数据全部删除；你也可以在应用内删除单本书，同时删除它的副本与阅读记录。',
  '#三、我们什么时候会联网',
  '本应用的核心功能完全离线可用。联网只有两种情形，且都不涉及上传你的任何数据：',
  '1. 下载字体包 —— 只有你主动点击「下载」时发起。下载的是开源字体文件，过程不携带任何身份或行为信息，下载后校验文件完整性。',
  '2. 广告素材 —— 如果未来版本包含广告，仅用于拉取与展示广告内容。',
  '两种情形都不会上传：你的书、阅读进度、设置、任何设备标识，一律不出设备。',
  '断网时会发生什么：字体下载与广告静默不可用，阅读功能 100% 完整，不弹窗、不报错、不留空白占位。',
  '你可以自己关掉联网：在系统「设置 → 应用 → Rock阅读 → 联网控制」中关闭本应用的联网权限，此后完全离线运行，功能不受任何影响。',
  '#四、我们申请了哪些权限',
  '仅 ohos.permission.INTERNET，用于上述「字体下载」与「广告素材」两种情形。',
  '我们没有申请、也不会申请：位置、通讯录、相机、麦克风、短信、通话记录、日历、健康数据、设备标识符等权限。',
  '关于你的文件：导入书籍通过系统文件选择器完成，是你主动挑选的那一个文件，应用只读取它并复制一份到沙箱。本应用不会扫描、读取或上传你设备上的其他任何文件。',
  '#五、第三方 SDK',
  '当前版本不含任何第三方 SDK。',
  '如未来版本加入广告，将使用华为系统级广告服务（非三方 SDK，不额外引入代码库、不影响安装包体积），届时会在本政策更新并说明。',
  '#六、数据出境',
  '不存在。你的数据不出设备，我们也没有任何服务器可接收。',
  '#七、未成年人',
  '本应用不提供个性化推荐，不基于用户画像推送内容。未成年人使用不产生额外数据收集。',
  '#八、你的权利',
  '· 查看与导出：数据就在设备上，应用内可直接查看；如需导出，可在卸载前通过系统文件管理访问应用目录。',
  '· 删除：应用内可删除单本书及其记录；卸载应用可删除全部数据。',
  '· 撤回联网：见第三节，系统层面关闭即可。',
  '#九、政策更新',
  '如本政策发生实质性变更，会在应用内及上架页面更新。若不同意，可停止使用并卸载（卸载会删除全部本地数据）。',
  '#十、联系我们',
  '如对本政策有疑问，或需要行使上述权利，可通过邮件联系：',
  'danglei328@163.com',
  '我们会在合理期限内答复。'
];

@Entry
@Component
struct Privacy {
  @State palette: Palette = paletteOf(THEME_DARK);
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
        .fontSize(13)
        .fontColor(this.palette.text)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .margin({ top: 18, bottom: 6 })
    } else {
      Text(text)
        .fontSize(11.5)
        .fontColor(this.palette.text2)
        .width('100%')
        .margin({ bottom: 8 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(20)
          .fontColor(this.palette.text)
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .responseRegion({ x: -5, y: -5, width: 44, height: 44 })
          .onClick(() => this.getUIContext().getRouter().back())
        Text('PRIVACY')
          .fontSize(12)
          .fontFamily('monospace')
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: 6 })
        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ left: 12, right: 18, top: 10, bottom: 12 })
      .border({ width: { bottom: 1 }, color: this.palette.lineSoft })

      Scroll() {
        Column() {
          ForEach(PRIVACY_LINES, (line: string) => {
            this.lineView(line)
          // key 用序号：正文里可能有重复段落，拿内容当 key 会冲突（ForEach 键必须唯一）
          }, (line: string, idx: number) => 'p' + idx)
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 14, bottom: 34 })
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
