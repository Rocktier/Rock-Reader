/**
 * MOBI 正文编码解码单测（纯逻辑；对应 P0 2026-10-29 "encoding 字段解析了却没用"缺陷）
 *
 * 旧实现：parseRecord0 解出 meta.encoding，MobiParser 却无条件 utf8Of ⇒ UTF-16/GBK
 * 书静默乱码。这里锁住"按 code page 分派"的纯 TS 部分（UTF-8/16/cp1252），
 * 设备 TextDecoder 那几张多字节表留给真机验证。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  decodeCp1252,
  decodeUtf16Be,
  decodeUtf16Le,
  deviceEncodingName,
  MOBI_ENC_BIG5,
  MOBI_ENC_CP1252,
  MOBI_ENC_EUC_KR,
  MOBI_ENC_GB18030,
  MOBI_ENC_GBK,
  MOBI_ENC_SHIFT_JIS,
  MOBI_ENC_UTF16BE,
  MOBI_ENC_UTF16LE,
  MOBI_ENC_UTF8
} from '../entry/src/main/ets/engine/text/MobiEncoding.ets';

test('常量：code page 编号与 MOBI 规范一致', () => {
  assert.equal(MOBI_ENC_UTF8, 65001);
  assert.equal(MOBI_ENC_UTF16LE, 1200);
  assert.equal(MOBI_ENC_UTF16BE, 1201);
  assert.equal(MOBI_ENC_CP1252, 1252);
  assert.equal(MOBI_ENC_GBK, 936);
  assert.equal(MOBI_ENC_GB18030, 54936);
  assert.equal(MOBI_ENC_BIG5, 950);
  assert.equal(MOBI_ENC_SHIFT_JIS, 932);
  assert.equal(MOBI_ENC_EUC_KR, 949);
});

test('decodeUtf16Le：小端 + 中文 + 剥 BOM', () => {
  // '中'=U+4E2D → 2D 4E；'A'=U+0041 → 41 00
  assert.equal(decodeUtf16Le(new Uint8Array([0x2D, 0x4E, 0x41, 0x00])), '中A');
  // FF FE 是 UTF-16LE BOM，应剥掉
  assert.equal(decodeUtf16Le(new Uint8Array([0xFF, 0xFE, 0x41, 0x00])), 'A');
  assert.equal(decodeUtf16Le(new Uint8Array([])), '');
});

test('decodeUtf16Be：大端 + 中文 + 剥 BOM', () => {
  assert.equal(decodeUtf16Be(new Uint8Array([0x4E, 0x2D, 0x00, 0x41])), '中A');
  assert.equal(decodeUtf16Be(new Uint8Array([0xFE, 0xFF, 0x00, 0x41])), 'A');
  assert.equal(decodeUtf16Be(new Uint8Array([])), '');
});

test('decodeUtf16Le/Be：奇数长度末字节不成对 → 忽略，不崩', () => {
  assert.equal(decodeUtf16Le(new Uint8Array([0x41, 0x00, 0x42])), 'A');
  assert.equal(decodeUtf16Be(new Uint8Array([0x00, 0x41, 0x42])), 'A');
});

test('decodeCp1252：ASCII 直通 + 0x80-0x9F 特殊字符（€、弯引号）', () => {
  // 0x41='A'  0x80=€(U+20AC)  0x93=“(U+201C)  0xFF=ÿ(U+00FF)
  assert.equal(decodeCp1252(new Uint8Array([0x41, 0x80, 0x93, 0xFF])), 'A€“ÿ');
  assert.equal(decodeCp1252(new Uint8Array([0x48, 0x69])), 'Hi');
});

test('deviceEncodingName：多字节编码交设备；纯 TS 能解/未知的返回空串', () => {
  assert.equal(deviceEncodingName(MOBI_ENC_GBK), 'gbk');
  assert.equal(deviceEncodingName(MOBI_ENC_GB18030), 'gb18030');
  assert.equal(deviceEncodingName(MOBI_ENC_BIG5), 'big5');
  assert.equal(deviceEncodingName(MOBI_ENC_SHIFT_JIS), 'shift_jis');
  assert.equal(deviceEncodingName(MOBI_ENC_EUC_KR), 'euc-kr');
  // 这四种由纯 TS 分支处理，不进设备解码
  assert.equal(deviceEncodingName(MOBI_ENC_UTF8), '');
  assert.equal(deviceEncodingName(MOBI_ENC_UTF16LE), '');
  assert.equal(deviceEncodingName(MOBI_ENC_CP1252), '');
  // 完全不认识的 code page → 空串 ⇒ MobiParser 抛 MOBI_UNSUPPORTED_ENCODING
  assert.equal(deviceEncodingName(99999), '');
});
