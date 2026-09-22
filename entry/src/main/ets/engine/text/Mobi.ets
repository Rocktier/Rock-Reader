/**
 * MOBI / AZW3 的**纯逻辑**解析（PDB 容器 + 尾部裁剪 + PalmDOC 解压）
 *
 * 与 `parser/MobiParser.ets` 分开的原因同 `Markup.ets`：那边要读文件（fileIo），
 * 拖上它就不能在 CI 单测。**能测的部分全部放这里。**
 *
 * ## 格式速览（依据 MobileRead Wiki 的 MOBI 条目，字段偏移以它为准）
 *
 * MOBI 是 **Palm 数据库（PDB）** 容器，正文是**按 4096 字节切块的 HTML**：
 *   - PDB 头 78 字节，第 76-77 字节是记录数；之后每条记录 8 字节（offset 4 + 属性 4）
 *   - 第 0 条记录里依次是：PalmDOC Header(16B) → MOBI Header(变长) → EXTH(元数据)
 *   - 压缩：1 = 无压缩，2 = PalmDOC(LZ77 变体)，17480 = HUFF/CDIC（本版未实现）
 *   - 每条记录**末尾可能有附加数据**（extraDataFlags），不裁掉会导致解压错位 → 文末乱码
 *
 * ## 实测样本（2026-09-22，两本都是 calibre 9.0 生成）
 *
 * | | MOBI(694KB) | AZW3(839KB) |
 * |---|---|---|
 * | 压缩 | 2 PalmDOC | 2 PalmDOC |
 * | 编码 | 65001 UTF-8 | 65001 UTF-8 |
 * | extraDataFlags | 0x3 | 0x3 |
 * | 解出的正文 | HTML 3.2 | XHTML |
 * | 分章标记 | `<mbp:pagebreak/>` ×122 | `<h1>` ×245 |
 */

/** PDB 里一条记录的位置 */
export interface PdbEntry {
  offset: number;
  size: number;
}

/** record 0 里我们要用到的字段 */
export interface MobiMeta {
  /** 1=无压缩 2=PalmDOC 17480=HUFF/CDIC */
  compression: number;
  /** 0=无加密；非 0 = 有 DRM，读不了 */
  encryption: number;
  /** 未压缩正文总长度（解压后按它截断，多出来的是重叠残留） */
  textLength: number;
  /** 正文占多少条记录 */
  recordCount: number;
  recordSize: number;
  /** 65001 = UTF-8 */
  encoding: number;
  /** 第一条正文记录的编号（通常 1；实测 AZW3 样本里写了 0，所以取值时兜底为 1） */
  firstContent: number;
  /** 记录尾部附加数据标志 */
  extraFlags: number;
  /** 第一张图片的记录号（MOBI header 偏移 108）；-1 = 没有 */
  firstImageIndex: number;
  /** EXTH 201（coveroffset）：封面记录号 = firstImageIndex + coverOffset；-1 = 没有 */
  coverOffset: number;
  title: string;
  author: string;
}

export const COMPRESSION_NONE: number = 1;
export const COMPRESSION_PALMDOC: number = 2;
export const COMPRESSION_HUFF: number = 17480;

/** PDB 头固定 78 字节，其中 76-77 是记录数 */
const PDB_HEADER_BYTES: number = 78;
const RECORD_INFO_BYTES: number = 8;

function u16(b: Uint8Array, i: number): number {
  if (i + 1 >= b.length) {
    return 0;
  }
  return (b[i] << 8) | b[i + 1];
}

function u32(b: Uint8Array, i: number): number {
  if (i + 3 >= b.length) {
    return 0;
  }
  return ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]) >>> 0;
}

/**
 * UTF-8 解码（自己写而不用 util.TextDecoder：那份是 ArkTS 的，
 * 到了 Node 测试环境就没有了 —— 跨环境一致的解码只能有一份实现）
 */
export function utf8Of(bytes: Uint8Array): string {
  let out: string = '';
  let i: number = 0;
  while (i < bytes.length) {
    const c: number = bytes[i];
    if (c < 0x80) {
      out += String.fromCharCode(c);
      i += 1;
    } else if (c >= 0xC0 && c < 0xE0 && i + 1 < bytes.length) {
      out += String.fromCharCode(((c & 0x1F) << 6) | (bytes[i + 1] & 0x3F));
      i += 2;
    } else if (c >= 0xE0 && c < 0xF0 && i + 2 < bytes.length) {
      out += String.fromCharCode(((c & 0x0F) << 12) | ((bytes[i + 1] & 0x3F) << 6) | (bytes[i + 2] & 0x3F));
      i += 3;
    } else if (c >= 0xF0 && i + 3 < bytes.length) {
      const cp: number = ((c & 0x07) << 18) | ((bytes[i + 1] & 0x3F) << 12) |
        ((bytes[i + 2] & 0x3F) << 6) | (bytes[i + 3] & 0x3F);
      // 代理对（emoji 等）：拆成两个 UTF-16 单元
      const v: number = cp - 0x10000;
      out += String.fromCharCode(0xD800 + (v >> 10), 0xDC00 + (v & 0x3FF));
      i += 4;
    } else {
      i += 1;
    }
  }
  return out;
}

