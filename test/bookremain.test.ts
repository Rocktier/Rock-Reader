/**
 * P0-3 全书剩余时间单测（纯逻辑）
 *
 * bookCharsLeft 必须与 bookPercentOf **同源**：已知章用真值、未知章按均值外推。
 * 这里用「总量 / 已读」互验，防止两处口径漂移（漂移 = 进度 60% 剩余却算成 40% 的另一套数）。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bookCharsLeft,
  bookLeftText,
  bookPercentOf,
  chapterLeftText,
  EST_WPM
} from '../entry/src/main/ets/engine/stats/ReadStats.ets';

test('bookCharsLeft：全部章已量 → 剩余 = 总量 - 已读，精确到个位', () => {
  // 3 章，字数 [1000, 2000, 3000]，总量 6000
  // 读在第 1 章（idx=1）50% → 已读 = 1000 + 2000*0.5 = 2000 → 剩 4000
  assert.equal(bookCharsLeft([1000, 2000, 3000], 3, 1, 0.5), 4000);
  // 读在第 0 章开头 → 已读 0 → 剩 6000
  assert.equal(bookCharsLeft([1000, 2000, 3000], 3, 0, 0), 6000);
  // 读在末章末尾 → 已读 6000 → 剩 0
  assert.equal(bookCharsLeft([1000, 2000, 3000], 3, 2, 1), 0);
});

test('bookCharsLeft：未知章按已确认章均值外推（与 bookPercentOf 同源）', () => {
  // 4 章，已知 [1000, 0, 2000, 0] → 均值 (1000+2000)/2 = 1500
  // 总量 = 1000 + 2000 + 1500 + 1500 = 6000
  // 读在 idx=0 全部 + idx=1 到 50% → 已读 = 1000 + 1500*0.5 = 1750 → 剩 4250
  const counts: number[] = [1000, 0, 2000, 0];
  const left: number = bookCharsLeft(counts, 4, 1, 0.5);
  assert.equal(left, 4250);
  // 互验：进度 = (总量-剩余)/总量
  const pct: number = bookPercentOf(counts, 4, 1, 0.5);
  assert.ok(Math.abs((6000 - left) / 6000 - pct) < 1e-9, '剩余与进度必须同源，不能各算各的');
});

test('bookCharsLeft：一章都没量过 → -1（不编数字）；越界与脏值收敛', () => {
  assert.equal(bookCharsLeft([0, 0, 0], 3, 0, 0.2), -1);
  assert.equal(bookCharsLeft([], 3, 0, 0.2), -1);
  assert.equal(bookCharsLeft([1000], 0, 0, 0), -1, 'total<=0');
  // chapterIndex 越界被夹取，pagePercent 被 clamp01，不许算出 NaN/负数
  const left: number = bookCharsLeft([1000, 2000], 2, 99, 5);
  assert.ok(left >= 0 && Number.isFinite(left));
  assert.equal(bookCharsLeft([1000, 2000], 2, -3, Number.NaN), 3000);
});

test('bookLeftText：分钟档 / 小时档 / 边界 / 脏值', () => {
  assert.equal(bookLeftText(-1), '', '无法估算');
  assert.equal(bookLeftText(0), '', '已读完');
  assert.equal(bookLeftText(Number.NaN), '');
  assert.equal(bookLeftText(1), '全书还剩不到 1 分钟');
  assert.equal(bookLeftText(349), '全书还剩不到 1 分钟');
  assert.equal(bookLeftText(350), '全书还剩约 1 分钟');
  assert.equal(bookLeftText(350 * 30), '全书还剩约 30 分钟');
  // 350*60 = 21000 → 60 分钟整 = 1 小时
  assert.equal(bookLeftText(21000), '全书还剩约 1 小时');
  // 350*90 = 31500 → 90 分钟 = 1 小时 30 分
  assert.equal(bookLeftText(31500), '全书还剩约 1 小时 30 分');
  // 350*125 = 43750 → 125 分钟 = 2 小时 5 分
  assert.equal(bookLeftText(43750), '全书还剩约 2 小时 5 分');
});

test('P0-3 与 A3 本章剩余共用同一估算速度（口径一致，不许各设一套）', () => {
  // 同样 700 字：本章/全书文案除了前缀，分钟数应一致
  assert.equal(chapterLeftText(700), '本章还剩约 2 分钟');
  assert.equal(bookLeftText(700), '全书还剩约 2 分钟');
  assert.ok(EST_WPM > 0);
});
