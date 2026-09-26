/**
 * 极简 ZIP 读取器（**纯 TS，零 @ohos 依赖 → CI 可单测**）
 *
 * 用途：EPUB 就是一个 zip。我们**不整本解压到磁盘**，而是：
 *   ① 解析中央目录（central directory）拿到条目表；
 *   ② 只按需解压要用的条目（OPF / NCX / 当前章的 XHTML）。
 * 这样导入 EPUB 不产生临时文件，读一章也只解一章。
 *
 * 与 Inflate.ets 同样的取舍：自研而非 @ohos.zlib —— 自研能在 CI 里用真实 zip 测穿。
 * 明确不做：zip64、加密（EPUB 不加密）。遇到 zip64 会明确抛错，不静默读错。
 */
import { inflateRaw } from './Inflate';
import { bomLengthOf, decodeUtf8 } from '../text/Utf8Decode';

const SIG_LOCAL: number = 0x04034b50;
const SIG_CENTRAL: number = 0x02014b50;
const SIG_EOCD: number = 0x06054b50;

export interface ZipEntry {
  name: string;
  /** 0 = stored（不压缩），8 = deflate */
  method: number;
  compressedSize: number;
  uncompressedSize: number;
  localHeaderOffset: number;
}

function u16(data: Uint8Array, at: number): number {
  return data[at] | (data[at + 1] << 8);
}

function u32(data: Uint8Array, at: number): number {
  return (data[at] | (data[at + 1] << 8) | (data[at + 2] << 16) | (data[at + 3] << 24)) >>> 0;
}

/** zip 条目名解码（审查报告 B10）：
 *  GP flag bit11 = 1 → 名字是 UTF-8；否则按 cp437/latin-1 逐字节。
 *  旧版无视 flag 一律 latin-1 → 中文名 EPUB 的条目名变 mojibake，OPF 里的 UTF-8 href
 *  在 map 里查不到 → 整章静默消失。utf8 分支用本文件已 import 的 decodeUtf8。 */
function decodeName(data: Uint8Array, at: number, len: number, utf8Flag: boolean): string {
  if (utf8Flag) {
    return decodeUtf8(data.subarray(at, at + len));
  }
  let out: string = '';
  for (let i: number = 0; i < len; i++) {
    out += String.fromCharCode(data[at + i]);
  }
  return out;
}

export class ZipArchive {
  private bytes: Uint8Array;
  private entries: Map<string, ZipEntry> = new Map<string, ZipEntry>();

  private constructor(bytes: Uint8Array) {
    this.bytes = bytes;
  }

  /** 解析中央目录；不是合法 zip 就抛 BAD_ZIP_* */
  static parse(bytes: Uint8Array): ZipArchive {
    if (bytes.length < 22) {
      throw new Error('BAD_ZIP_TOO_SMALL');
    }
    // 从尾部往前找 EOCD（注释最长 65535，所以最多回看 65557 字节）
    const minPos: number = Math.max(0, bytes.length - 65557);
    let eocd: number = -1;
    for (let i: number = bytes.length - 22; i >= minPos; i--) {
      if (u32(bytes, i) === SIG_EOCD) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw new Error('BAD_ZIP_NO_EOCD');
    }

    const total: number = u16(bytes, eocd + 10);
    const cdSize: number = u32(bytes, eocd + 12);
    const cdOffset: number = u32(bytes, eocd + 16);
    if (cdOffset + cdSize > bytes.length || cdOffset >= bytes.length) {
      throw new Error('BAD_ZIP_BAD_DIRECTORY');
    }

    const archive: ZipArchive = new ZipArchive(bytes);
    let at: number = cdOffset;
    for (let i: number = 0; i < total; i++) {
      if (at + 46 > bytes.length || u32(bytes, at) !== SIG_CENTRAL) {
        throw new Error('BAD_ZIP_BAD_ENTRY');
      }
      const method: number = u16(bytes, at + 10);
      const compressedSize: number = u32(bytes, at + 20);
      const uncompressedSize: number = u32(bytes, at + 24);
      const nameLen: number = u16(bytes, at + 28);
      const extraLen: number = u16(bytes, at + 30);
      const commentLen: number = u16(bytes, at + 32);
      const localOffset: number = u32(bytes, at + 42);
      const gpFlags: number = u16(bytes, at + 8);
      const nameIsUtf8: boolean = (gpFlags & 0x800) !== 0;
      if (compressedSize === 0xFFFFFFFF || uncompressedSize === 0xFFFFFFFF || localOffset === 0xFFFFFFFF) {
        throw new Error('ZIP64_UNSUPPORTED');
      }
      const entry: ZipEntry = {
        name: decodeName(bytes, at + 46, nameLen, nameIsUtf8),
        method: method,
        compressedSize: compressedSize,
        uncompressedSize: uncompressedSize,
        localHeaderOffset: localOffset
      };
      archive.entries.set(entry.name, entry);
      at += 46 + nameLen + extraLen + commentLen;
    }
    return archive;
  }

  has(name: string): boolean {
    return this.entries.has(name);
  }

  entry(name: string): ZipEntry | null {
    const item: ZipEntry | undefined = this.entries.get(name);
    return item === undefined ? null : item;
  }

  names(): string[] {
    const out: string[] = [];
    this.entries.forEach((value: ZipEntry, key: string) => {
      out.push(key);
    });
    return out;
  }

  /** 解压一个条目；不存在抛 NO_ENTRY:<name> */
  read(name: string): Uint8Array {
    const entry: ZipEntry | undefined = this.entries.get(name);
    if (entry === undefined) {
      throw new Error('NO_ENTRY:' + name);
    }
    const lh: number = entry.localHeaderOffset;
    if (lh + 30 > this.bytes.length || u32(this.bytes, lh) !== SIG_LOCAL) {
      throw new Error('BAD_ZIP_BAD_LOCAL_HEADER');
    }
    const nameLen: number = u16(this.bytes, lh + 26);
    const extraLen: number = u16(this.bytes, lh + 28);
    const start: number = lh + 30 + nameLen + extraLen;
    const end: number = start + entry.compressedSize;
    if (end > this.bytes.length) {
      throw new Error('BAD_ZIP_TRUNCATED');
    }
    // 用中央目录里的长度（而不是本地头的长度）：带 data descriptor 的条目本地头长度是 0
    const raw: Uint8Array = this.bytes.slice(start, end);

    if (entry.method === 0) {
      return raw;
    }
    if (entry.method === 8) {
      return inflateRaw(raw);
    }
    throw new Error('ZIP_UNSUPPORTED_METHOD:' + entry.method);
  }

  /** 按 UTF-8 解成字符串（EPUB 的 XML/XHTML 都是 UTF-8） */
  readText(name: string): string {
    const bytes: Uint8Array = this.read(name);
    return decodeUtf8(bytes, bomLengthOf(bytes));
  }
}
