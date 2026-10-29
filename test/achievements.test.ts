/**
 * P0-4 阅读成就单测（纯逻辑）
 * 锁住 8 个徽章的阈值、进度条口径、脏值收敛 —— 防止将来"顺手改阈值"导致用户
 * 已点亮的徽章莫名消失或永远点不亮。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  achievementsOf,
  Achievement,
  AchievementInput,
  finishedBookCount,
  unlockedCount
} from '../entry/src/main/ets/engine/stats/ReadStats.ets';

function input(over: Partial<AchievementInput> = {}): AchievementInput {
  return {
    totalMs: 0,
    streak: 0,
    sessionCount: 0,
    finishedBooks: 0,
    ...over
  };
}

test('徽章表固定 8 个，id 稳定（改这里等于改用户已见成就）', () => {
  const list: Achievement[] = achievementsOf(input());
  assert.equal(list.length, 8);
  const ids: string[] = list.map((a: Achievement) => a.id);
  assert.deepEqual(ids, [
    'first_read', 'streak_3', 'streak_7', 'streak_14',
    'hours_10', 'hours_50', 'books_1', 'books_5'
  ]);
});

test('全新用户：全部未解锁、进度为 0', () => {
  const list: Achievement[] = achievementsOf(input());
  for (const a of list) {
    assert.equal(a.unlocked, false, a.id);
    assert.equal(a.ratio, 0, a.id);
  }
  assert.equal(unlockedCount(list), 0);
});

test('开卷有益：累计满 10 分钟解锁；9.9 分钟不解锁但进度接近 1', () => {
  const done: Achievement = achievementsOf(input({ totalMs: 10 * 60000 }))[0];
  assert.equal(done.unlocked, true);
  assert.equal(done.ratio, 1);
  const almost: Achievement = achievementsOf(input({ totalMs: 9.9 * 60000 }))[0];
  assert.equal(almost.unlocked, false);
  assert.ok(almost.ratio > 0.98 && almost.ratio < 1);
});

test('连续徽章：3/7/14 天按阈值逐级点亮', () => {
  const at3 = achievementsOf(input({ streak: 3 }));
  assert.equal(at3[1].unlocked, true, '三日成习');
  assert.equal(at3[2].unlocked, false, '七日之约还没到');
  assert.equal(at3[3].unlocked, false);
  const at7 = achievementsOf(input({ streak: 7 }));
  assert.equal(at7[1].unlocked, true);
  assert.equal(at7[2].unlocked, true);
  assert.equal(at7[3].unlocked, false);
  const at14 = achievementsOf(input({ streak: 14 }));
  assert.equal(at14[3].unlocked, true);
  assert.equal(unlockedCount(at14), 3, 'streak 只点亮 3 个连续徽章');
});

test('时长徽章：10 小时 / 50 小时（分钟口径换算）', () => {
  const at10h = achievementsOf(input({ totalMs: 10 * 3600000 }));
  assert.equal(at10h[4].unlocked, true, '十时沉浸');
  assert.equal(at10h[5].unlocked, false, '五十时还没到');
  const at50h = achievementsOf(input({ totalMs: 50 * 3600000 }));
  assert.equal(at50h[5].unlocked, true);
});

test('读完徽章：1 本 / 5 本', () => {
  const at1 = achievementsOf(input({ finishedBooks: 1 }));
  assert.equal(at1[6].unlocked, true);
  assert.equal(at1[7].unlocked, false);
  const at5 = achievementsOf(input({ finishedBooks: 5 }));
  assert.equal(at5[7].unlocked, true);
});

test('全满：8/8 点亮', () => {
  const list = achievementsOf(input({
    totalMs: 50 * 3600000, streak: 14, finishedBooks: 5, sessionCount: 999
  }));
  assert.equal(unlockedCount(list), 8);
  for (const a of list) {
    assert.equal(a.ratio, 1, a.id);
  }
});

test('脏值（NaN / 负数）收敛为 0，绝不点亮也不出 NaN 进度', () => {
  const list = achievementsOf(input({
    totalMs: Number.NaN, streak: -5, sessionCount: Number.NaN, finishedBooks: -1
  }));
  for (const a of list) {
    assert.equal(a.unlocked, false, a.id);
    assert.ok(Number.isFinite(a.ratio), a.id + ' 的 ratio 不能是 NaN');
    assert.equal(a.ratio, 0);
  }
});

test('unlockedCount：空表为 0', () => {
  assert.equal(unlockedCount([]), 0);
});

test('finishedBookCount：≥0.99 算读完，脏值（NaN/负数/越界）忽略', () => {
  assert.equal(finishedBookCount([1, 0.995, 0.99, 0.989, 0.5]), 3);
  assert.equal(finishedBookCount([Number.NaN, -1, 2, 1.5, 1]), 1); // 越界/脏值都不算，只有 1 合法
  assert.equal(finishedBookCount([]), 0);
});
