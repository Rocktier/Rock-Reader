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
