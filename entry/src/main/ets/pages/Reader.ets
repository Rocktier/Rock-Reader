import { router } from '@kit.ArkUI';

/**
 * 阅读页（M1 占位，M3 实现分页渲染）
 */
@Entry
@Component
struct Reader {
  build() {
    Column() {
      Text($r('app.string.reader_placeholder'))
        .fontSize(18)
        .fontColor($r('app.color.rd_text'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.rd_bg'))
  }
}
