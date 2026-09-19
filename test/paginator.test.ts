/**
 * 排版器契约与页表缓存（纯逻辑，CI 可跑）
 * 设计依据：docs/v1-design.md §3 / §9 —— CI 无模拟器，靠注入假实现把链路测穿。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FakePaginator, LayoutBox, PageCache } from '../entry/src/main/ets/engine/paginator/Paginator.ets';

function box(signature: string): LayoutBox {
  return { fontSizePx: 42, lineHeightPx: 80, widthPx: 900, heightPx: 1400, fontFamily: '', fontPath: '', fontWeight: 400, signature };
}

test('FakePaginator：按固定字数切页，页与页首尾相接且不漏字', () => {
  const text = 'x'.repeat(1250);
  const table = new FakePaginator(500).paginate(text, box('sig'));
  assert.equal(table.pages.length, 3);
  assert.deepEqual(table.pages[0], { start: 0, end: 500 });
  assert.deepEqual(table.pages[2], { start: 1000, end: 1250 });
  assert.equal(table.totalChars, 1250);
  assert.equal(table.signature, 'sig', '签名必须原样带出，否则缓存键会错');
  for (let i = 1; i < table.pages.length; i++) {
    assert.equal(table.pages[i - 1].end, table.pages[i].start);
  }
});

test('FakePaginator：空文本也要有一页（翻页不能因此崩）', () => {
  const table = new FakePaginator(500).paginate('', box('s'));
  assert.equal(table.pages.length, 1);
  assert.deepEqual(table.pages[0], { start: 0, end: 0 });
});

test('PageCache：命中则返回同一页表，未命中返回 null', () => {
  const cache = new PageCache(2);
  assert.equal(cache.get('a'), null);
  const table = new FakePaginator(10).paginate('0123456789', box('a'));
  cache.put('a', table);
  assert.equal(cache.get('a'), table);
});

test('PageCache：超出容量按插入顺序淘汰最旧的（LRU 语义，防止内存无限涨）', () => {
  const cache = new PageCache(2);
  const t = new FakePaginator(10).paginate('0123456789', box('k'));
  cache.put('k1', t);
  cache.put('k2', t);
  cache.put('k3', t); // 挤掉 k1
  assert.equal(cache.get('k1'), null);
  assert.notEqual(cache.get('k2'), null);
  assert.notEqual(cache.get('k3'), null);
});

test('PageCache：重复 put 同一个 key 不重复占用容量', () => {
  const cache = new PageCache(1);
  const t = new FakePaginator(10).paginate('0123456789', box('k'));
  cache.put('k', t);
  cache.put('k', t);
  cache.put('m', t); // 若上面重复计数，k 会被提前挤掉
  assert.notEqual(cache.get('m'), null);
});
