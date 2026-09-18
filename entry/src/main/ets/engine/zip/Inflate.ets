/**
 * raw DEFLATE 解压（RFC 1951）—— **纯 TS，零 @ohos 依赖 → CI 可单测**
 *
 * 为什么自研而不是用 @ohos.zlib：
 *   zlib 只在设备上可用，本机与 CI 都验不了；EPUB 解包是 v1 硬需求，
 *   而"验不了"正是这个项目最大的风险（本机无鸿蒙环境）。
 *   自研后，CI 里可以用 Node 的 deflateRawSync 造真实压缩数据做回归 —— 见 test/zip.test.ts。
 *
 * ponytail: 只实现解压（EPUB 只需要读），不做压缩；不做 zip64。
 * 参考：RFC 1951 的经典 puff 结构（counts/symbols + 逐位解码），实现为自写。
 */

/** 位读取器：DEFLATE 是 LSB-first */
class BitReader {
  private data: Uint8Array;
  private pos: number = 0;
  private buf: number = 0;
  private cnt: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  /** 读 n 位（n ≤ 16） */
  bits(n: number): number {
    while (this.cnt < n) {
      const byte: number = this.pos < this.data.length ? this.data[this.pos] : 0;
      this.pos += 1;
      this.buf |= byte << this.cnt;
      this.cnt += 8;
    }
    const value: number = this.buf & ((1 << n) - 1);
    this.buf >>>= n;
    this.cnt -= n;
    return value;
  }

  /** 丢弃到字节边界（stored block 用） */
  alignToByte(): void {
    const drop: number = this.cnt & 7;
    this.buf >>>= drop;
    this.cnt -= drop;
  }

  /** 字节对齐后的直接取字节 */
  byteAligned(): number {
    if (this.cnt >= 8) {
      const value: number = this.buf & 0xFF;
      this.buf >>>= 8;
      this.cnt -= 8;
      return value;
    }
    const value: number = this.pos < this.data.length ? this.data[this.pos] : 0;
    this.pos += 1;
    return value;
  }
}

interface HuffTable {
  counts: number[];
  symbols: number[];
}

/** 由码长数组构建规范 Huffman 表 */
function buildTable(lengths: number[]): HuffTable {
  const counts: number[] = new Array<number>(16).fill(0);
  for (let i: number = 0; i < lengths.length; i++) {
    counts[lengths[i]] += 1;
  }
  counts[0] = 0;
  const offsets: number[] = new Array<number>(16).fill(0);
  let total: number = 0;
  for (let len: number = 1; len < 16; len++) {
    offsets[len] = total;
    total += counts[len];
  }
  const symbols: number[] = new Array<number>(total).fill(0);
  for (let s: number = 0; s < lengths.length; s++) {
    const len: number = lengths[s];
    if (len !== 0) {
      symbols[offsets[len]] = s;
      offsets[len] += 1;
    }
  }
  return { counts: counts, symbols: symbols };
}

/** 逐位解码一个符号 */
function decodeSymbol(reader: BitReader, table: HuffTable): number {
  let code: number = 0;
  let first: number = 0;
  let index: number = 0;
  for (let len: number = 1; len < 16; len++) {
    code |= reader.bits(1);
    const count: number = table.counts[len];
    if (code - first < count) {
      return table.symbols[index + (code - first)];
    }
    index += count;
    first = (first + count) << 1;
    code <<= 1;
  }
  throw new Error('INFLATE_BAD_CODE');
}

const LENGTH_BASE: number[] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
  35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
];
const LENGTH_EXTRA: number[] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
  3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
];
const DIST_BASE: number[] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
  257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
];
const DIST_EXTRA: number[] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
  7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
];
/** 动态块里码长表本身的传输顺序（RFC 1951 §3.2.7） */
const CL_ORDER: number[] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15];

function fixedTables(): HuffTable[] {
  const litLengths: number[] = new Array<number>(288).fill(0);
  for (let i: number = 0; i < 144; i++) {
    litLengths[i] = 8;
  }
  for (let i: number = 144; i < 256; i++) {
    litLengths[i] = 9;
  }
  for (let i: number = 256; i < 280; i++) {
    litLengths[i] = 7;
  }
  for (let i: number = 280; i < 288; i++) {
    litLengths[i] = 8;
  }
  const distLengths: number[] = new Array<number>(30).fill(5);
  return [buildTable(litLengths), buildTable(distLengths)];
}

