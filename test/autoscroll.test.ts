/**
 * 自动滚动（滚屏）纯逻辑单测
 *
 * 守的是三件容易出事故的事：
 *  1. **跨章推进**：章末那一拍必须翻到下一章，而不是停在章尾反复翻。
 *  2. **到底收工**：全书最后一页必须停，不能无限翻。
 *  3. **脏值不崩**：速度档从偏好读出来可能是脏的（老版本、越界、手改），
 *     归一化必须兜住，不能让定时器拿到 NaN。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  nextScrollSpeed,
  normalizeScrollSpeed,
  remainingPages,
  remainingText,
  ScrollAction,
  scrollAction,
  scrollSpeedIndex,
  scrollSpeedText,
  scrollTickAllowed,
  scrollToggleOf,
  SCROLL_END_HINT,
  SCROLL_SPEED_DEFAULT,
  SCROLL_SPEEDS,
  ScrollState,
  ScrollToggle,
  toggleScrollState
} from '../entry/src/main/ets/data/AutoScroll.ets';

test('速度档文案带单位', () => {
  assert.equal(scrollSpeedText(4), '4秒/页');
  assert.equal(scrollSpeedText(2), '2秒/页');
});

test('速度档表：五档、默认 4 秒、都在 2~8 之间', () => {
  assert.equal(SCROLL_SPEEDS.length, 5);
  assert.equal(SCROLL_SPEED_DEFAULT, 4);
  assert.ok(SCROLL_SPEEDS.indexOf(SCROLL_SPEED_DEFAULT) >= 0);
  for (const s of SCROLL_SPEEDS) {
    assert.ok(s >= 2 && s <= 8, `档位越界: ${s}`);
  }
});

test('速度档下标：命中返回下标，脏值返回 -1', () => {
  assert.equal(scrollSpeedIndex(4), SCROLL_SPEEDS.indexOf(4));
  assert.equal(scrollSpeedIndex(999), -1);
  assert.equal(scrollSpeedIndex(0), -1);
});

test('速度档循环：走到头回到第一档', () => {
  const first: number = SCROLL_SPEEDS[0];
  const last: number = SCROLL_SPEEDS[SCROLL_SPEEDS.length - 1];
  assert.equal(nextScrollSpeed(last), first);
  // 依次切一遍能回到原位
  let cur: number = SCROLL_SPEED_DEFAULT;
  for (let i = 0; i < SCROLL_SPEEDS.length; i++) {
    cur = nextScrollSpeed(cur);
  }
  assert.equal(cur, SCROLL_SPEED_DEFAULT);
});

test('脏速度档：循环不崩，归一化回默认', () => {
  assert.ok(nextScrollSpeed(999) > 0);
  assert.equal(normalizeScrollSpeed(999), SCROLL_SPEED_DEFAULT);
  assert.equal(normalizeScrollSpeed(-1), SCROLL_SPEED_DEFAULT);
  assert.equal(normalizeScrollSpeed(NaN), SCROLL_SPEED_DEFAULT);
  assert.equal(normalizeScrollSpeed(4), 4);
});

test('状态切换：运行↔暂停，未启用时直接进运行', () => {
  assert.equal(toggleScrollState(ScrollState.RUNNING), ScrollState.PAUSED);
  assert.equal(toggleScrollState(ScrollState.PAUSED), ScrollState.RUNNING);
  assert.equal(toggleScrollState(ScrollState.OFF), ScrollState.RUNNING);
});

test('一拍动作：页内还有剩 → 翻页', () => {
  assert.equal(scrollAction(0, 10, 0, 3), ScrollAction.TURN);
  assert.equal(scrollAction(8, 10, 0, 3), ScrollAction.TURN);
});

test('一拍动作：本章最后一页但还有下一章 → 跨章翻（不是停）', () => {
  assert.equal(scrollAction(9, 10, 0, 3), ScrollAction.TURN);
  assert.equal(scrollAction(0, 1, 1, 3), ScrollAction.TURN);
});

test('一拍动作：全书最后一页 → 停', () => {
  assert.equal(scrollAction(9, 10, 2, 3), ScrollAction.STOP);
  assert.equal(scrollAction(0, 1, 0, 1), ScrollAction.STOP);
});

test('一拍动作：没有页（未打开）→ 停，不空转', () => {
  assert.equal(scrollAction(0, 0, 0, 0), ScrollAction.STOP);
  assert.equal(scrollAction(0, 5, 0, 0), ScrollAction.STOP);
});

test('剩余页数：章内剩余 + 后面各章按当前章页数粗估', () => {
  // 本章 10 页，现在第 0 页（0-based）：章内剩 9，后面还有 2 章 ⇒ 9 + 2*10 = 29
  assert.equal(remainingPages(0, 10, 0, 3), 29);
  // 本章最后一页：章内剩 0，后面 2 章 ⇒ 20
  assert.equal(remainingPages(9, 10, 0, 3), 20);
  // 全书最后一页：0
  assert.equal(remainingPages(9, 10, 2, 3), 0);
  // 算不出来
  assert.equal(remainingPages(0, 0, 0, 0), -1);
});

test('剩余时间文案：不足 1 分钟 / 约 N 分钟 / 算不出时为空', () => {
  // 向上取整：剩 0 页 = 不足 1 分钟；剩 1 页（4 秒）向上取整也是 1 分钟 ⇒「约 1 分钟」
  assert.equal(remainingText(0, 4), '不足 1 分钟');
  assert.equal(remainingText(1, 4), '约 1 分钟');
  assert.equal(remainingText(15, 4), '约 1 分钟');
  assert.equal(remainingText(30, 4), '约 2 分钟');
  assert.equal(remainingText(-1, 4), '');
  assert.equal(remainingText(10, 0), '');
});

test('到底提示文案非空', () => {
  assert.ok(SCROLL_END_HINT.length > 0);
});

test('菜单按钮三态：OFF→开跑、PAUSED→继续、RUNNING→停', () => {
  // ⚠️ 最容易出事故的一格：**PAUSED 必须映射到 RESUME，不能映射到 STOP**。
  // 用户在浮条上按了「暂停」，再开菜单按「滚屏」，
  // 若这里判成 STOP 就等于「用户想继续、结果被关掉」—— 静默的期望违背。
  assert.equal(scrollToggleOf(ScrollState.OFF), ScrollToggle.START);
  assert.equal(scrollToggleOf(ScrollState.PAUSED), ScrollToggle.RESUME);
  assert.equal(scrollToggleOf(ScrollState.RUNNING), ScrollToggle.STOP);
  // 三种状态映射到三种不同动作 —— 相同就等于按钮说不清自己会做什么
  const actions: ScrollToggle[] = [
    scrollToggleOf(ScrollState.OFF),
    scrollToggleOf(ScrollState.PAUSED),
    scrollToggleOf(ScrollState.RUNNING)
  ];
  assert.equal(new Set(actions).size, 3);
});

test('浮层遮着正文时不翻页：任一浮层开着就不许翻', () => {
  assert.equal(scrollTickAllowed(false, false, false, false), true);
  assert.equal(scrollTickAllowed(true, false, false, false), false, '菜单开着');
  assert.equal(scrollTickAllowed(false, true, false, false), false, '目录开着');
  assert.equal(scrollTickAllowed(false, false, true, false), false, '设置开着');
  assert.equal(scrollTickAllowed(false, false, false, true), false, '摘录卡开着');
  // 多个同时开着也不许翻
  assert.equal(scrollTickAllowed(true, true, true, true), false);
});
