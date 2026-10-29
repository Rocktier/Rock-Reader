/**
 * 字数普查节奏与取消的守门测试（2026-10-29，AGC 点击时延整改）
 *
 * 锁住两条直接影响「点开一本书卡不卡」的属性：
 *   ① 分帧粒度必须是**每章**（原每 8 章 → 一次冻结 8 章，AGC 转场 lane 被整段推后）
 *   ② 取消标志必须可置位/可复位/可查询（离开阅读页要能停普查）
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  SURVEY_YIELD_EVERY, SurveyCancel, surveyShouldContinue, surveyShouldYield
} from '../entry/src/main/ets/data/Survey.ets';

test('分帧粒度必须是每章一章（不是每 8 章）', () => {
  assert.equal(SURVEY_YIELD_EVERY, 1);
});

test('每章都要让出一帧', () => {
  assert.equal(surveyShouldYield(0), true);
  assert.equal(surveyShouldYield(1), true);
  assert.equal(surveyShouldYield(2), true);
  assert.equal(surveyShouldYield(99), true);
});

test('越界下标不让帧（防御：负数不该触发让帧）', () => {
  assert.equal(surveyShouldYield(-1), false);
});

test('未取消时继续普查', () => {
  assert.equal(surveyShouldContinue(false), true);
});

test('已取消时立刻退出普查', () => {
  assert.equal(surveyShouldContinue(true), false);
});

test('取消标志：初始未取消 → 置位 → 复位', () => {
  const c = new SurveyCancel();
  assert.equal(c.isCancelled(), false);
  c.cancel();
  assert.equal(c.isCancelled(), true);
  c.reset();
  assert.equal(c.isCancelled(), false);
});

test('取消标志：新开一本书要能复用（复位后仍可用）', () => {
  const c = new SurveyCancel();
  c.cancel();
  c.reset();
  // 复位后再取消仍生效（说明不是一次性状态）
  c.cancel();
  assert.equal(c.isCancelled(), true);
});
