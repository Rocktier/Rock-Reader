/**
 * 服务卡片 UI（B1，2026-10-25 党哥批准）
 *
 * 两个规格共用一页，靠 binding data 的 dimension 分发布局：
 *  - 2×2：紧凑四行（标题 / 进度条 / 书名 / 作者），一眼定位「读到哪了」
 *  - 2×4：加一行章节与剩余时间（复用阅读页同款 chapterLeftText 文案）
 *
 * 交互：整卡可点 → postCardAction('router') 拉起 EntryAbility 带 bookId，
 * 由 EntryAbility → AppStorage 'pendingOpenBook' → 书架页 push Reader 定位
 * （与「用其他应用打开」同一条转发链路，见 EntryAbility.takeOpenBook）。
 *
 * 配色全部走 sys.color：卡片配置 colorMode=auto，深浅色由系统托管，零维护。
 */
@Entry
@Component
struct WidgetCard {
  @LocalStorageProp('hasBook') hasBook: boolean = false;
  @LocalStorageProp('bookId') bookId: string = '';
  @LocalStorageProp('bookTitle') bookTitle: string = '';
  @LocalStorageProp('author') author: string = '';
  @LocalStorageProp('chapter') chapter: string = '';
  @LocalStorageProp('percent') percent: number = 0;
  @LocalStorageProp('leftText') leftText: string = '';
  /** '2*2' | '2*4'；缺省按 2×2 */
  @LocalStorageProp('dimension') dimension: string = '2*2';

  private readonly appLabel: string = 'Rock阅读';

  build() {
    Column() {
      if (!this.hasBook) {
        this.emptyBody();
      } else if (this.dimension === '2*4') {
        this.wideBody();
      } else {
        this.smallBody();
      }
    }
    .padding(this.dimension === '2*4' ? 16 : 12)
    .width('100%')
    .height('100%')
    .backgroundColor($r('sys.color.comp_background_primary'))
    .borderRadius(20)
    // 整卡点击 = 「继续读」：router 动作带 bookId 拉起应用
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { bookId: this.bookId }
      });
    });
  }

  /** 顶部行：应用名 + 百分比（空态隐藏百分比） */
  @Builder
  headerRow() {
    Row() {
      Text(this.appLabel)
        .fontSize(this.dimension === '2*4' ? 11 : 10)
        .fontColor($r('sys.color.font_secondary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .layoutWeight(1);
      if (this.hasBook) {
        Text(`${this.percent}%`)
          .fontSize(this.dimension === '2*4' ? 11 : 10)
          .fontColor($r('sys.color.font_primary'))
          .fontWeight(FontWeight.Medium);
      }
    }
    .width('100%');
  }

  /** 进度条：track + 按百分比填充的 fill（数据层保证 0~100） */
  @Builder
  progressBar(barVp: number) {
    Stack() {
      Column()
        .width('100%')
        .height(barVp)
        .borderRadius(barVp / 2)
        .backgroundColor($r('sys.color.comp_divider'));
      Column()
        .width(`${this.percent}%`)
        .height(barVp)
        .borderRadius(barVp / 2)
        .backgroundColor($r('sys.color.ohos_id_color_primary'));
    }
    .width('100%')
    .height(barVp);
  }

  /** 2×2：紧凑四行 */
  @Builder
  smallBody() {
    Column() {
      this.headerRow();
      this.progressBar(4);
      Text(this.bookTitle)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      Text(this.author)
        .fontSize(10)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween);
  }

  /** 2×4：书名加大 + 章节 + 本章剩余时间 */
  @Builder
  wideBody() {
    Column() {
      this.headerRow();
      this.progressBar(5);
      Text(this.bookTitle)
        .fontSize(16)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      Text(`${this.author} · ${this.chapter}`)
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%');
      Text(this.leftText.length > 0 ? this.leftText : '点卡片继续读')
        .fontSize(10)
        .fontColor($r('sys.color.font_tertiary'))
        .maxLines(1)
        .width('100%');
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.SpaceBetween);
  }

  /** 空态：没读过任何书（或库被清空）——卡片仍可点，点了打开书架 */
  @Builder
  emptyBody() {
    Column() {
      Text(this.appLabel)
        .fontSize(13)
        .fontColor($r('sys.color.font_primary'))
        .fontWeight(FontWeight.Medium);
      Text('还没有在读的书')
        .fontSize(11)
        .fontColor($r('sys.color.font_secondary'))
        .margin({ top: 4 });
      Text('导入一本，桌面就能续读')
        .fontSize(10)
        .fontColor($r('sys.color.font_tertiary'))
        .margin({ top: 2 });
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center);
  }
}
