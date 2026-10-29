/**
 * P0-1 高亮调色板单测（纯逻辑）
 * 核心守门：老库 color=null 必须归一到默认 0 —— 否则补列前的老高亮会数组越界/发黑。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  COLOR_DEFAULT,
  COLOR_KEYS,
  colorIndices,
  highlightInk,
  normalizeColor
} from '../entry/src/main/ets/engine/marks/HighlightPalette.ets';

test('调色板：5 个语义色，默认索引 0', () => {
  assert.equal(COLOR_KEYS.length, 5);
  assert.equal(COLOR_DEFAULT, 0);
  assert.deepEqual(colorIndices(), [0, 1, 2, 3, 4]);
});

test('normalizeColor：合法索引原样返回', () => {
  assert.equal(normalizeColor(0), 0);
  assert.equal(normalizeColor(4), 4);
  assert.equal(normalizeColor(2.9), 2, '浮点向下取整');
});

test('normalizeColor：脏值（null/NaN/负/越界）一律回落默认 —— 老库兼容关键', () => {
  assert.equal(normalizeColor(null), 0);
  assert.equal(normalizeColor(undefined), 0);
  assert.equal(normalizeColor(Number.NaN), 0);
  assert.equal(normalizeColor(-1), 0);
  assert.equal(normalizeColor(5), 0, '越界');
  assert.equal(normalizeColor(999), 0);
});

test('highlightInk：昼夜两套色都是合法 hex，脏索引也不越界', () => {
  for (const i of colorIndices()) {
    assert.match(highlightInk(i, false), /^#[0-9A-Fa-f]{6}$/);
    assert.match(highlightInk(i, true), /^#[0-9A-Fa-f]{6}$/);
  }
  // 脏索引回落到默认色，与 normalizeColor(0) 的结果一致
  assert.equal(highlightInk(null as unknown as number, false), highlightInk(0, false));
  assert.equal(highlightInk(99, true), highlightInk(0, true));
  // 昼夜默认色不同（夜间更亮）
  assert.notEqual(highlightInk(0, false), highlightInk(0, true));
});