/** 读一个动态块的码长表并构建 lit/dist 两张表 */
function dynamicTables(reader: BitReader): HuffTable[] {
  const hlit: number = reader.bits(5) + 257;
  const hdist: number = reader.bits(5) + 1;
  const hclen: number = reader.bits(4) + 4;

  const clLengths: number[] = new Array<number>(19).fill(0);
  for (let i: number = 0; i < hclen; i++) {
    clLengths[CL_ORDER[i]] = reader.bits(3);
  }
  const clTable: HuffTable = buildTable(clLengths);

  const lengths: number[] = new Array<number>(hlit + hdist).fill(0);
  let i: number = 0;
  while (i < hlit + hdist) {
    const sym: number = decodeSymbol(reader, clTable);
    if (sym < 16) {
      lengths[i] = sym;
      i += 1;
    } else if (sym === 16) {
      // 重复上一个码长 3~6 次
      if (i === 0) {
        throw new Error('INFLATE_BAD_REPEAT');
      }
      const prev: number = lengths[i - 1];
      const repeat: number = 3 + reader.bits(2);
      for (let k: number = 0; k < repeat && i < lengths.length; k++) {
        lengths[i] = prev;
        i += 1;
      }
    } else if (sym === 17) {
      const repeat: number = 3 + reader.bits(3);
      for (let k: number = 0; k < repeat && i < lengths.length; k++) {
        lengths[i] = 0;
        i += 1;
      }
    } else {
      const repeat: number = 11 + reader.bits(7);
      for (let k: number = 0; k < repeat && i < lengths.length; k++) {
        lengths[i] = 0;
        i += 1;
      }
    }
  }
  const litLengths: number[] = lengths.slice(0, hlit);
  const distLengths: number[] = lengths.slice(hlit, hlit + hdist);
  return [buildTable(litLengths), buildTable(distLengths)];
}

/**
 * 解压 raw deflate 数据（不含 zlib/gzip 头）。
 * @throws INFLATE_* 系列错误，由调用方决定兜底
 */
export function inflateRaw(input: Uint8Array): Uint8Array {
  const reader: BitReader = new BitReader(input);
  let out: Uint8Array = new Uint8Array(Math.max(1024, input.length * 4));
  let outLen: number = 0;

  const ensure = (extra: number): void => {
    if (outLen + extra <= out.length) {
      return;
    }
    let size: number = out.length * 2;
    while (size < outLen + extra) {
      size *= 2;
    }
    const grown: Uint8Array = new Uint8Array(size);
    grown.set(out.slice(0, outLen), 0);
    out = grown;
  };

  let final: number = 0;
  while (final === 0) {
    final = reader.bits(1);
    const type: number = reader.bits(2);

    if (type === 0) {
      // stored：字节对齐后跟 LEN / NLEN
      reader.alignToByte();
      const len: number = reader.byteAligned() | (reader.byteAligned() << 8);
      reader.byteAligned();
      reader.byteAligned();
      ensure(len);
      for (let i: number = 0; i < len; i++) {
        out[outLen] = reader.byteAligned();
        outLen += 1;
      }
      continue;
    }

    if (type === 3) {
      throw new Error('INFLATE_BAD_BLOCK_TYPE');
    }

    const tables: HuffTable[] = type === 1 ? fixedTables() : dynamicTables(reader);
    const litTable: HuffTable = tables[0];
    const distTable: HuffTable = tables[1];

    while (true) {
      const sym: number = decodeSymbol(reader, litTable);
      if (sym < 256) {
        ensure(1);
        out[outLen] = sym;
        outLen += 1;
        continue;
      }
      if (sym === 256) {
        break;
      }
      const li: number = sym - 257;
      if (li < 0 || li >= LENGTH_BASE.length) {
        throw new Error('INFLATE_BAD_LENGTH_CODE');
      }
      const length: number = LENGTH_BASE[li] + reader.bits(LENGTH_EXTRA[li]);
      const dsym: number = decodeSymbol(reader, distTable);
      if (dsym >= DIST_BASE.length) {
        throw new Error('INFLATE_BAD_DIST_CODE');
      }
      const distance: number = DIST_BASE[dsym] + reader.bits(DIST_EXTRA[dsym]);
      if (distance > outLen) {
        throw new Error('INFLATE_DIST_TOO_FAR');
      }
      ensure(length);
      let from: number = outLen - distance;
      for (let k: number = 0; k < length; k++) {
        out[outLen] = out[from];
        outLen += 1;
        from += 1;
      }
    }
  }

  return out.slice(0, outLen);
}
