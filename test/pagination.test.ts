import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildPageTable,
  layoutSignature,
  linesPerPage,
  pageOfChar
} from '../entry/src/main/ets/engine/paginator/PageTableBuilder.ets';

test('每页行数 = 视口高 / 行高，向下取整且至少 1 行', () => {
  assert.equal(linesPerPage(1000, 40), 25);
  assert.equal(linesPerPage(1000, 33), 30);
  assert.equal(linesPerPage(10, 40), 1);
  assert.equal(linesPerPage(1000, 0), 1);
});

test('页表：按行数切页，页与页首尾相接、无重叠', () => {
  // 10 行，每行结束索引依次为 10,20,...,100
  const lineEnds: number[] = [];
  for (let i = 1; i <= 10; i++) {
    lineEnds.push(i * 10);
  }
  const table = buildPageTable(lineEnds, 3, 100);
  assert.equal(table.pages.length, 4); // 3+3+3+1
  assert.deepEqual(table.pages[0], { start: 0, end: 30 });
  assert.deepEqual(table.pages[1], { start: 30, end: 60 });
  assert.deepEqual(table.pages[2], { start: 60, end: 90 });
  assert.deepEqual(table.pages[3], { start: 90, end: 100 });
  for (let i = 1; i < table.pages.length; i++) {
    assert.equal(table.pages[i - 1].end, table.pages[i].start);
  }
});

test('页表：空文本也要有一页（不能 0 页导致翻页崩溃）', () => {
  const table = buildPageTable([], 20, 0);
  assert.equal(table.pages.length, 1);
  assert.deepEqual(table.pages[0], { start: 0, end: 0 });
});

test('pageOfChar：按字符偏移反查页码（进度恢复用）', () => {
  const table = buildPageTable([10, 20, 30, 40, 50], 2, 50); // 3 页
  assert.equal(pageOfChar(table.pages, 0), 1);
  assert.equal(pageOfChar(table.pages, 19), 1);
  assert.equal(pageOfChar(table.pages, 20), 2);
  assert.equal(pageOfChar(table.pages, 39), 2);
  assert.equal(pageOfChar(table.pages, 40), 3);
  assert.equal(pageOfChar(table.pages, 49), 3);
  assert.equal(pageOfChar(table.pages, 999), 3);
});

test('排版签名：任一参数变化都必须变（否则页表会错用缓存）', () => {
  const base = layoutSignature(3, 3, 3, 390, 'sys');
  assert.equal(base, layoutSignature(3, 3, 3, 390, 'sys'));
  assert.notEqual(base, layoutSignature(4, 3, 3, 390, 'sys'));
  assert.notEqual(base, layoutSignature(3, 4, 3, 390, 'sys'));
  assert.notEqual(base, layoutSignature(3, 3, 4, 390, 'sys'));
  assert.notEqual(base, layoutSignature(3, 3, 3, 391, 'sys'));
  assert.notEqual(base, layoutSignature(3, 3, 3, 390, 'serif'));
});
