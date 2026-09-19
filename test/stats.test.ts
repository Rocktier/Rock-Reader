/**
 * 阅读统计单测（纯逻辑）
 * 全部断言都与时区无关：时间点都用 startOfDay 派生，避免"跑在不同时区的机器上结果不同"。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  byBook,
  dailyMs,
  durationText,
  msInRange,
  msOfDay,
  MIN_SESSION_MS,
  ReadSession,
  sessionMs,
  startOfDay,
  startOfNextDay,
  streakDays,
  totalMs
} from '../entry/src/main/ets/engine/stats/ReadStats.ets';

const DAY: number = 24 * 60 * 60 * 1000;
const BASE: number = new Date(2026, 8, 19, 12, 0, 0).getTime();

function s(startAt: number, endAt: number, bookId: string = 'b1', chapterIndex: number = 0): ReadSession {
  return { bookId: bookId, chapterIndex: chapterIndex, startAt: startAt, endAt: endAt };
}

function dayOffset(n: number): number {
  return startOfDay(BASE) + n * DAY;
}

test('sessionMs：脏数据（倒挂 / NaN / 零长）一律记 0，不许出现负数时长', () => {
  assert.equal(sessionMs(s(1000, 5000)), 4000);
  assert.equal(sessionMs(s(5000, 1000)), 0);
  assert.equal(sessionMs(s(1000, 1000)), 0);
  assert.equal(sessionMs(s(Number.NaN, 1000)), 0);
});

test('totalMs：累加所有会话时长', () => {
  const list: ReadSession[] = [s(dayOffset(0), dayOffset(0) + 60000), s(dayOffset(-1), dayOffset(-1) + 30000)];
  assert.equal(totalMs(list), 90000);
});

test('msInRange：区间外不计、部分重叠按交集裁剪', () => {
  const from: number = dayOffset(0);
  const to: number = startOfNextDay(BASE);
  const list: ReadSession[] = [
    s(from - 10000, from + 20000),      // 跨区间左边界：只算 20000
    s(to - 5000, to + 5000),            // 跨右边界：只算 5000
    s(from - 50000, from - 10000),      // 完全在区间外
    s(from + 1000, from + 4000)         // 完全在区间内：3000
  ];
  assert.equal(msInRange(list, from, to), 28000);
  assert.equal(msInRange(list, to, from), 0, '反向区间必须是 0，不能算出负数');
});

test('非法时长的会话不进统计（不允许 NaN 污染总和）', () => {
  const bad: ReadSession[] = [s(5000, 1000), s(Number.NaN, Number.NaN)];
  assert.equal(totalMs(bad), 0);
  assert.equal(msInRange(bad, 0, Number.MAX_SAFE_INTEGER), 0);
});

test('msOfDay：熬夜跨日的会话只把落在当天的那部分算给当天', () => {
  const yesterday: number = dayOffset(-1);
  const midnight: number = startOfDay(BASE);
  // 昨天 23:30 读到今天 00:30
  const list: ReadSession[] = [s(midnight - 30 * 60000, midnight + 30 * 60000)];
  assert.equal(msOfDay(list, BASE), 30 * 60000, '今天只应得 30 分钟');
  assert.equal(msOfDay(list, yesterday), 30 * 60000, '昨天只得 30 分钟');
});

test('streakDays：今天 + 昨天 + 前天 → 3 天', () => {
  const list: ReadSession[] = [
    s(dayOffset(0) + 3600000, dayOffset(0) + 3660000),
    s(dayOffset(-1) + 3600000, dayOffset(-1) + 3660000),
    s(dayOffset(-2) + 3600000, dayOffset(-2) + 3660000)
  ];
  assert.equal(streakDays(list, BASE), 3);
});

test('streakDays：今天还没读但昨天读过 → 不算断（从昨天往前数）', () => {
  const list: ReadSession[] = [
    s(dayOffset(-1) + 3600000, dayOffset(-1) + 3660000),
    s(dayOffset(-2) + 3600000, dayOffset(-2) + 3660000)
  ];
  assert.equal(streakDays(list, BASE), 2);
});

test('streakDays：中间断了一天 → 只数到今天为止的连续段', () => {
  const list: ReadSession[] = [
    s(dayOffset(0) + 3600000, dayOffset(0) + 3660000),
    s(dayOffset(-2) + 3600000, dayOffset(-2) + 3660000)  // 昨天缺
  ];
  assert.equal(streakDays(list, BASE), 1);
});

test('streakDays：完全没读过（或只有非法会话）→ 0', () => {
  assert.equal(streakDays([], BASE), 0);
  assert.equal(streakDays([s(5000, 1000)], BASE), 0);
});

test('dailyMs：长度正确，末位是今天，跨日会话按天裁剪', () => {
  const midnight: number = startOfDay(BASE);
  const list: ReadSession[] = [
    s(midnight - 30 * 60000, midnight + 30 * 60000),   // 昨天 30 分 + 今天 30 分
    s(dayOffset(-3) + 3600000, dayOffset(-3) + 3660000) // 3 天前 1 分钟
  ];
  const week: number[] = dailyMs(list, BASE, 7);
  assert.equal(week.length, 7);
  assert.equal(week[6], 30 * 60000, '末位 = 今天');
  assert.equal(week[5], 30 * 60000, '前一天（昨天）');
  assert.equal(week[3], 60000, '3 天前');
  assert.equal(week[0], 0, '4 天前没读');
  assert.deepEqual(dailyMs(list, BASE, 0), [], 'days<=0 返回空数组，不许崩');
});

test('durationText：秒 / 分 / 小时三档，零与脏数据是「—」', () => {
  assert.equal(durationText(0), '—');
  assert.equal(durationText(-5), '—');
  assert.equal(durationText(Number.NaN), '—');
  assert.equal(durationText(48000), '48 秒');
  assert.equal(durationText(36 * 60000), '36 分');
  assert.equal(durationText(2 * 3600000), '2 小时');
  assert.equal(durationText(2 * 3600000 + 5 * 60000), '2 小时 5 分');
});

test('byBook：按书汇总并降序；非法会话记 0 但仍入表', () => {
  const list: ReadSession[] = [
    s(0, 60000, 'a'),
    s(0, 30000, 'b'),
    s(0, 90000, 'a')
  ];
  const totals = byBook(list);
  assert.equal(totals[0].bookId, 'a');
  assert.equal(totals[0].ms, 150000);
  assert.equal(totals[1].bookId, 'b');
  assert.equal(totals[1].ms, 30000);
});

test('MIN_SESSION_MS 是合理阈值（翻目录误触不该进统计）', () => {
  assert.equal(MIN_SESSION_MS, 3000);
});
