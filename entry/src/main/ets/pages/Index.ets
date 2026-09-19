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
import { BookImporter, ImportResult } from '../engine/importer/BookImporter';
import {
  collectGroups,
  filterByStatus,
  GROUP_ALL,
  GROUP_UNFILED,
  filledCells,
  normalizeGroupName,
  percentText,
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

/** 编辑器/菜单的显示模式 */
const MODE_NONE: string = 'none';
const MODE_MENU: string = 'menu';
const MODE_RENAME: string = 'rename';
const MODE_GROUP: string = 'group';

/** 进度条格数（与「继续阅读」卡片一致） */
const CELLS: number = 10;

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
  @State items: ShelfItem[] = [];
  @State groups: string[] = [];
  @State activeGroup: string = GROUP_ALL;
  /** 阅读状态筛选（未读 / 在读 / 已读），与分组是两个独立维度 */
  @State statusFilter: string = STATUS_ALL;
  @State resume: ShelfItem | null = null;
  @State busy: boolean = false;
  @State palette: Palette = paletteOf(THEME_DARK);

  /** 长按后弹出的菜单/输入框 */
  @State editorMode: string = MODE_NONE;
  @State editorBookId: string = '';
  @State editorText: string = '';

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
      const list: BookRecord[] = await this.db.listBooks();
      const percents: Map<string, number> = await this.db.listAllProgress();
      const built: ShelfItem[] = [];
      for (let i = 0; i < list.length; i++) {
        const raw: number | undefined = percents.get(list[i].id);
        const one: ShelfItem = { book: list[i], percent: raw === undefined ? 0 : raw };
        built.push(one);
      }
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

  private openEditor(mode: string, item: ShelfItem): void {
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
      promptAction.showToast({ message: '操作失败' });
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
  resumeCard(item: ShelfItem) {
    Row({ space: 14 }) {
      this.bookCover(item.book, 58)
      Column({ space: 6 }) {
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
  groupChip(name: string, active: boolean) {
    Text(name)
      .fontSize(11)
      .fontFamily('monospace')
      .fontColor(active ? this.palette.bg : this.palette.text3)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(10)
      .backgroundColor(active ? this.palette.text : 'rgba(0,0,0,0)')
      .borderWidth(1)
      .borderColor(active ? this.palette.text : this.palette.line)
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
          this.menuButton('移除', '')
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
      .backgroundColor(this.palette.card)
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
      .fontColor(nextMode === '' ? '#FF4A3D' : this.palette.text)
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({ top: 10, bottom: 10 })
      .onClick(() => {
        if (nextMode === '') {
          this.closeEditor();
          this.confirmDelete(this.bookOf(this.editorBookId));
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
            .margin({ left: 8 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/Stats' });
            })
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
        .padding({ top: 10, bottom: 14 })

        // 分组筛选（只有存在两个及以上分组时才出现，避免只有「未分组」时白占一行）
        if (this.groups.length > 1) {
          Scroll() {
            Row({ space: 8 }) {
              this.groupChip('全部', this.activeGroup === GROUP_ALL)
              ForEach(this.groups, (g: string) => {
                this.groupChip(g, this.activeGroup === g)
              }, (g: string) => 'chip' + g)
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

        // 继续阅读
        if (this.resume !== null && this.activeGroup === GROUP_ALL) {
          this.resumeCard(this.resume)
          Row()
            .height(14)
        }

        // 书架网格
        if (this.items.length === 0) {
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

      if (this.editorMode !== MODE_NONE) {
        this.editorPanel()
      }
    }
    .width('100%')
    .height('100%')
  }
}
