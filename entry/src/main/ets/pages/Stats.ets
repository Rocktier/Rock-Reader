/**
 * 阅读统计页
 * 设计依据：docs/v1-design.md §8 —— 黑底白字、等宽数码、卡片 16vp 圆角（官方大圆角）、不放营销文案
 *
 * 数据全部来自本机 relationalStore（零联网）。计算逻辑在 engine/stats/ReadStats.ets（纯逻辑、可单测）。
 * 只取近 30 天的会话：统计不需要全量历史，也避免表越长越慢。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookDb } from '../data/BookDb';
import { ReaderPrefs, DAILY_GOAL_DEFAULT } from '../data/ReaderPrefs';
import { BookRecord } from '../common/Types';
import { byBook, BookTotal, dailyMs, durationText, msOfDay, ReadSession, streakDays, totalMs } from '../engine/stats/ReadStats';
import { Palette, paletteOf, THEME_DARK, ThemeName } from '../common/Theme';
import { formPadOf } from '../common/LayoutStyle';
import { RR_FS_DISPLAY, RR_FS_TITLE, RR_FS_LABEL, RR_FS_META, RR_FS_DIGIT, RR_FS_MICRO, RR_SP_SM, RR_SP_MD, RR_SP_XL, RR_SP_2XL, RR_SP_3XL, RR_SP_4XL, RR_RADIUS_CARD } from '../theme/RrTokens';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 统计窗口：近 30 天 */
const WINDOW_DAYS: number = 30;
/** 柱状图展示近 7 天 */
const CHART_DAYS: number = 7;
const BAR_MAX_VP: number = 72;
/** 每本书最多列几行 */
const TOP_BOOKS: number = 5;

interface BookStatRow {
  title: string;
  ms: number;
}

@Entry
@Component
struct Stats {
  @State palette: Palette = paletteOf(THEME_DARK);
  @State loading: boolean = true;
  @State totalText: string = '—';
  @State todayText: string = '—';
  @State streak: number = 0;
  @State week: number[] = [];
  @State weekMax: number = 0;
  @State rows: BookStatRow[] = [];
  @State sessionCount: number = 0;
  /** A4：每日目标（分钟；0 = 关）。党哥 2026-10-25 定默认 20 分钟 */
  @State private goalMin: number = DAILY_GOAL_DEFAULT;
  @State private goalText: string = '';
  @State private goalRatio: number = 0;
  /** 今日已读毫秒（load 时算一次；切换目标档位时复用，不重查 DB） */
  private todayMs: number = 0;
  /**
   * 版心单侧补丁（vp）：P0-5 大屏适配。数字卡与柱状图在宽屏上拉满
   * 会摊成扁带 —— 封顶 560vp 居中（formPadOf，CI 有单测）。
   * 0 = 手机竖屏 / 未测量，行为与旧版一致。
   */
  @State private padX: number = 0;

  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();

  aboutToAppear(): void {
    this.prefs.open(this.getUIContext().getHostContext() as Context);
    this.palette = paletteOf(this.prefs.getTheme());
    this.load();
  }

  private async load(): Promise<void> {
    try {
      await this.db.open(this.getUIContext().getHostContext() as Context);
      const now: number = Date.now();
      // 顺手清掉 180 天前的会话：统计窗口只有 30 天，保留更久没有意义还拖慢查询
      await this.db.pruneSessions(now - 180 * 24 * 60 * 60 * 1000);
      const since: number = now - WINDOW_DAYS * 24 * 60 * 60 * 1000;
      const sessions: ReadSession[] = await this.db.listSessions(since);

      this.totalText = durationText(totalMs(sessions));
      this.todayMs = msOfDay(sessions, now);
      this.todayText = durationText(this.todayMs);
      this.streak = streakDays(sessions, now);
      this.sessionCount = sessions.length;

      const week: number[] = dailyMs(sessions, now, CHART_DAYS);
      this.week = week;
      let max: number = 0;
      for (let i = 0; i < week.length; i++) {
        if (week[i] > max) {
          max = week[i];
        }
      }
      this.weekMax = max;

      // 书名映射（统计只存 bookId，标题从 books 表取）
      const books: BookRecord[] = await this.db.listBooks();
      const ids: string[] = [];
      const titles: string[] = [];
      for (let i = 0; i < books.length; i++) {
        ids.push(books[i].id);
        titles.push(books[i].title);
      }
      const perBook: BookTotal[] = byBook(sessions);
      const rows: BookStatRow[] = [];
      for (let i = 0; i < perBook.length && rows.length < TOP_BOOKS; i++) {
        if (perBook[i].ms <= 0) {
          continue;
        }
        const at: number = ids.indexOf(perBook[i].bookId);
        const row: BookStatRow = {
          title: at < 0 ? '（已从书架移除）' : titles[at],
          ms: perBook[i].ms
        };
        rows.push(row);
      }
      this.rows = rows;
      this.refreshGoal();
      this.loading = false;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load stats failed: %{public}s', JSON.stringify(e));
      this.loading = false;
    }
  }

