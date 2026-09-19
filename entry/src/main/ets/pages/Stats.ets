/**
 * 阅读统计页
 * 设计依据：docs/v1-design.md §8 —— 黑底白字、等宽数码、卡片 12 圆角、不放营销文案
 *
 * 数据全部来自本机 relationalStore（零联网）。计算逻辑在 engine/stats/ReadStats.ets（纯逻辑、可单测）。
 * 只取近 30 天的会话：统计不需要全量历史，也避免表越长越慢。
 */
import { router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookDb } from '../data/BookDb';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { BookRecord } from '../common/Types';
import { byBook, BookTotal, dailyMs, durationText, msOfDay, ReadSession, streakDays, totalMs } from '../engine/stats/ReadStats';
import { Palette, paletteOf, THEME_DARK, ThemeName } from '../common/Theme';

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

  private db: BookDb = new BookDb();
  private prefs: ReaderPrefs = new ReaderPrefs();

  aboutToAppear(): void {
    this.prefs.open(getContext(this) as Context);
    this.palette = paletteOf(this.prefs.getTheme());
    this.load();
  }

  private async load(): Promise<void> {
    try {
      await this.db.open(getContext(this) as Context);
      const now: number = Date.now();
      // 顺手清掉 180 天前的会话：统计窗口只有 30 天，保留更久没有意义还拖慢查询
      await this.db.pruneSessions(now - 180 * 24 * 60 * 60 * 1000);
      const since: number = now - WINDOW_DAYS * 24 * 60 * 60 * 1000;
      const sessions: ReadSession[] = await this.db.listSessions(since);

      this.totalText = durationText(totalMs(sessions));
      this.todayText = durationText(msOfDay(sessions, now));
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
      this.loading = false;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'load stats failed: %{public}s', JSON.stringify(e));
      this.loading = false;
    }
  }

  @Builder
  metricCard(label: string, value: string, hint: string) {
    Column() {
      Text(label)
        .fontSize(10)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
      Text(value)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.palette.text)
        .margin({ top: 6 })
      Text(hint)
        .fontSize(9)
        .fontFamily('monospace')
        .fontColor(this.palette.text3)
        .margin({ top: 4 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding(14)
    .borderRadius(12)
    .backgroundColor(this.palette.card)
    .borderWidth(1)
    .borderColor(this.palette.line)
  }

  build() {
    Column() {
      // 顶部
      Row() {
        Text('‹')
          .fontSize(20)
          .fontColor(this.palette.text)
          .width(30)
          .height(30)
          .responseRegion({ x: -8, y: -8, width: 46, height: 46 })
          .textAlign(TextAlign.Center)
          .borderWidth(1)
          .borderColor(this.palette.line)
          .onClick(() => {
            router.back();
          })
        Text('阅读统计')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette.text)
          .margin({ left: 12 })
        Blank()
        Text(`${WINDOW_DAYS} 天`)
          .fontSize(9)
          .fontFamily('monospace')
          .fontColor(this.palette.text3)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10, bottom: 16 })

      if (this.loading) {
        Column() {
          Text('···')
            .fontSize(13)
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
            .margin({ top: 10 })

            // 近 7 天柱状
            Column() {
              Text(`近 ${CHART_DAYS} 天`)
                .fontSize(10)
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
              .margin({ top: 10 })

              Row() {
                ForEach(this.week, (ms: number, i: number) => {
                  Text(i === this.week.length - 1 ? '今天' : `${this.week.length - 1 - i}天前`)
                    .fontSize(8)
                    .fontFamily('monospace')
                    .fontColor(this.palette.text3)
                    .layoutWeight(1)
                    .textAlign(TextAlign.Center)
                }, (ms: number, i: number) => 'lb' + i)
              }
              .width('100%')
              .margin({ top: 6 })
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor(this.palette.card)
            .borderWidth(1)
            .borderColor(this.palette.line)
            .margin({ top: 10 })

            // 每本书
            if (this.rows.length > 0) {
              Column() {
                Text('读得最多的书')
                  .fontSize(10)
                  .fontFamily('monospace')
                  .fontColor(this.palette.text3)
                  .alignSelf(ItemAlign.Start)

                ForEach(this.rows, (row: BookStatRow) => {
                  Row() {
                    Text(row.title)
                      .fontSize(12.5)
                      .fontColor(this.palette.text)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    Text(durationText(row.ms))
                      .fontSize(11)
                      .fontFamily('monospace')
                      .fontColor(this.palette.text3)
                  }
                  .width('100%')
                  .padding({ top: 10 })
                }, (row: BookStatRow) => row.title + row.ms)
              }
              .width('100%')
              .padding(14)
              .borderRadius(12)
              .backgroundColor(this.palette.card)
              .borderWidth(1)
              .borderColor(this.palette.line)
              .margin({ top: 10 })
            }

            Text('全部数据都在你的设备上，不上传、不联网')
              .fontSize(9.5)
              .fontFamily('monospace')
              .fontColor(this.palette.text3)
              .margin({ top: 16, bottom: 20 })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette.bg)
    .padding({ left: 22, right: 22 })
  }
}
