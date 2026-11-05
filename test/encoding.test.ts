import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  detectBom,
  detectEncoding,
  isValidUtf8,
  normalizeEncoding,
  encodingLabel,
  encodingHint,
  FORCED_ENCODINGS
} from '../entry/src/main/ets/engine/text/Encoding.ets';
// BOM 长度只有生产真源这一份：Utf8Decode.bomLengthOf（Encoding 里那份重复实现已删）
import { bomLengthOf } from '../entry/src/main/ets/engine/text/Utf8Decode.ets';

function utf8Bytes(s: string): Uint8Array {
  return new Uint8Array(Buffer.from(s, 'utf8'));
}

test('UTF-8 BOM 能被识别', () => {
  const bytes = new Uint8Array([0xEF, 0xBB, 0xBF, 0x61]);
  assert.equal(detectBom(bytes), 'utf-8');
  assert.equal(bomLengthOf(bytes), 3);
  assert.equal(detectEncoding(bytes).bom, true);
});

test('UTF-16 BOM 能被识别', () => {
  assert.equal(detectBom(new Uint8Array([0xFF, 0xFE, 0x61, 0x00])), 'utf-16le');
  assert.equal(detectBom(new Uint8Array([0xFE, 0xFF, 0x00, 0x61])), 'utf-16be');
});

test('纯 ASCII 视为合法 UTF-8', () => {
  const bytes = new Uint8Array([0x48, 0x65, 0x6C, 0x6C, 0x6F]); // "Hello"
  assert.equal(isValidUtf8(bytes), true);
  assert.equal(detectEncoding(bytes).encoding, 'utf-8');
});

test('合法中文 UTF-8 判为 utf-8', () => {
  const bytes = utf8Bytes('岩层之下，雨夜。');
  assert.equal(isValidUtf8(bytes), true);
  assert.equal(detectEncoding(bytes).encoding, 'utf-8');
  assert.equal(detectEncoding(bytes).bom, false);
});

test('GBK 字节被判为 gb18030（中文 TXT 大头）', () => {
  // "中文" 的 GBK 编码：D6 D0 CE C4
  const bytes = new Uint8Array([0xD6, 0xD0, 0xCE, 0xC4]);
  assert.equal(isValidUtf8(bytes), false);
  assert.equal(detectEncoding(bytes).encoding, 'gb18030');
});

test('非法首字节 / 截断序列不误判', () => {
  assert.equal(isValidUtf8(new Uint8Array([0x80])), false);
  assert.equal(isValidUtf8(new Uint8Array([0xFF])), false);
  // 截断在样本边界上的多字节序列不应导致整文件判为非 UTF-8
  assert.equal(isValidUtf8(new Uint8Array([0xE5, 0xB2]), 2), true);
});

test('bomLengthOf 对无 BOM 返回 0', () => {
  assert.equal(bomLengthOf(new Uint8Array([0x61, 0x62])), 0);
});

/* ---------------- 手动指定编码（2026-11-05，党哥选项 A） ----------------
 * 为什么必须有出口：自动探测的兜底是「不是 UTF-8 就当 GB18030」，
 * 而 BIG5 繁体字节同样不是合法 UTF-8 ⇒ 会被当成 GB18030 解成满屏乱码，且**一声不响**。
 * 模拟器实测原文「這是一份繁體中文測試文件」显示为「碷垎 纒砰いゅ…」。
 */

test('BIG5 字节同样落进 gb18030 —— 自动探测救不了繁体（留手动出口的理由）', () => {
  // 0xA4 是 UTF-8 的续字节，不能当首字节 ⇒ 必判非法
  const big5 = new Uint8Array([0xA4, 0xE5, 0xA4, 0x40]);
  assert.equal(isValidUtf8(big5), false);
  assert.equal(detectEncoding(big5).encoding, 'gb18030');
});

test('normalizeEncoding：白名单原样返回', () => {
  assert.equal(normalizeEncoding('auto'), 'auto');
  assert.equal(normalizeEncoding('utf-8'), 'utf-8');
  assert.equal(normalizeEncoding('gb18030'), 'gb18030');
  assert.equal(normalizeEncoding('big5'), 'big5');
});

test('normalizeEncoding：脏值一律回 auto（手改偏好库不该把解码搞崩）', () => {
  assert.equal(normalizeEncoding(''), 'auto');
  assert.equal(normalizeEncoding('gbk'), 'auto');   // 常见误写，故意不收
  assert.equal(normalizeEncoding('utf8'), 'auto');
  assert.equal(normalizeEncoding('BIG5'), 'auto');  // 大小写不宽容：存进去的一定是小写
  assert.equal(normalizeEncoding('utf-16le'), 'auto');
});

test('按钮顺序：auto 在最前（默认项），四项不重复', () => {
  assert.equal(FORCED_ENCODINGS.length, 4);
  assert.equal(FORCED_ENCODINGS[0], 'auto');
  assert.equal(new Set(FORCED_ENCODINGS).size, 4);
});

test('label 短、hint 长，且都不是空串', () => {
  for (const e of FORCED_ENCODINGS) {
    assert.notEqual(encodingLabel(e).length, 0);
    assert.notEqual(encodingHint(e).length, 0);
  }
  assert.equal(encodingLabel('big5'), 'BIG5');
  assert.equal(encodingLabel('auto'), '自动');
  // 中文用户认「繁体」比认「BIG5」快 —— hint 必须带人话
  assert.ok(encodingHint('big5').includes('繁体'));
  assert.ok(encodingHint('gb18030').includes('简体'));
});
