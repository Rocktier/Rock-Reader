import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  bomLength,
  detectBom,
  detectEncoding,
  isValidUtf8
} from '../entry/src/main/ets/engine/text/Encoding.ets';

function utf8Bytes(s: string): Uint8Array {
  return new Uint8Array(Buffer.from(s, 'utf8'));
}

test('UTF-8 BOM 能被识别', () => {
  const bytes = new Uint8Array([0xEF, 0xBB, 0xBF, 0x61]);
  assert.equal(detectBom(bytes), 'utf-8');
  assert.equal(bomLength(bytes), 3);
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

test('bomLength 对无 BOM 返回 0', () => {
  assert.equal(bomLength(new Uint8Array([0x61, 0x62])), 0);
});