/** 解析 PDB 记录表（传整个文件的字节） */
export function parsePdb(bytes: Uint8Array): PdbEntry[] {
  const out: PdbEntry[] = [];
  if (bytes.length < PDB_HEADER_BYTES) {
    return out;
  }
  const n: number = u16(bytes, 76);
  for (let i: number = 0; i < n; i++) {
    const base: number = PDB_HEADER_BYTES + i * RECORD_INFO_BYTES;
    if (base + 4 > bytes.length) {
      break;
    }
    const off: number = u32(bytes, base);
    let size: number = bytes.length - off;
    if (i + 1 < n) {
      const next: number = PDB_HEADER_BYTES + (i + 1) * RECORD_INFO_BYTES;
      if (next + 4 <= bytes.length) {
        size = u32(bytes, next) - off;
      }
    }
    if (off <= bytes.length && size > 0) {
      out.push({ offset: off, size: size });
    }
  }
  return out;
}

/**
 * 从记录末尾读一个 **backward-encoded 变长整数**。
 *
 * 规范：每个字节存 7 位，**最高位那个字节带 0x80 标记**；而它写在 `<data><size>` 的
 * 末尾，所以从后往前读 —— 先读到的是低位，遇到 0x80 就结束。
 */
function readBackwardVarint(rec: Uint8Array, end: number): number {
  let pos: number = end - 1;
  let shift: number = 0;
  while (pos >= 0 && shift <= 21) {
    const b: number = rec[pos];
    shift += 7;
    pos -= 1;
    if ((b & 0x80) !== 0) {
      break;
    }
  }
  // pos+1 = 这个 size 字段的起始 = 附加数据的起点
  return pos + 1;
}

/**
 * 裁掉记录尾部的附加数据。
 *
 * 规范说"位序：entry 1 紧跟正文，entry 16 在最末"，所以**从高位往低位**剥。
 * 只认低 3 位（0x1 多字节重叠 / 0x2 索引 / 0x4 uncrossable）—— 更高的位格式不明，
 * 宁可不裁（裁错会丢正文），实测两本样本都是 0x3。
 */
export function stripTrailing(rec: Uint8Array, flags: number): Uint8Array {
  const known: number = flags & 0x0007;
  if (known === 0) {
    return rec;
  }
  let end: number = rec.length;
  for (let bit: number = 2; bit >= 0; bit--) {
    if (((known >> bit) & 1) === 0) {
      continue;
    }
    if (end <= 0) {
      break;
    }
    end = readBackwardVarint(rec, end);
    if (end <= 0) {
      return rec.subarray(0, 0);
    }
  }
  return rec.subarray(0, end);
}

/**
 * PalmDOC 解压（LZ77 变体，每个 4096 字节块独立）。
 *
 * 字节含义：
 *   0x00        → 原样输出 0
 *   0x01-0x08   → 接下来 N 个字节原样搬
 *   0x09-0x7F   → 原样输出该字节
 *   0x80-0xBF   → 两字节长度-距离对：distance = (v >> 3) & 0x7FF，length = (v & 7) + 3
 *   0xC0-0xFF   → 输出一个空格 + (c & 0x7F)
 */
export function decompressPalmDoc(src: Uint8Array): Uint8Array {
  const out: Uint8Array = new Uint8Array(src.length * 2 + 16);
  let wp: number = 0;
  let i: number = 0;
  while (i < src.length) {
    const c: number = src[i];
    i += 1;
    if (c === 0) {
      out[wp] = 0;
      wp += 1;
    } else if (c <= 8) {
      for (let k: number = 0; k < c && i < src.length; k++) {
        out[wp] = src[i];
        wp += 1;
        i += 1;
      }
    } else if (c <= 0x7F) {
      out[wp] = c;
      wp += 1;
    } else if (c <= 0xBF) {
      if (i >= src.length) {
        break;
      }
      const v: number = (c << 8) | src[i];
      i += 1;
      const dist: number = (v >> 3) & 0x7FF;
      const len: number = (v & 7) + 3;
      let from: number = wp - dist;
      if (from < 0) {
        from = 0;
      }
      for (let k: number = 0; k < len; k++) {
        if (from + k < wp) {
          out[wp] = out[from + k];
          wp += 1;
        }
      }
    } else {
      out[wp] = 0x20;
      wp += 1;
      out[wp] = c & 0x7F;
      wp += 1;
    }
    // 解压后一定比源长，但留个余量判断防止越界
    if (wp + 8 > out.length) {
      break;
    }
  }
  return out.subarray(0, wp);
}

