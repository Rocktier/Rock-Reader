/**
 * 设置页
 * 设计依据：docs/v1-design.md §8 ——
 *  ① **一律不用滑块**：字号/行距/边距全是档位芯片（家族铁律）；
 *  ② 芯片 0 圆角（Nothing 工业感），卡片 12；
 *  ③ 文案只讲品牌承诺「核心数据不联网」，不提广告、不提联网开关（spec §8.5）。
 *
 * 数值唯一真源在 common/LayoutStyle.ets，本页**只写档位序号**。
 * 从阅读页进来：返回时阅读页会按字符偏移复原位置（切档位不跳页）。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { clampLevel, LayoutLevels, LEVEL_MAX, LEVEL_MIN } from '../common/LayoutStyle';
import { Palette, paletteOf, THEME_DARK, THEME_LIGHT, ThemeName } from '../common/Theme';
import { applyThemeToSystem } from '../common/SystemBar';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const CHIP_SIZE: number = 44;
const CHIP_HEIGHT: number = 34;
/** 系统字体列表最多显示多少项（有些设备会返回几十项，取够用的量） */
const MAX_FONT_ITEMS: number = 40;

@Entry
@Component
struct Settings {
  @State palette: Palette = paletteOf(THEME_DARK);
  @State levels: LayoutLevels = { fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3 };
  @State theme: ThemeName = THEME_DARK;
  /** '' = 系统默认 */
  @State fontFamily: string = '';
  @State fontFamilies: string[] = [];

  private prefs: ReaderPrefs = new ReaderPrefs();

  aboutToAppear(): void {
    this.prefs.open(getContext(this) as Context);
    this.levels = this.prefs.getLevels();
    this.theme = this.prefs.getTheme();
    this.fontFamily = this.prefs.getFontFamily();
    this.palette = paletteOf(this.theme);
    this.loadSystemFonts();
  }

