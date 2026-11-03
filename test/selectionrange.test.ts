import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  MIN_SELECTION_LEN, excerptOfSelection, selectionIsEmpty, selectionWorthKeeping, toChapterRange
} from '../entry/src/main/ets/engine/marks/SelectionRange';

// ── 坐标换算：页内下标 ⇒ 章内偏移 ────────────────────────────────────
//
// ⚠️ 这是划词功能最容易错的地方：
//   `onTextSelectionChange` 给的是**当页文本内**的下标；
//   而 `highlights` 表存的是 (chapter_index, start_char, end_char)，**章内偏移**。
//   换算公式 = 当页起始偏移 + 页内下标。

test('toChapterRange: 页内下标换算成章内偏移', () => {
  const r = toChapterRange(1000, 500, 10, 20);
  assert.ok(r !== null);
  assert.equal(r.start, 1010);
  assert.equal(r.end, 1020);
});

test('toChapterRange: 第 0 页（起始偏移 0）就是原样', () => {
  const r = toChapterRange(0, 500, 5, 15);
  assert.ok(r !== null);
  assert.equal(r.start, 5);
  assert.equal(r.end, 15);
});

test('toChapterRange: 整页选区（0 ~ 页长）⇒ 正好是这一页的区间', () => {
  const r = toChapterRange(200, 300, 0, 300);
  assert.ok(r !== null);
  assert.equal(r.start, 200);
  assert.equal(r.end, 500);
});

test('toChapterRange: 非法选区返回 null（不产生脏坐标进 DB）', () => {
  // 起点为负
  assert.equal(toChapterRange(0, 500, -1, 20), null);
  // 终点在起点之前（用户反向拖选）
  assert.equal(toChapterRange(0, 500, 30, 10), null);
  // 超出当页文本长度
  assert.equal(toChapterRange(0, 500, 10, 600), null);
  // 终点等于起点（没选中东西）
  assert.equal(toChapterRange(0, 500, 10, 10), null);
});

test('toChapterRange: NaN / Infinity 一律 null（脏数据不进 DB）', () => {
  assert.equal(toChapterRange(NaN, 500, 0, 10), null);
  assert.equal(toChapterRange(0, 500, NaN, 10), null);
  assert.equal(toChapterRange(0, 500, 0, Infinity), null);
  assert.equal(toChapterRange(Infinity, 500, 0, 10), null);
});

// ── 快照截取 ──────────────────────────────────────────────────────────

test('excerptOfSelection: 截出选中的那段', () => {
  const page: string = '前面的内容在这里。然后是选中的一段。然后是后面的。';
  const start: number = page.indexOf('选中的一段');
  const ex: string = excerptOfSelection(page, start, start + '选中的一段'.length);
  assert.equal(ex, '选中的一段');
});

test('excerptOfSelection: 空白归一化（换行/连续空格压成单空格，与整页快照同口径）', () => {
  const page: string = '前\n\n  后';
  const ex: string = excerptOfSelection(page, 0, page.length);
  assert.equal(ex, '前 后');
});

test('excerptOfSelection: 超过上限被截断', () => {
  const page: string = '字'.repeat(500);
  const ex: string = excerptOfSelection(page, 0, 500);
  assert.equal(ex.length, 200);
});

test('excerptOfSelection: 非法区间返回空串', () => {
  assert.equal(excerptOfSelection('abc', 2, 1), '');
  assert.equal(excerptOfSelection('abc', -1, 2), '');
  assert.equal(excerptOfSelection('abc', 0, 99), '');
});

// ── 值不值得存 ────────────────────────────────────────────────────────

test('selectionWorthKeeping: 少于 2 字符的选区不值得存（多半是误触）', () => {
  assert.equal(MIN_SELECTION_LEN, 2);
  assert.equal(selectionWorthKeeping(0, 1), false);
  assert.equal(selectionWorthKeeping(5, 5), false);
});

test('selectionWorthKeeping: 2 字符及以上就值得存', () => {
  assert.equal(selectionWorthKeeping(0, 2), true);
  assert.equal(selectionWorthKeeping(10, 100), true);
});

test('selectionWorthKeeping: 非法区间返回 false', () => {
  assert.equal(selectionWorthKeeping(-1, 10), false);
  assert.equal(selectionWorthKeeping(10, 5), false);
  assert.equal(selectionWorthKeeping(NaN, 10), false);
});

// ── 空选区判定（面板的唯一门槛）────────────────────────────────────────
//
// ⚠️ 2026-11-03 模拟器实测：系统中文长按默认只选中**一个字**（range 3-4）。
//   之前用「少于 2 字就丢弃」拦在点「加入摘录」之前 ⇒ 用户点了没反应＝死路。
//   ⇒ 门槛改成「只拒空选区」，1 个字照样开面板（面板可编辑，用户自己能改）。

test('selectionIsEmpty: 单个字符不算空（要开面板让用户自己改）', () => {
  assert.equal(selectionIsEmpty(3, 4), false);
  assert.equal(selectionIsEmpty(0, 1), false);
});

test('selectionIsEmpty: 空选区（start == end）算空', () => {
  assert.equal(selectionIsEmpty(5, 5), true);
  assert.equal(selectionIsEmpty(0, 0), true);
});

test('selectionIsEmpty: 非法区间算空（负数 / 反向 / NaN）', () => {
  assert.equal(selectionIsEmpty(-1, 10), true);
  assert.equal(selectionIsEmpty(10, 5), true);
  assert.equal(selectionIsEmpty(NaN, 10), true);
  assert.equal(selectionIsEmpty(0, Infinity), true);
});
