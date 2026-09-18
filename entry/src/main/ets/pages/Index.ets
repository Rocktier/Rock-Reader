import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/**
 * 书架页（M1 骨架版）
 * 设计依据：docs/v1-design.md §8 —— 黑底白字、等宽数码、书封 0 圆角、卡片 12 圆角
 * 空态不放营销文案（家族规则）
 */
@Entry
@Component
struct Index {
  @State bookCount: number = 0;

  build() {
    Column() {
      // 顶部：标题 + 本数 + 导入
      Row() {
        Text($r('app.string.shelf_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.rd_text'))

        Text(this.bookCount.toString() + ' 本')
          .fontSize(11)
          .fontColor($r('app.color.rd_text3'))
          .fontFamily('monospace')
          .margin({ left: 10 })

        Blank()

        Text('＋')
          .fontSize(16)
          .fontColor($r('app.color.rd_text'))
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderWidth(1)
          .borderColor($r('app.color.rd_line'))
          .onClick(() => {
            // M2 接入 filePicker 导入本地书
            hilog.info(DOMAIN, TAG, 'import tapped');
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 18 })

      // 空态
      Column() {
        Text($r('app.string.shelf_empty_hint'))
          .fontSize(13)
          .fontColor($r('app.color.rd_text3'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)

      // 页脚：等宽数码（Nothing 式）
      Row() {
        Text('LOCAL ONLY')
          .fontSize(9)
          .fontColor($r('app.color.rd_text3'))
          .fontFamily('monospace')
        Blank()
        Text('v1.0.0')
          .fontSize(9)
          .fontColor($r('app.color.rd_text3'))
          .fontFamily('monospace')
      }
      .width('100%')
      .padding({ bottom: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rd_bg'))
    .padding({ left: 22, right: 22 })
  }
}
