/**
 * 编码探测（纯逻辑，无 ArkUI / 无 Node 依赖 → 可在 taskpool 跑、可被 CI 单测）
 *
 * 设计依据：docs/v1-design.md §3 / §7
 * 策略：先认 BOM → 再校验 UTF-8 合法性 → 都不成立则判 GB18030（中文 TXT 的大头）
 * 兜底：调用方可在探测失败时让用户手选编码
 */

export type EncodingName = 'utf-8' | 'utf-16le' | 'utf-16be' | 'gb18030';

/**
 * 用户**手动指定**的正文编码（2026-11-05，党哥拍板选项 A）。
 *
 * 为什么需要：自动探测只到「BOM → UTF-8 合法性 → 否则 GB18030」这一步，
 * **BIG5 繁体 TXT 会静默乱码**（模拟器实测：`碷垎 纒砰いゅ`，一句提示都没有）。
 * 探测再聪明也会判错，而判错时用户唯一能自救的途径就是自己选。
 *
 * `'auto'` = 沿用导入时的自动探测（不是"没有编码"，是"交给探测"）。
 */
export type ForcedEncoding = 'auto' | 'utf-8' | 'gb18030' | 'big5';

/** 面板上的按钮顺序：自动在最前（默认项），其余按简体用户→繁体用户的常见程度排 */
export const FORCED_ENCODINGS: ForcedEncoding[] = ['auto', 'utf-8', 'gb18030', 'big5'];

/** 归一：只接受白名单值，脏值一律回 'auto'（手改过偏好库也不该把解码搞崩） */
export function normalizeEncoding(v: string): ForcedEncoding {
  if (v === 'utf-8' || v === 'gb18030' || v === 'big5') {
    return v as ForcedEncoding;
  }
  return 'auto';
}

/** 按钮上的短标签 */
export function encodingLabel(e: string): string {
  if (e === 'utf-8') {
    return 'UTF-8';
  }
  if (e === 'gb18030') {
    return 'GB18030';
  }
  if (e === 'big5') {
    return 'BIG5';
  }
  return '自动';
}

/** 说明用全称（中文用户认「简体」比认「GB18030」快） */
export function encodingHint(e: string): string {
  if (e === 'utf-8') {
    return 'UTF-8（国际通用）';
  }
  if (e === 'gb18030') {
    return 'GB18030（简体中文）';
  }
  if (e === 'big5') {
    return 'BIG5（繁体中文，港台常用）';
  }
  return '自动（按内容判断）';
}

export interface EncodingGuess {
  encoding: EncodingName;
  /** 是否带 BOM */
  bom: boolean;
  /** 置信度 0~1 */
  confidence: number;
}

/** 探测 BOM。返回 null 表示无 BOM。 */
export function detectBom(bytes: Uint8Array): EncodingName | null {
  if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
    return 'utf-8';
  }
  if (bytes.length >= 2 && bytes[0] === 0xFF && bytes[1] === 0xFE) {
    return 'utf-16le';
  }
  if (bytes.length >= 2 && bytes[0] === 0xFE && bytes[1] === 0xFF) {
    return 'utf-16be';
  }
  return null;
}

/**
 * 严格校验 bytes 是否为合法 UTF-8 序列（按 RFC 3629）。
 * 只看前 sampleSize 个字节，避免大文件全量扫描。
 */
export function isValidUtf8(bytes: Uint8Array, sampleSize: number = 65536): boolean {
  const end: number = Math.min(bytes.length, sampleSize);
  let i: number = 0;
  while (i < end) {
    const b0: number = bytes[i];
    let need: number = 0;
    let min: number = 0;
    let cp: number = 0;
    if (b0 < 0x80) {
      i += 1;
      continue;
    } else if (b0 >= 0xC2 && b0 <= 0xDF) {
      need = 1; cp = b0 & 0x1F; min = 0x80;
    } else if (b0 >= 0xE0 && b0 <= 0xEF) {
      need = 2; cp = b0 & 0x0F; min = 0x800;
    } else if (b0 >= 0xF0 && b0 <= 0xF4) {
      need = 3; cp = b0 & 0x07; min = 0x10000;
    } else {
      return false; // 0x80~0xC1、0xF5~0xFF 都是非法首字节
    }
    if (i + need >= end) {
      return true; // 样本边界截断，视为合法（不因截断误判整文件）
    }
    for (let k: number = 1; k <= need; k++) {
      const bk: number = bytes[i + k];
      if ((bk & 0xC0) !== 0x80) {
        return false;
      }
      cp = (cp << 6) | (bk & 0x3F);
    }
    if (cp < min || cp > 0x10FFFF || (cp >= 0xD800 && cp <= 0xDFFF)) {
      return false; // 过长编码 / 代理区 / 越界
    }
    i += need + 1;
  }
  return true;
}

/** 综合探测：BOM → UTF-8 校验 → GB18030 */
export function detectEncoding(bytes: Uint8Array, sampleSize: number = 65536): EncodingGuess {
  const bom: EncodingName | null = detectBom(bytes);
  if (bom !== null) {
    return { encoding: bom, bom: true, confidence: 1 };
  }
  if (isValidUtf8(bytes, sampleSize)) {
    // 纯 ASCII 文件按 UTF-8 处理也永远正确
    return { encoding: 'utf-8', bom: false, confidence: 0.95 };
  }
  return { encoding: 'gb18030', bom: false, confidence: 0.7 };
}
