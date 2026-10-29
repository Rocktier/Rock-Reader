/**
 * MOBI 正文编码解码（纯逻辑，零设备 API → CI 可单测）
 *
 * 背景（2026-10-29 P0）：record0 的 offset 28 存的是 **Windows code page 编号**，
 * 但旧实现永远用 UTF-8 解码（MobiParser.ets 无条件 utf8Of）⇒ UTF-16 / GBK 的书
 * 静默解出乱码，且**零报错**，用户只会以为"这本书是坏的"。
 *
 * 分工（为什么不能全丢给设备 TextDecoder）：
 *  - UTF-8(65001) / UTF-16LE(1200) / UTF-16BE(1201) / Windows-1252(1252)
 *    → 本文件纯 TS 实现，跨 ArkTS / Node 行为一致、可单测、不依赖设备编码表。
 *  - GBK(936) / GB18030(54936) / Big5(950) / Shift-JIS(932) / EUC-KR(949)
 *    → 多字节编码交给设备 TextDecoder（TxtParser.decodeBytes）。
 *    ⚠️ 设备不支持时由调用方抛 MOBI_UNSUPPORTED_ENCODING，**绝不静默兜底成 UTF-8**
 *       —— 兜底 = 又回到"乱码书"，这正是本次要修的病根。
 */

/** record0.offset28 的常见 code page 值（MOBI 规范沿用 Windows 编号） */
export const MOBI_ENC_UTF8: number = 65001;
export const MOBI_ENC_UTF16LE: number = 1200;
export const MOBI_ENC_UTF16BE: number = 1201;
export const MOBI_ENC_CP1252: number = 1252;
export const MOBI_ENC_GBK: number = 936;
export const MOBI_ENC_GB18030: number = 54936;
export const MOBI_ENC_BIG5: number = 950;
export const MOBI_ENC_SHIFT_JIS: number = 932;
export const MOBI_ENC_EUC_KR: number = 949;

/**
 * 需要交给设备 TextDecoder 的多字节编码 → 标准编码名。
 * 纯 TS 能自己解的那四种（UTF-8/UTF-16LE/BE/cp1252）**返回空串**，
 * 由 MobiParser 走纯 TS 分支；其余返回标准名；完全不认识的返回空串
 * ⇒ MobiParser 抛 MOBI_UNSUPPORTED_ENCODING。
 */
export function deviceEncodingName(encoding: number): string {
  switch (encoding) {
    case MOBI_ENC_GBK:
      return 'gbk';
    case MOBI_ENC_GB18030:
      return 'gb18030';
    case MOBI_ENC_BIG5:
      return 'big5';
    case MOBI_ENC_SHIFT_JIS:
      return 'shift_jis';
    case MOBI_ENC_EUC_KR:
      return 'euc-kr';
    default:
      return '';
  }
}

/** UTF-16LE 解码（小端）。代理对天然由两个 UTF-16 单元承载，无需特殊处理。 */
export function decodeUtf16Le(bytes: Uint8Array): string {
  let out: string = '';
  const n: number = bytes.length;
  for (let i: number = 0; i + 1 < n; i += 2) {
    out += String.fromCharCode(bytes[i] | (bytes[i + 1] << 8));
  }
  // 剥 BOM（U+FEFF / U+FFFE 反序）
  if (out.length > 0 && (out.charCodeAt(0) === 0xFEFF || out.charCodeAt(0) === 0xFFFE)) {
    out = out.substring(1);
  }
  return out;
}

/** UTF-16BE 解码（大端）。 */
export function decodeUtf16Be(bytes: Uint8Array): string {
  let out: string = '';
  const n: number = bytes.length;
  for (let i: number = 0; i + 1 < n; i += 2) {
    out += String.fromCharCode((bytes[i] << 8) | bytes[i + 1]);
  }
  if (out.length > 0 && (out.charCodeAt(0) === 0xFEFF || out.charCodeAt(0) === 0xFFFE)) {
    out = out.substring(1);
  }
  return out;
}

/**
 * Windows-1252 解码：0x00-0x7F 与 ASCII 同、0xA0-0xFF 与 Latin-1 同，
 * 只有 0x80-0x9F 这 32 个位置有 cp1252 自己的标点/字母（€、弯引号等）。
 */
const CP1252_HIGH: number[] = [
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
];

export function decodeCp1252(bytes: Uint8Array): string {
  let out: string = '';
  for (let i: number = 0; i < bytes.length; i++) {
    const b: number = bytes[i];
    if (b >= 0x80 && b <= 0x9F) {
      out += String.fromCharCode(CP1252_HIGH[b - 0x80]);
    } else {
      out += String.fromCharCode(b);
    }
  }
  return out;
}
