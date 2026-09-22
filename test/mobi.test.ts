/**
 * MOBI / AZW3 的纯逻辑（PDB 容器 / 尾部裁剪 / PalmDOC 解压）
 *
 * 断言里的字节模式都来自**真实样本**上验证过的行为（2026-09-22 两本 calibre 生成的书）：
 * compression=2(PalmDOC)、extraDataFlags=0x3、UTF-8。
 * IO 部分（MobiParser）拖了 fileIo，只能靠真机导入验证。
 */
import { test } from 'node:test';
import assert from 'node:assert';
import {
  COMPRESSION_HUFF,
  decompressPalmDoc,
  isSupportedCompression,
  parsePdb,
  parseRecord0,
  stripTrailing,
  utf8Of
} from '../entry/src/main/ets/engine/text/Mobi.ets';

test('utf8Of：中文与 emoji（自己实现的解码，跨 ArkTS / Node 一致）', () => {
  assert.equal(utf8Of(new Uint8Array([0xE4, 0xB8, 0xAD, 0x41])), '中A');
  // U+1F600 是代理对 → 2 个 UTF-16 单元
  assert.equal(utf8Of(new Uint8Array([0xF0, 0x9F, 0x98, 0x80])).length, 2);
  assert.equal(utf8Of(new Uint8Array([])), '');
});

test('decompressPalmDoc：普通字节 / 空格前缀 / 原样搬 N 字节', () => {
  assert.equal(utf8Of(decompressPalmDoc(new Uint8Array([0x41, 0x42]))), 'AB');
  // 0xC0-0xFF → 输出一个空格 + (c & 0x7F)
  assert.equal(utf8Of(decompressPalmDoc(new Uint8Array([0xC1]))), ' A');
  // 0x01-0x08 → 接下来 N 个字节原样搬
  assert.equal(utf8Of(decompressPalmDoc(new Uint8Array([0x02, 0x41, 0x42]))), 'AB');
});

test('decompressPalmDoc：长度-距离对会重复已输出的内容', () => {
  // 0x8008 → dist = (0x8008>>3)&0x7FF = 1，len = (0x8008&7)+3 = 3 → 'A' 再补 3 个
  const out: Uint8Array = decompressPalmDoc(new Uint8Array([0x41, 0x80, 0x08]));
  assert.equal(utf8Of(out), 'AAAA');
});

test('stripTrailing：按 backward varint 剥掉记录尾部的附加数据', () => {
  const rec: Uint8Array = new Uint8Array([0x41, 0x42, 0x85]); // 末尾 0x85 = 带 0x80 标记的尺寸字节
  assert.deepEqual(Array.from(stripTrailing(rec, 0x1)), [0x41, 0x42]);
  // flags = 0 表示没有附加数据 → 一个字节都不该动
  assert.equal(stripTrailing(rec, 0).length, 3);
});

test('parsePdb：读出记录数与每条的偏移/长度', () => {
  const b: Uint8Array = new Uint8Array(300);
  b[76] = 0;
  b[77] = 2;                                          // numRecords = 2
  b[78] = 0; b[79] = 0; b[80] = 0; b[81] = 100;       // record 0 offset = 100
  b[86] = 0; b[87] = 0; b[88] = 0; b[89] = 200;       // record 1 offset = 200
  const es = parsePdb(b);
  assert.equal(es.length, 2);
  assert.equal(es[0].offset, 100);
  assert.equal(es[0].size, 100);                      // 200 - 100
  assert.equal(es[1].offset, 200);
});

test('parseRecord0：PalmDOC 头字段；没有 MOBI 头时正文默认从 1 号记录开始', () => {
  const r: Uint8Array = new Uint8Array(16);
  r[0] = 0; r[1] = 2;                                 // compression = 2 (PalmDOC)
  r[4] = 0; r[5] = 1; r[6] = 0; r[7] = 0;             // textLength = 65536
  r[8] = 0; r[9] = 126;                               // recordCount（实测 MOBI 样本值）
  const m = parseRecord0(r);
  assert.equal(m.compression, 2);
  assert.equal(m.textLength, 65536);
  assert.equal(m.recordCount, 126);
  assert.equal(m.firstContent, 1);
});

test('isSupportedCompression：HUFF/CDIC(17480) 本版明确不支持', () => {
  assert.equal(isSupportedCompression(COMPRESSION_HUFF), false);
  assert.equal(isSupportedCompression(2), true, 'PalmDOC');
  assert.equal(isSupportedCompression(1), true, '无压缩');
});
