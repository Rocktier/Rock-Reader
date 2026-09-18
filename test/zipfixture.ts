/**
 * 测试用：在内存里现造一个**真实合法的 zip**（含正确 CRC32、真实 deflate 数据）
 *
 * 为什么不用现成的 epub 样本：那是版权书，不该进公开仓库。
 * 现造的好处是还能顺便验证"我们的 inflate 能解开真实 zlib 产出的 deflate 流"。
 * （本地另有一次对真实 epub 的手工验证，见 progress.md）
 */
import { deflateRawSync } from 'node:zlib';

export interface BuildEntry {
  name: string;
  data: Uint8Array;
  /** true = 不压缩（EPUB 的 mimetype 条目必须如此） */
  store?: boolean;
}

function crc32(data: Uint8Array): number {
  let c: number = ~0;
  for (let i: number = 0; i < data.length; i++) {
    c ^= data[i];
    for (let k: number = 0; k < 8; k++) {
      c = (c >>> 1) ^ (0xEDB88320 & -(c & 1));
    }
  }
  return (~c) >>> 0;
}

function writeU16(buf: Uint8Array, at: number, value: number): void {
  buf[at] = value & 0xFF;
  buf[at + 1] = (value >>> 8) & 0xFF;
}

function writeU32(buf: Uint8Array, at: number, value: number): void {
  buf[at] = value & 0xFF;
  buf[at + 1] = (value >>> 8) & 0xFF;
  buf[at + 2] = (value >>> 16) & 0xFF;
  buf[at + 3] = (value >>> 24) & 0xFF;
}

export function bytesOf(text: string): Uint8Array {
  return new Uint8Array(Buffer.from(text, 'utf8'));
}

export function buildZip(entries: BuildEntry[]): Uint8Array {
  const parts: Uint8Array[] = [];
  const centralParts: Uint8Array[] = [];
  const encoder = new TextEncoder();
  let offset: number = 0;

  for (let i: number = 0; i < entries.length; i++) {
    const entry: BuildEntry = entries[i];
    const store: boolean = entry.store === true;
    const nameBytes: Uint8Array = encoder.encode(entry.name);
    const crc: number = crc32(entry.data);
    const payload: Uint8Array = store
      ? entry.data
      : new Uint8Array(deflateRawSync(Buffer.from(entry.data)));

    const local: Uint8Array = new Uint8Array(30 + nameBytes.length);
    writeU32(local, 0, 0x04034b50);
    writeU16(local, 4, 20);          // version needed
    writeU16(local, 6, 0);           // flags
    writeU16(local, 8, store ? 0 : 8);
    writeU16(local, 10, 0);          // time
    writeU16(local, 12, 0x21);       // date（固定值，保证可复现）
    writeU32(local, 14, crc);
    writeU32(local, 18, payload.length);
    writeU32(local, 22, entry.data.length);
    writeU16(local, 26, nameBytes.length);
    writeU16(local, 28, 0);
    local.set(nameBytes, 30);
    parts.push(local, payload);

    const central: Uint8Array = new Uint8Array(46 + nameBytes.length);
    writeU32(central, 0, 0x02014b50);
    writeU16(central, 4, 20);        // version made by
    writeU16(central, 6, 20);        // version needed
    writeU16(central, 8, 0);         // flags
    writeU16(central, 10, store ? 0 : 8);
    writeU16(central, 12, 0);
    writeU16(central, 14, 0x21);
    writeU32(central, 16, crc);
    writeU32(central, 20, payload.length);
    writeU32(central, 24, entry.data.length);
    writeU16(central, 28, nameBytes.length);
    writeU16(central, 30, 0);        // extra
    writeU16(central, 32, 0);        // comment
    writeU16(central, 34, 0);        // disk
    writeU16(central, 36, 0);        // internal attrs
    writeU32(central, 38, 0);        // external attrs
    writeU32(central, 42, offset);   // local header offset
    central.set(nameBytes, 46);
    centralParts.push(central);

    offset += local.length + payload.length;
  }

  let centralSize: number = 0;
  for (let i: number = 0; i < centralParts.length; i++) {
    centralSize += centralParts[i].length;
  }
  const eocd: Uint8Array = new Uint8Array(22);
  writeU32(eocd, 0, 0x06054b50);
  writeU16(eocd, 4, 0);
  writeU16(eocd, 6, 0);
  writeU16(eocd, 8, entries.length);
  writeU16(eocd, 10, entries.length);
  writeU32(eocd, 12, centralSize);
  writeU32(eocd, 16, offset);
  writeU16(eocd, 20, 0);

  const all: Uint8Array[] = parts.concat(centralParts).concat([eocd]);
  let total: number = 0;
  for (let i: number = 0; i < all.length; i++) {
    total += all[i].length;
  }
  const out: Uint8Array = new Uint8Array(total);
  let at: number = 0;
  for (let i: number = 0; i < all.length; i++) {
    out.set(all[i], at);
    at += all[i].length;
  }
  return out;
}
