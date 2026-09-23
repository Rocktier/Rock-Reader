/**
 * 关于页（2026-09-23 新增）
 *
 * 为什么要有这一页：
 *  ① **上架硬性要求**：应用内必须能查看隐私政策（华为审核会查），此前只有私有仓里的草稿；
 *  ② 品牌承诺需要一个"完整版"的家 —— 设置页底部只有一行空间，放不下。
 *
 * slogan（党哥 2026-09-23 定「主句 + 副句」）：
 *   主句 书在你手上，哪儿也不去   ← 讲"本地、不上传"
 *   副句 断网也能读完整本书       ← 讲"断网完整"
 *   两句合起来才是完整承诺，所以**永远一起出现**。
 *
 * 分工：设置页底部只放 slogan；本页放 slogan + 承诺细节 + 隐私政策入口。
 * 同一句话不放两处，避免以后改一半。
 */
import { router } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { Palette, paletteOf, THEME_DARK } from '../common/Theme';
import { ReaderPrefs } from '../data/ReaderPrefs';

/** slogan 主句：品牌承诺的第一句，改这里等于改全部三处（书架空态 / 设置页底 / 本页） */
const SLOGAN_MAIN: string = '书在你手上，哪儿也不去';
/** slogan 副句：把"断网完整"讲明白 */
const SLOGAN_SUB: string = '断网也能读完整本书';

@Entry
@Component
struct About {
  @State palette: Palette = paletteOf(THEME_DARK);
  /** 取不到版本就不显示（不编造一个假版本号） */
  @State versionText: string = '';
  private prefs: ReaderPrefs = new ReaderPrefs();

  aboutToAppear(): void {
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.palette = paletteOf(this.prefs.getTheme());
    this.loadVersion();
  }

  onPageShow(): void {
    // 主题可能在别处改过 → 回来时重读，与设置页同一套逻辑
    this.prefs.reload();
    this.palette = paletteOf(this.prefs.getTheme());
  }

  private loadVersion(): void {
    try {
      const info: bundleManager.BundleInfo =
        bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      this.versionText = '版本 ' + info.versionName;
    } catch (e) {
      this.versionText = '';
    }
  }

  @Builder
  /** 一行条目：左侧文字 + 右侧 ›，整行可点（热区按 44 撑开） */
  entryRow(label: string, note: string, onClick: () => void) {
    Row() {
      Column({ space: 4 }) {
        Text(label)
          .fontSize(13)
          .fontColor(this.palette.text)
        if (note.length > 0) {
          Text(note)
            .fontSize(10)
            .fontColor(this.palette.text3)
        }
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text('›')
        .fontSize(16)
        .fontColor(this.palette.text3)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .border({ width: { bottom: 1 }, color: this.palette.lineSoft })
    .onClick(() => onClick())
    .responseRegion({ x: 0, y: -4, width: '100%', height: 52 })
  }

  build() {
    Column() {
      // 顶栏：与设置页同规格（返回键热区 44，标题等宽）
      Row() {
        Text('‹')
          .fontSize(20)
          .fontColor(this.palette.text)
          .width(34)
          .height(34)
          .textAlign(TextAlign.Center)
          .responseRegion({ x: -5, y: -5, width: 44, height: 44 })
          .onClick(() => this.getUIContext().getRouter().back())
        Text('ABOUT')
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
          // 品牌区
          Text('Rock阅读')
            .fontSize(18)
            .fontColor(this.palette.text)
          Text('RockReader')
            .fontSize(11)
            .fontFamily('monospace')
            .fontColor(this.palette.text3)
            .margin({ top: 4 })
          if (this.versionText.length > 0) {
            Text(this.versionText)
              .fontSize(10)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .margin({ top: 8 })
          }

          // slogan：主句 + 副句，永远成对
          Column({ space: 8 }) {
            Text(SLOGAN_MAIN)
              .fontSize(15)
              .fontColor(this.palette.text)
            Text(SLOGAN_SUB)
              .fontSize(11)
              .fontColor(this.palette.text2)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 28 })

          // 承诺细节：从设置页底部迁来（那边只留 slogan）
          Column({ space: 6 }) {
            Text('核心数据不联网')
              .fontSize(12)
              .fontColor(this.palette.text2)
            Text('书籍与进度全部在本机处理；卸载即删除。')
              .fontSize(11)
              .fontColor(this.palette.text3)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: 20 })

          Column() {
            this.entryRow('隐私政策', '不收集个人信息 · 数据只在本地', () => {
              router.pushUrl({ url: 'pages/Privacy' });
            })
          }
          .width('100%')
          .margin({ top: 28 })
        }
        .width('100%')
        .padding({ left: 22, right: 22, top: 26, bottom: 30 })
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