/** EXTH 里取某个 type 的字符串（找不到返回 ''） */
function exthString(rec0: Uint8Array, start: number, end: number, type: number): string {
  let p: number = start;
  while (p + 8 <= end) {
    const t: number = u32(rec0, p);
    const l: number = u32(rec0, p + 4);
    if (l < 8 || p + l > end) {
      break;
    }
    if (t === type) {
      const s: number = p + 8;
      let e: number = p + l;
      // 数据尾部常有补零
      while (e > s && rec0[e - 1] === 0) {
        e -= 1;
      }
      return utf8Of(rec0.subarray(s, e));
    }
    p += l;
  }
  return '';
}

/** EXTH 里取某个 type 的 4 字节整数（如 201 = 封面偏移）；没有返回 -1 */
function exthU32(rec0: Uint8Array, start: number, end: number, type: number): number {
  let p: number = start;
  while (p + 8 <= end) {
    const t: number = u32(rec0, p);
    const l: number = u32(rec0, p + 4);
    if (l < 8 || p + l > end) {
      break;
    }
    if (t === type && l >= 12) {
      return u32(rec0, p + 8);
    }
    p += l;
  }
  return -1;
}

/**
 * 解析 record 0（PalmDOC Header + MOBI Header + EXTH）。
 * 缺字段一律给默认值 —— 元数据拿不到不该让整本书读不了。
 */
export function parseRecord0(rec0: Uint8Array): MobiMeta {
  const compression: number = u16(rec0, 0);
  const textLength: number = u32(rec0, 4);
  const recordCount: number = u16(rec0, 8);
  const recordSize: number = u16(rec0, 10);
  const encryption: number = u16(rec0, 12);

  let encoding: number = 65001;
  let firstContent: number = 1;
  let extraFlags: number = 0;
  let firstImageIndex: number = -1;
  let coverOffset: number = -1;
  let title: string = '';
  let author: string = '';

  if (rec0.length > 16 && rec0[16] === 0x4D && rec0[17] === 0x4F &&
      rec0[18] === 0x42 && rec0[19] === 0x49) {
    const hlen: number = u32(rec0, 20);
    if (rec0.length >= 32) {
      encoding = u32(rec0, 28);
    }
    const exthFlags: number = rec0.length >= 132 ? u32(rec0, 128) : 0;
    if (rec0.length >= 194) {
      firstContent = u16(rec0, 192);
    }
    if (rec0.length >= 112) {
      firstImageIndex = u32(rec0, 108);
      // 0xFFFFFFFF 是"未设置"的约定值
      if (firstImageIndex === 0xFFFFFFFF) {
        firstImageIndex = -1;
      }
    }
    // 实测 AZW3 样本这里写的是 0 —— 0 不是合法的正文字号（0 号是 header 本身），兜底为 1
    if (firstContent <= 0) {
      firstContent = 1;
    }
    if (rec0.length >= 244) {
      extraFlags = u32(rec0, 240);
    }
    const at: number = 16 + hlen;
    if ((exthFlags & 0x40) !== 0 && at + 12 <= rec0.length &&
        rec0[at] === 0x45 && rec0[at + 1] === 0x58 && rec0[at + 2] === 0x54 && rec0[at + 3] === 0x48) {
      const elen: number = u32(rec0, at + 4);
      const end: number = Math.min(at + elen, rec0.length);
      // 书名优先用 503（updatedtitle），没有再退 503 之外的常见位置
      title = exthString(rec0, at + 12, end, 503);
      if (title.length === 0) {
        title = exthString(rec0, at + 12, end, 505);
      }
      author = exthString(rec0, at + 12, end, 100);
      // 封面指针（实测样本 = 6）：封面记录号 = firstImageIndex + coverOffset
      coverOffset = exthU32(rec0, at + 12, end, 201);
    }
  }
  return {
    compression: compression,
    encryption: encryption,
    textLength: textLength,
    recordCount: recordCount,
    recordSize: recordSize,
    encoding: encoding,
    firstContent: firstContent,
    extraFlags: extraFlags,
    firstImageIndex: firstImageIndex,
    coverOffset: coverOffset,
    title: title,
    author: author
  };
}

/** 是否支持该压缩方式（17480 = HUFF/CDIC 本版未实现） */
export function isSupportedCompression(compression: number): boolean {
  return compression === COMPRESSION_NONE || compression === COMPRESSION_PALMDOC;
}
