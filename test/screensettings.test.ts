import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  BRIGHTNESS_DEFAULT_INDEX, BRIGHTNESS_LEVELS, BRIGHTNESS_SYSTEM, applyWindowSettings, brightnessLabelOf,
  brightnessValueOf, nextBrightnessIndex, restoreWindowSettings
} from '../entry/src/main/ets/engine/reader/ScreenSettings';

// ── 档位表：窗口亮度的语义与边界 ──────────────────────────────────────
//
// 背景（2026-11-03）：全仓 keepScreenOn / setWindowBrightness 零命中，
// 对标 Apple Books / Kindle / 静读天下（都有「阅读时保持常亮」+「阅读页独立亮度」）。
//
// ⚠️ 关键 SDK 约束（决定了这些用例在锁什么）：
//   `setWindowBrightness` 只在窗口前台有焦点时生效，**传 -1 恢复系统亮度**。

test('brightness levels: 第一档必须是「跟随系统」（值 -1）', () => {
  assert.equal(BRIGHTNESS_LEVELS[0].value, BRIGHTNESS_SYSTEM);
  assert.equal(BRIGHTNESS_LEVELS[0].value, -1);
  assert.equal(BRIGHTNESS_LEVELS[0].label, '跟随系统');
});

test('brightness levels: 默认档就是「跟随系统」（不改变用户原有亮度习惯）', () => {
  assert.equal(BRIGHTNESS_DEFAULT_INDEX, 0);
  assert.equal(brightnessValueOf(BRIGHTNESS_DEFAULT_INDEX), -1);
});

test('brightness levels: 所有档位的亮度值都在 0~1 或 -1 之内', () => {
  for (const lv of BRIGHTNESS_LEVELS) {
    assert.ok(lv.value === -1 || (lv.value >= 0 && lv.value <= 1),
      '亮度越界：' + lv.label + ' = ' + lv.value);
  }
});

test('brightness levels: 档位值必须严格递增（除 -1 那档外）', () => {
  const vals = BRIGHTNESS_LEVELS.filter((lv) => lv.value !== -1).map((lv) => lv.value);
  for (let i = 1; i < vals.length; i++) {
    assert.ok(vals[i] > vals[i - 1], '亮度档位必须递增：' + vals[i - 1] + ' → ' + vals[i]);
  }
});

test('brightness levels: 最亮档 = 1.0（等同系统满亮，不能更亮）', () => {
  assert.equal(brightnessValueOf(BRIGHTNESS_LEVELS.length - 1), 1.0);
});

// ── 脏值必须回落，绝不让脏数据进 UI ──────────────────────────────────

test('brightnessValueOf: 越界索引回落默认档（不抛错、不进 UI）', () => {
  assert.equal(brightnessValueOf(-1), -1);
  assert.equal(brightnessValueOf(BRIGHTNESS_LEVELS.length), -1);
  assert.equal(brightnessValueOf(999), -1);
});

test('brightnessValueOf: 非数字（NaN / Infinity）也回落', () => {
  assert.equal(brightnessValueOf(NaN), -1);
  assert.equal(brightnessValueOf(Infinity), -1);
});

test('brightnessLabelOf: 越界时给出「跟随系统」而不是空白/undefined', () => {
  assert.equal(brightnessLabelOf(-5), '跟随系统');
  assert.equal(brightnessLabelOf(999), '跟随系统');
  assert.equal(brightnessLabelOf(NaN), '跟随系统');
});

test('brightnessLabelOf: 正常档位给出对应文案', () => {
  assert.equal(brightnessLabelOf(1), '很暗');
  assert.equal(brightnessLabelOf(BRIGHTNESS_LEVELS.length - 1), '很亮');
});

// ── 循环切换 ──────────────────────────────────────────────────────────

test('nextBrightnessIndex: 循环（最后一档回到第一档）', () => {
  assert.equal(nextBrightnessIndex(0), 1);
  assert.equal(nextBrightnessIndex(BRIGHTNESS_LEVELS.length - 2), BRIGHTNESS_LEVELS.length - 1);
  assert.equal(nextBrightnessIndex(BRIGHTNESS_LEVELS.length - 1), 0);
});

test('nextBrightnessIndex: 越界输入回落默认档而不是崩', () => {
  assert.equal(nextBrightnessIndex(-1), BRIGHTNESS_DEFAULT_INDEX);
  assert.equal(nextBrightnessIndex(999), BRIGHTNESS_DEFAULT_INDEX);
  assert.equal(nextBrightnessIndex(NaN), BRIGHTNESS_DEFAULT_INDEX);
});

// ── 进/出阅读页的窗口设置（**必须成对**，漏一处就是 bug）──────────────

test('restoreWindowSettings: 离开阅读页必须把亮度还原成系统、关掉常亮', () => {
  const r = restoreWindowSettings();
  // ⚠️ 这两条是「退到书架后屏幕还压着暗 / 还常亮不灭」的根因所在
  assert.equal(r.brightness, -1);
  assert.equal(r.keepScreenOn, false);
});

test('applyWindowSettings: 亮度取档位值，常亮取用户选择', () => {
  const a = applyWindowSettings(2, true);
  assert.equal(a.brightness, brightnessValueOf(2));
  assert.equal(a.keepScreenOn, true);

  const b = applyWindowSettings(0, false);
  assert.equal(b.brightness, -1);
  assert.equal(b.keepScreenOn, false);
});

test('applyWindowSettings: 越界档位不产生非法亮度（回落 -1）', () => {
  const a = applyWindowSettings(999, true);
  assert.equal(a.brightness, -1);
});
