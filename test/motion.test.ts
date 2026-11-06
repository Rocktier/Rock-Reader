/**
 * 动效 token 单测（纯数值 / 纯函数，零 ArkUI 依赖）
 *
 * 守两件事：
 *   ① **降级必须是 0 而不是"变慢"** —— 「减少动态效果」的用户要的是不动，不是慢动作；
 *   ② **错峰必须封顶** —— 书架一百本若按 index 线性累加，最后一本要等六秒才出现，
 *      比不做动效更糟。这两条都是"看起来对、真机上很糟"的典型，靠眼睛发现不了。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MOTION_MS_ENTER,
  MOTION_MS_STEP,
  ANIM_SCALE_DEFAULT,
  isReducedMotion,
  motionMs,
  staggerMs
} from '../entry/src/main/ets/common/Motion.ets';

test('motionMs：正常档原样返回', () => {
  assert.equal(motionMs(MOTION_MS_ENTER, false), 280);
  assert.equal(motionMs(0, false), 0);
});

test('motionMs：减少动态效果 ⇒ 时长归零（瞬时到终态，不是变慢）', () => {
  assert.equal(motionMs(MOTION_MS_ENTER, true), 0);
  assert.equal(motionMs(1000, true), 0);
});

test('motionMs：负数当 0（脏值不许产生负时长）', () => {
  assert.equal(motionMs(-1, false), 0);
});

test('staggerMs：线性错峰', () => {
  assert.equal(staggerMs(0, 8), 0);
  assert.equal(staggerMs(1, 8), MOTION_MS_STEP);
  assert.equal(staggerMs(3, 8), 3 * MOTION_MS_STEP);
});

test('staggerMs：超过封顶就一起落位（长书架不排队）', () => {
  assert.equal(staggerMs(8, 8), 8 * MOTION_MS_STEP);
  assert.equal(staggerMs(99, 8), 8 * MOTION_MS_STEP);
  assert.equal(staggerMs(99, 8, 40), 320);
});

test('staggerMs：负 index / 负 cap 都夹到 0', () => {
  assert.equal(staggerMs(-3, 8), 0);
  assert.equal(staggerMs(5, -1), 0);
});

/**
 * 系统「减少动态效果」读数 → 是否降级（2026-11-06 接上真实开关）。
 *
 * 读的是 `settings.display.ANIMATOR_DURATION_SCALE`（动画时长倍率）：
 * **0 = 动画立即结束**，也就是"移除动画"打开时的值。
 *
 * 这条测试的重点不在 0 和 1，而在**读不到怎么办**：
 * 本地 x86 模拟器没有 settingsdata 目录，`getValueSync` 会抛错并回落成 '1'；
 * 若把空串/脏值判成"要降级"，整台机器上所有动效会静默消失 —— 谁也不知道为什么。
 */
test('isReducedMotion：0 才算降级，读不到/脏值一律当正常', () => {
  assert.equal(isReducedMotion('0'), true);
  assert.equal(isReducedMotion('1'), false);
  assert.equal(isReducedMotion('0.5'), false, '0.5 是"变慢"不是"关闭"');
  assert.equal(isReducedMotion('-1'), true, '负值当 0 处理');
  assert.equal(isReducedMotion(''), false, '空串不能当成关闭 —— 否则读取失败会让动效全没');
  assert.equal(isReducedMotion('abc'), false);
  assert.equal(isReducedMotion(ANIM_SCALE_DEFAULT), false, '默认值必须是不降级');
});