  onPageShow(): void {
    this.loadSystemFonts();
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
        const name: string = list[i];
        if (name.length > 0 && name !== this.fontFamily) {
          picked.push(name);
        }
      }
      this.fontFamilies = picked;
    } catch (e) {
      // 取不到就只显示「系统默认」—— 字体选择不是读书的必要条件，绝不因此报错
      hilog.warn(DOMAIN, TAG, 'getSystemFontList failed: %{public}s', JSON.stringify(e));
      this.fontFamilies = [];
    }
  }

  private pickFont(family: string): void {
    this.fontFamily = family;
    this.prefs.saveFontFamily(family);
  }

  /** row: 'font' | 'line' | 'margin'；n: 档位序号 */
  private pick(row: string, n: number): void {
    const level: number = clampLevel(n);
    const next: LayoutLevels = {
      fontSizeLevel: row === 'font' ? level : this.levels.fontSizeLevel,
      lineHeightLevel: row === 'line' ? level : this.levels.lineHeightLevel,
      marginLevel: row === 'margin' ? level : this.levels.marginLevel
    };
    this.levels = next;
    this.prefs.saveLevels(next);
  }

  private pickTheme(theme: ThemeName): void {
    this.theme = theme;
    this.palette = paletteOf(theme);
    this.prefs.saveTheme(theme);
    // 同步系统层：浅色主题下必须把状态栏文字改成黑色，否则白底白字
    applyThemeToSystem(getContext(this) as Context, theme);
    this.loadSystemFonts();
  }

  private currentOf(row: string): number {
    if (row === 'font') {
      return this.levels.fontSizeLevel;
    }
    return row === 'line' ? this.levels.lineHeightLevel : this.levels.marginLevel;
  }

  @Builder
  levelRow(label: string, row: string, hint: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(13.5)
          .fontColor(this.palette.text)
        Blank()
        Text(hint)
          .fontSize(9.5)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: 10 })

      Row({ space: 8 }) {
        ForEach([1, 2, 3, 4, 5], (n: number) => {
          Text(`${n}`)
            .fontSize(13)
            .fontFamily('monospace')
            .fontColor(this.currentOf(row) === n ? this.palette.bg : this.palette.text2)
            .backgroundColor(this.currentOf(row) === n ? this.palette.text : this.palette.card)
            .border({ width: 1, color: this.currentOf(row) === n ? this.palette.text : this.palette.line })
            .borderRadius(0)
            .width(CHIP_SIZE)
            .height(CHIP_HEIGHT)
            .textAlign(TextAlign.Center)
            .onClick(() => this.pick(row, n))
        }, (n: number) => row + n)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 16, bottom: 16 })
  }

  @Builder
  fontChip(label: string, family: string) {
    Text(label)
      .fontFamily(family)                  // 用该字体本身渲染，直接看效果
      .fontSize(13)
      .fontColor(this.fontFamily === family ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.fontFamily === family ? this.palette.text : this.palette.card)
      .border({ width: 1, color: this.fontFamily === family ? this.palette.text : this.palette.line })
      .borderRadius(0)
      .height(CHIP_HEIGHT)
      .padding({ left: 14, right: 14 })
      .onClick(() => this.pickFont(family))
  }

  /** 字体：横向芯片列表（系统已装字体，**不内置字体文件 → 体积 0**） */
  @Builder
  fontSection() {
    Column() {
      Row() {
        Text('字体')
          .fontSize(13.5)
          .fontColor(this.palette.text)
        Blank()
        Text(this.fontFamily.length > 0 ? `${this.fontFamilies.length} 款可选` : '系统默认')
          .fontSize(9.5)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .margin({ bottom: 9 })

      // 预览：直接看这套字体在正文里的样子
      Text('思维力是孩子学习力的基础 ABC 123')
        .fontFamily(this.fontFamily)
        .fontSize(15)
        .fontColor(this.palette.text2)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ bottom: 12 })

      Scroll() {
        Row({ space: 8 }) {
          this.fontChip('系统默认', '')
          ForEach(this.fontFamilies, (family: string) => {
            this.fontChip(family, family)
          }, (family: string) => 'fam' + family)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 16, bottom: 16 })
  }

  @Builder
  themeChip(label: string, value: ThemeName) {
    Text(label)
      .fontSize(12.5)
      .fontColor(this.theme === value ? this.palette.bg : this.palette.text2)
      .backgroundColor(this.theme === value ? this.palette.text : this.palette.card)
      .border({ width: 1, color: this.theme === value ? this.palette.text : this.palette.line })
      .borderRadius(0)
      .height(CHIP_HEIGHT)
      .padding({ left: 18, right: 18 })
      .onClick(() => this.pickTheme(value))
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
          .onClick(() => router.back())
        Text('SETTINGS')
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

      Column() {
        Text('排版')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .width('100%')
          .margin({ bottom: 4 })

        this.levelRow('字号', 'font', `${this.levels.fontSizeLevel}/${LEVEL_MAX}`)
        this.levelRow('行距', 'line', `${this.levels.lineHeightLevel}/${LEVEL_MAX}`)
        this.levelRow('页边距', 'margin', `${this.levels.marginLevel}/${LEVEL_MAX}`)

        this.fontSection()

        Divider()
          .color(this.palette.lineSoft)
          .margin({ top: 8, bottom: 8 })

        Text('主题')
          .fontSize(11)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
          .width('100%')
          .margin({ bottom: 12 })

        Row({ space: 10 }) {
          this.themeChip('深色', THEME_DARK)
          this.themeChip('浅色', THEME_LIGHT)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 22, right: 22, top: 18 })
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text('核心数据不联网')
          .fontSize(12)
          .fontColor(this.palette.text2)
        Text('书籍与进度全部在本机处理')
          .fontSize(10)
          .fontColor(this.palette.text3)
          .margin({ top: 6 })
      }
      .width('100%')
      .padding({ left: 22, right: 22, bottom: 26 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
  }
}
