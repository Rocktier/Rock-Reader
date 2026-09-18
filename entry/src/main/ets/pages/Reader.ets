/**
 * 阅读页
 * 设计依据：docs/v1-design.md §8 —— 零常驻控件（点屏幕中间才浮出细栏）、页脚等宽数码
 *
 * 本版为 M3 第一版：**滚动模式** + 章节切换 + 进度落库。
 * 分页（横滑翻页，默认模式）下一步做 —— PageTableBuilder 已就绪，只差接 graphics.text 的 LineMetrics。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { router } from '@kit.ArkUI';
import { BookDb } from '../data/BookDb';
import { BookRecord, ChapterRow, ReadingProgress } from '../common/Types';
import { readChapterTextByChars, clearTextCache } from '../engine/parser/TxtParser';

interface ReaderParams {
  bookId: string;
}

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 排版档位 3（默认）的数值，见 docs/v1-design.md §8 唯一真源表 */
const FONT_SIZE: number = 18;
const LINE_HEIGHT: number = 34;
const PAGE_MARGIN: number = 20;

@Entry
@Component
struct Reader {
  @State title: string = '';
  @State chapterTitle: string = '';
  @State text: string = '';
  @State chapterIndex: number = 0;
  @State chapterCount: number = 0;
  @State showMenu: boolean = false;
  @State hint: string = '';
  @State loading: boolean = true;

  private db: BookDb = new BookDb();
  private book: BookRecord | null = null;
  private chapters: ChapterRow[] = [];

  aboutToAppear(): void {
    this.init();
  }

  aboutToDisappear(): void {
    clearTextCache();
  }

  private async init(): Promise<void> {
    try {
      const params = router.getParams() as ReaderParams;
      await this.db.open(getContext(this) as Context);
      const book = await this.db.getBook(params.bookId);
      if (book === null) {
        this.hint = '找不到这本书';
        this.loading = false;
        return;
      }
      this.book = book;
      this.title = book.title;

      if (book.format !== 'txt') {
        // EPUB 解析在 M4；这里明确告知，不假装能读
        this.hint = 'EPUB 阅读将在下个版本支持';
        this.loading = false;
        return;
      }

      this.chapters = await this.db.listChapters(book.id);
      this.chapterCount = this.chapters.length;
      if (this.chapterCount === 0) {
        this.hint = '这本书没有解析出章节';
        this.loading = false;
        return;
      }
      const p: ReadingProgress | null = await this.db.getProgress(book.id);
      const idx: number = p === null ? 0 : Math.min(p.chapterIndex, this.chapterCount - 1);
      this.loadChapter(idx);
      this.loading = false;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'reader init failed: %{public}s', JSON.stringify(e));
      this.hint = '打开失败';
      this.loading = false;
    }
  }

  private loadChapter(idx: number): void {
    if (this.book === null || idx < 0 || idx >= this.chapters.length) {
      return;
    }
    this.chapterIndex = idx;
    const ch: ChapterRow = this.chapters[idx];
    this.chapterTitle = ch.title;
    try {
      this.text = readChapterTextByChars(this.book.path, ch.startChar, ch.endChar);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load chapter failed: %{public}s', JSON.stringify(e));
      this.text = '';
      this.hint = '这一章读取失败';
    }
    this.persistProgress();
  }

  /** 每章切换时落一次进度；再叠加「每 N 页落一次」在分页版里做 */
  private persistProgress(): void {
    if (this.book === null || this.chapterCount === 0) {
      return;
    }
    const p: ReadingProgress = {
      bookId: this.book.id,
      chapterIndex: this.chapterIndex,
      charOffset: 0,
      percent: (this.chapterIndex + 1) / this.chapterCount,
      updatedAt: Date.now()
    };
    this.db.saveProgress(p).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'save progress failed: %{public}s', e.message);
    });
    this.db.touchLastRead(this.book.id, p.updatedAt).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'touch lastRead failed: %{public}s', e.message);
    });
  }

  @Builder
  topBar() {
    Row() {
      Text('‹')
        .fontSize(17)
        .fontColor($r('app.color.rd_text2'))
        .onClick(() => router.back())
      Text(this.title)
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.rd_text'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 12 })
        .layoutWeight(1)
      Text(`${this.chapterIndex + 1}/${this.chapterCount}`)
        .fontSize(9.5)
        .fontFamily('monospace')
        .fontColor($r('app.color.rd_text3'))
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.rd_bg'))
    .border({ width: { bottom: 1 }, color: $r('app.color.rd_line_soft') })
  }

  @Builder
  bottomBar() {
    Column() {
      Row() {
        Text('上一章')
          .fontSize(12)
          .fontColor(this.chapterIndex > 0 ? $r('app.color.rd_text') : $r('app.color.rd_text3'))
          .onClick(() => this.loadChapter(this.chapterIndex - 1))
        Blank()
        Text(this.chapterTitle)
          .fontSize(10)
          .fontFamily('monospace')
          .fontColor($r('app.color.rd_text3'))
          .maxLines(1)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        Blank()
        Text('下一章')
          .fontSize(12)
          .fontColor(this.chapterIndex < this.chapterCount - 1 ? $r('app.color.rd_text') : $r('app.color.rd_text3'))
          .onClick(() => this.loadChapter(this.chapterIndex + 1))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 16, bottom: 26 })
    .backgroundColor($r('app.color.rd_bg'))
    .border({ width: { top: 1 }, color: $r('app.color.rd_line_soft') })
  }

  build() {
    Stack() {
      Scroll() {
        Column() {
          if (this.hint.length > 0) {
            Text(this.hint)
              .fontSize(13)
              .fontColor($r('app.color.rd_text2'))
              .margin({ top: 60 })
          } else {
            Text(this.text)
              .fontSize(FONT_SIZE)
              .lineHeight(LINE_HEIGHT)
              .fontColor($r('app.color.rd_text'))
              .width('100%')
              .textAlign(TextAlign.Start)
          }
        }
        .width('100%')
        .padding({
          left: PAGE_MARGIN,
          right: PAGE_MARGIN,
          top: 40,
          bottom: 40
        })
        .alignItems(HorizontalAlign.Start)
      }
      .scrollBar(BarState.Off)
      .width('100%')
      .height('100%')

      // 页脚：等宽数码（Nothing 式），常驻但极克制
      Column() {
        Row() {
          Text(this.chapterTitle)
            .fontSize(9.5)
            .fontFamily('monospace')
            .fontColor($r('app.color.rd_text3'))
            .maxLines(1)
            .layoutWeight(1)
          Text(this.chapterCount > 0 ? `${this.chapterIndex + 1}/${this.chapterCount}` : '')
            .fontSize(9.5)
            .fontFamily('monospace')
            .fontColor($r('app.color.rd_text3'))
        }
        .width('100%')
        .padding({ left: PAGE_MARGIN, right: PAGE_MARGIN, bottom: 14 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)

      if (this.showMenu) {
        Column() {
          this.topBar()
          Blank()
          this.bottomBar()
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.rd_bg'))
    .onClick(() => {
      this.showMenu = !this.showMenu;
    })
  }
}