  /**
   * A4：按当前目标与今日已读算文案/进度条。
   * 点目标循环切换档位时调用（不重查 DB —— 今天已读时长在 load 时算过）。
   */
  private refreshGoal(): void {
    this.goalMin = this.prefs.getDailyGoalMin();
    const target: number = this.goalMin * 60 * 1000;
    if (this.goalMin <= 0) {
      this.goalText = '未开启 · 点此设置';
      this.goalRatio = 0;
      return;
    }
    this.goalRatio = Math.max(0, Math.min(1, this.todayMs / target));
    if (this.todayMs >= target) {
      this.goalText = '已达成';
    } else {
      const left: number = Math.max(1, Math.ceil((target - this.todayMs) / 60000));
      this.goalText = `还差 ${left} 分钟`;
    }
  }

  @Builder
  metricCard(label: string, value: string, hint: string) {
    Column() {
      Text(label)
        .fontSize(RR_FS_DIGIT)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
      Text(value)
        .fontSize(RR_FS_DISPLAY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: RR_SP_MD })
      Text(hint)
        .fontSize(RR_FS_MICRO)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .margin({ top: RR_SP_SM })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .borderRadius(RR_RADIUS_CARD)
    .backgroundColor(this.palette.card)
    .borderWidth(1)
    .borderColor(this.palette.line)
  }

  build() {
    Column() {
      // 顶部
      Row() {
        Text('‹')
          .fontSize(RR_FS_TITLE)
          .fontColor(this.palette.text)
          .width(30)
          .height(30)
          .responseRegion({ x: -8, y: -8, width: 46, height: 46 })
          .textAlign(TextAlign.Center)
          .borderWidth(1)
          .borderColor(this.palette.line)
          .accessibilityText('返回')
          .onClick(() => {
            this.getUIContext().getRouter().back();
          })
        Text('阅读统计')
          .fontSize(RR_FS_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: RR_SP_2XL })
        Blank()
        Text(`${WINDOW_DAYS} 天`)
          .fontSize(RR_FS_MICRO)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: RR_SP_XL, bottom: RR_SP_3XL })

