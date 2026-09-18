/**
 * 书架页
 * 设计依据：docs/v1-design.md §8 —— 黑底白字、等宽数码、书封 0 圆角、卡片 12 圆角、空态不放营销文案
 * 主题：色板来自 common/Theme.ets（运行时切换，与系统深浅色解耦）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router, promptAction } from '@kit.ArkUI';
import { BookDb } from '../data/BookDb';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { BookImporter, ImportResult } from '../engine/importer/BookImporter';
import { BookRecord, ReadingProgress } from '../common/Types';
import { Palette, paletteOf, THEME_DARK, ThemeName } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';

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

@Entry
@Component
struct Index {
  @State books: BookRecord[] = [];
  @State resume: BookRecord | null = null;
  @State resumePercent: number = 0;
  @State busy: boolean = false;
  @State palette: Palette = paletteOf(THEME_DARK);

  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();
  private theme: ThemeName = THEME_DARK;

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
      } else {
        this.resume = null;
        this.resumePercent = 0;
      }
    } catch (e) {
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
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'import failed: %{public}s', JSON.stringify(e));
      promptAction.showToast({ message: '导入失败' });
    } finally {
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
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'delete failed: %{public}s', JSON.stringify(e));
    }
  }

  private openBook(book: BookRecord): void {
    router.pushUrl({ url: 'pages/Reader', params: { bookId: book.id } });
  }

  @Builder
  bookCover(book: BookRecord, size: number) {
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

  @Builder
  resumeCard(book: BookRecord) {
    Row({ space: 14 }) {
      this.bookCover(book, 58)
      Column({ space: 6 }) {
        Text(book.title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(book.format.toUpperCase())
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
        Row({ space: 2 }) {
          ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], (i: number) => {
            Row()
              .layoutWeight(1)
              .height(2)
              .backgroundColor(this.resumePercent * 10 > i ? this.palette.text : this.palette.line)
          }, (i: number) => 'rp' + i)
        }
        .width('100%')
        .margin({ top: 6 })
        Text(`${Math.round(this.resumePercent * 100)}%`)
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
    .onClick(() => this.openBook(book))
  }

  build() {
    Column() {
      // 顶部
      Row() {
        Text($r('app.string.shelf_title'))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
        Text(`${this.books.length} 本`)
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .margin({ left: 10 })
        Blank()
        Text('Aa')
          .fontSize(13)
          .fontColor(this.palette.text)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderWidth(1)
          .borderColor(this.palette.line)
          .margin({ left: 8 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/Settings' });
          })
        Text(this.busy ? '···' : '＋')
          .fontSize(15)
          .fontColor(this.palette.text)
          .width(30)
          .height(30)
          .textAlign(TextAlign.Center)
          .borderWidth(1)
          .borderColor(this.palette.line)
          .margin({ left: 8 })
          .onClick(() => {
            this.onImport();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 18 })

      // 继续阅读
      if (this.resume !== null) {
        this.resumeCard(this.resume)
      }

      // 书架网格
      if (this.books.length === 0) {
        Column() {
          Text($r('app.string.shelf_empty_hint'))
            .fontSize(13)
            .fontColor(this.palette.text3)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Grid() {
            ForEach(this.books, (item: BookRecord) => {
              GridItem() {
                Column({ space: 7 }) {
                  this.bookCover(item, 88)
                  Text(item.title)
                    .fontSize(11.5)
                    .fontColor(this.palette.text)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(item.format.toUpperCase())
                    .fontSize(9)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                }
                .width('100%')
                .onClick(() => this.openBook(item))
                .gesture(LongPressGesture().onAction(() => this.confirmDelete(item)))
              }
            }, (item: BookRecord) => item.id)
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
        Blank()
        Text('v1.0.0')
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
  }
}