      if (this.loading) {
        Column() {
          Text('···')
            .fontSize(RR_FS_LABEL)
            .fontColor(this.palette.text3)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            // 三个数字
            Row({ space: 10 }) {
              this.metricCard('累计', this.totalText, '近 30 天')
              this.metricCard('今日', this.todayText, '0 点起算')
            }
            .width('100%')

            Row({ space: 10 }) {
              this.metricCard('连续', this.streak + ' 天', '含今天')
              this.metricCard('会话', this.sessionCount + ' 次', '3 秒以上')
            }
            .width('100%')
            .margin({ top: RR_SP_XL })

            // A4：今日目标（党哥 2026-10-25 拍板；点击循环切档位：关→10→20→30→60→关，
            // 与朗读定时同交互，不引弹窗）。达标文案 + 细进度条。
            Column() {
              Row() {
                Text('今日目标')
                  .fontSize(RR_FS_DIGIT)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text3)
                Blank()
                Text(this.goalText)
                  .fontSize(RR_FS_DIGIT)
                  .fontFamily('monospace')
                  .fontColor(this.goalMin > 0 && this.goalRatio >= 1 ? this.palette.accent : this.palette.text)
                  .accessibilityText('今日目标，点击调整档位')
                  .responseRegion({ x: 0, y: -8, width: 140, height: 44 })
                  .onClick(() => {
                    this.prefs.nextDailyGoal();
                    this.refreshGoal();
                  })
              }
              .width('100%')

              if (this.goalMin > 0) {
                Row({ space: 0 }) {
                  Row()
                    .layoutWeight(Math.max(0.001, this.goalRatio))
                    .height(6)
                    .backgroundColor(this.palette.text)
                  Row()
                    .layoutWeight(Math.max(0.001, 1 - this.goalRatio))
                    .height(6)
                    .backgroundColor(this.palette.line)
                }
                .width('100%')
                .borderRadius(3)
                .margin({ top: RR_SP_MD })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(14)
            .borderRadius(RR_RADIUS_CARD)
            .backgroundColor(this.palette.card)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .margin({ top: RR_SP_XL })

            // 近 7 天柱状
            Column() {
              Text(`近 ${CHART_DAYS} 天`)
                .fontSize(RR_FS_DIGIT)
                .fontFamily('monospace')
                .fontColor(this.palette.text3)
                .alignSelf(ItemAlign.Start)

              Row() {
                ForEach(this.week, (ms: number, i: number) => {
                  Column() {
                    Blank()
                    Column()
                      .width(14)
                      .height(this.weekMax <= 0 ? 2 : Math.max(2, Math.round(ms / this.weekMax * BAR_MAX_VP)))
                      .backgroundColor(ms > 0 ? this.palette.text : this.palette.line)
                  }
                  .layoutWeight(1)
                  .height(BAR_MAX_VP)
                  .justifyContent(FlexAlign.End)
                }, (ms: number, i: number) => 'bar' + i)
              }
              .width('100%')
              .height(BAR_MAX_VP)
              .alignItems(VerticalAlign.Bottom)
              .margin({ top: RR_SP_XL })

              Row() {
                ForEach(this.week, (ms: number, i: number) => {
                  Text(i === this.week.length - 1 ? '今天' : `${this.week.length - 1 - i}天前`)
                    .fontSize(RR_FS_MICRO)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                }, (ms: number, i: number) => 'lb' + i)
              }
              .width('100%')
              .margin({ top: RR_SP_MD })
            }
            .width('100%')
            .padding(14)
            .borderRadius(RR_RADIUS_CARD)
            .backgroundColor(this.palette.card)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .margin({ top: RR_SP_XL })

            // 每本书
            if (this.rows.length > 0) {
              Column() {
                Text('读得最多的书')
                  .fontSize(RR_FS_DIGIT)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text3)
                  .alignSelf(ItemAlign.Start)

                ForEach(this.rows, (row: BookStatRow) => {
                  Row() {
                    Text(row.title)
                      .fontSize(RR_FS_LABEL)
                      .fontColor(this.palette.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(durationText(row.ms))
                      .fontSize(RR_FS_META)
                      .fontFamily('monospace')
                      .fontColor(this.palette.text3)
                  }
                  .width('100%')
                  .padding({ top: RR_SP_XL })
                }, (row: BookStatRow) => row.title + row.ms)
              }
              .width('100%')
              .padding(14)
              .borderRadius(RR_RADIUS_CARD)
              .backgroundColor(this.palette.card)
              .borderWidth(1)
              .borderColor(this.palette.line)
              .margin({ top: RR_SP_XL })
            }

            Text('全部数据都在你的设备上，不上传、不联网')
              .fontSize(RR_FS_MICRO)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .margin({ top: RR_SP_3XL, bottom: RR_SP_4XL })
          }
          .width('100%')
        }
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .padding({ left: RR_SP_4XL + this.padX, right: RR_SP_4XL + this.padX })
    // 视口宽（vp）→ 版心补丁；旋转 / 分屏自动重算
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.padX = formPadOf(newValue.width as number);
    })
  }
}
