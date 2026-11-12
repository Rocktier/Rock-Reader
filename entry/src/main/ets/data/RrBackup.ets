/**
 * 整库备份：一本「能搬走」的书库（本地单文件容器，零联网、零权限）
 *
 * ## 为什么做成自研容器，不用 zip
 * 仓里只有自研的 raw-deflate **解压**（EPUB/MOBI 用），没有压缩实现；
 * 引 @kit 的 zlib 会给「极致小 + 零权限」再加一条 kit 依赖。容器很简单：
 *   固定 ASCII 头 + 纯值 JSON（URI 转义后全 ASCII）+ 逐个文件的长度前缀与原始字节。
 * 书籍可能几十 MB ⇒ 一律分块顺序读写，绝不整本读进内存。
 *
 * ## 为什么数据与文件分开导
 * `books/<id>/` 里有原书、封面和 TXT 预切章，数据库里另有章节索引、
 * 进度、书签、摘录与统计。只导数据库 = 重装后书打不开；只导文件 = 目录与进度全丢。
 * 两者都进同一个容器，导入时按当前 filesDir 重建路径（重装后沙箱路径会变）。
 *
 * ## 权限
 * 只用系统文件选择器（DocumentViewPicker）让用户自己指定位置：picker 返回的 uri
 * 在本进程内可直接 fs.openSync，**不需要任何存储权限**，也不需要 INTERNET。
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { BookDb, RrColumnDef } from './BookDb';

const MAGIC: string = 'RKREADER-BACKUP-V1\n';
const SUFFIX: string = '.rkreaderbackup';
/** 所有十进制长度头统一 16 位，读端不需要猜边界 */
const LEN_WIDTH: number = 16;
const CHUNK: number = 64 * 1024;

/** 备份用到的列（S=TEXT / I=INTEGER / F=REAL），与 BookDb 的 CREATE TABLE 逐字对应 */
export interface RrTableSpec {
  name: string;
  cols: RrColumnDef[];
}

export interface RrBackupResult {
  ok: boolean;
  text: string;
}

interface RrBackupMeta {
  version: number;
  rows: Record<string, Array<Record<string, string | number>>>;
}

/** 顺序 = 导入时的写入顺序（books 要先于引用它的表） */
const RR_TABLES: RrTableSpec[] = [
  {
    name: 'books',
    cols: [
      { name: 'id', kind: 'S' }, { name: 'title', kind: 'S' },
      { name: 'author', kind: 'S' }, { name: 'format', kind: 'S' },
      { name: 'path', kind: 'S' }, { name: 'size', kind: 'I' },
      { name: 'added_at', kind: 'I' }, { name: 'last_read_at', kind: 'I' },
      { name: 'group_name', kind: 'S' }
    ]
  },
  {
    name: 'chapters',
    cols: [
      { name: 'book_id', kind: 'S' }, { name: 'idx', kind: 'I' },
      { name: 'title', kind: 'S' }, { name: 'start_char', kind: 'I' },
      { name: 'end_char', kind: 'I' }, { name: 'start_byte', kind: 'I' },
      { name: 'end_byte', kind: 'I' }, { name: 'href', kind: 'S' },
      { name: 'char_count', kind: 'I' }
    ]
  },
  {
    name: 'progress',
    cols: [
      { name: 'book_id', kind: 'S' }, { name: 'chapter_index', kind: 'I' },
      { name: 'char_offset', kind: 'I' }, { name: 'percent', kind: 'F' },
      { name: 'updated_at', kind: 'I' }
    ]
  },
  {
    name: 'read_sessions',
    cols: [
      { name: 'book_id', kind: 'S' }, { name: 'chapter_index', kind: 'I' },
      { name: 'start_at', kind: 'I' }, { name: 'end_at', kind: 'I' }
    ]
  },
  {
    name: 'bookmarks',
    cols: [
      { name: 'id', kind: 'I' }, { name: 'book_id', kind: 'S' },
      { name: 'chapter_index', kind: 'I' }, { name: 'char_offset', kind: 'I' },
      { name: 'excerpt', kind: 'S' }, { name: 'note', kind: 'S' },
      { name: 'created_at', kind: 'I' }
    ]
  },
  {
    name: 'highlights',
    cols: [
      { name: 'id', kind: 'I' }, { name: 'book_id', kind: 'S' },
      { name: 'chapter_index', kind: 'I' }, { name: 'start_char', kind: 'I' },
      { name: 'end_char', kind: 'I' }, { name: 'excerpt', kind: 'S' },
      { name: 'note', kind: 'S' }, { name: 'color', kind: 'I' },
      { name: 'created_at', kind: 'I' }
    ]
  }
];

function fixedLen(n: number): string {
  let s: string = String(Math.floor(n));
  while (s.length < LEN_WIDTH) {
    s = '0' + s;
  }
  return s;
}

function asciiOf(ab: ArrayBuffer): string {
  const u8: Uint8Array = new Uint8Array(ab);
  let out: string = '';
  for (let i: number = 0; i < u8.length; i++) {
    out += String.fromCharCode(u8[i]);
  }
  return out;
}

/** 顺序读满 n 字节（不传 offset，文件指针自己往前走） */
function readBytes(fd: number, n: number): ArrayBuffer {
  const out: Uint8Array = new Uint8Array(n);
  let got: number = 0;
  while (got < n) {
    const part: ArrayBuffer = new ArrayBuffer(n - got);
    const r: number = fs.readSync(fd, part);
    if (r <= 0) {
      break;
    }
    out.set(new Uint8Array(part).slice(0, r), got);
    got += r;
  }
  return out.buffer;
}

function readAscii(fd: number, n: number): string {
  return asciiOf(readBytes(fd, n));
}

function isDirectory(path: string): boolean {
  try {
    fs.listFileSync(path);
    return true;
  } catch (e) {
    return false;
  }
}

function ensureDir(path: string): void {
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path, true);
  }
}

/**
 * books 目录下的所有文件，返回 `books/<id>/...` 形态的相对路径。
 * 已知结构是两层（书文件 / cover.jpg 与 ch/ 章节），不引递归 API。
 */
function listBookFiles(booksDir: string): string[] {
  const out: string[] = [];
  if (!fs.accessSync(booksDir)) {
    return out;
  }
  const ids: string[] = fs.listFileSync(booksDir);
  for (let i: number = 0; i < ids.length; i++) {
    const dir1: string = booksDir + '/' + ids[i];
    if (!isDirectory(dir1)) {
      continue;
    }
    const names: string[] = fs.listFileSync(dir1);
    for (let j: number = 0; j < names.length; j++) {
      const p2: string = dir1 + '/' + names[j];
      const rel2: string = 'books/' + ids[i] + '/' + names[j];
      if (!isDirectory(p2)) {
        out.push(rel2);
        continue;
      }
      const files: string[] = fs.listFileSync(p2);
      for (let k: number = 0; k < files.length; k++) {
        const p3: string = p2 + '/' + files[k];
        if (!isDirectory(p3)) {
          out.push(rel2 + '/' + files[k]);
        }
      }
    }
  }
  return out;
}

/** 相对路径 → 当前设备的绝对路径（重装后 filesDir 会变，绝不能存绝对路径） */
function toAbsolute(ctx: common.UIAbilityContext, rel: string): string {
  return ctx.filesDir + '/' + rel;
}

/** 绝对路径 → 相对路径；本来就不是本沙箱的，原样留着 */
function toRelative(ctx: common.UIAbilityContext, absPath: string): string {
  const prefix: string = ctx.filesDir + '/';
  if (absPath.startsWith(prefix)) {
    return absPath.substring(prefix.length);
  }
  return absPath;
}

function defaultName(): string {
  const d: Date = new Date();
  const pad: (n: number) => string = (n: number): string => n < 10 ? '0' + n : String(n);
  return 'Rock阅读-书库备份-' + String(d.getFullYear()) + pad(d.getMonth() + 1) +
    pad(d.getDate()) + SUFFIX;
}

/** 结果文案里报四项数字，便于「导出 → 卸载重装 → 导入」逐项对账 */
function summaryOf(meta: RrBackupMeta, fileCount: number): string {
  const n = (t: string): number => {
    const rows: Array<Record<string, string | number>> = meta.rows[t] ?? [];
    return rows.length;
  };
  return '已还原 ' + n('books') + ' 本书、' + fileCount + ' 份文件、' +
    n('progress') + ' 条进度、' + n('bookmarks') + ' 条书签、' + n('highlights') + ' 条摘录';
}

export async function rrExportBackup(
  ctx: common.UIAbilityContext, db: BookDb
): Promise<RrBackupResult> {
  const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
  const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
  options.newFileNames = [defaultName()];
  const uris: string[] = await viewPicker.save(options);
  if (uris === undefined || uris === null || uris.length === 0) {
    return { ok: false, text: '' };
  }

  const meta: RrBackupMeta = { version: 1, rows: {} };
  for (let i: number = 0; i < RR_TABLES.length; i++) {
    meta.rows[RR_TABLES[i].name] = await db.rrDump(RR_TABLES[i].name, RR_TABLES[i].cols);
  }
  // 书记录里的 path 是绝对路径 ⇒ 转成相对（导入时按新设备的 filesDir 重建）
  const books: Array<Record<string, string | number>> = meta.rows['books'] ?? [];
  for (let i: number = 0; i < books.length; i++) {
    books[i]['path'] = toRelative(ctx, String(books[i]['path'] ?? ''));
  }

  const relFiles: string[] = listBookFiles(ctx.filesDir + '/books');
  const dst: fs.File = fs.openSync(uris[0],
    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    const fd: number = dst.fd;
    const metaText: string = encodeURIComponent(JSON.stringify(meta));
    fs.writeSync(fd, MAGIC);
    fs.writeSync(fd, fixedLen(metaText.length));
    fs.writeSync(fd, metaText);
    fs.writeSync(fd, fixedLen(relFiles.length));
    for (let i: number = 0; i < relFiles.length; i++) {
      const abs: string = ctx.filesDir + '/' + relFiles[i];
      const relText: string = encodeURIComponent(relFiles[i]);
      const size: number = fs.statSync(abs).size;
      const src: fs.File = fs.openSync(abs, fs.OpenMode.READ_ONLY);
      try {
        fs.writeSync(fd, fixedLen(relText.length));
        fs.writeSync(fd, relText);
        fs.writeSync(fd, fixedLen(size));
        let left: number = size;
        while (left > 0) {
          const want: number = Math.min(CHUNK, left);
          const buf: ArrayBuffer = new ArrayBuffer(want);
          const r: number = fs.readSync(src.fd, buf);
          if (r <= 0) {
            break;
          }
          fs.writeSync(fd, r === buf.byteLength ? buf : buf.slice(0, r));
          left -= r;
        }
      } finally {
        fs.closeSync(src);
      }
    }
  } finally {
    fs.closeSync(dst);
  }
  return {
    ok: true,
    text: '已导出 ' + books.length + ' 本书、' + relFiles.length + ' 份文件到指定位置'
  };
}

export async function rrImportBackup(
  ctx: common.UIAbilityContext, db: BookDb
): Promise<RrBackupResult> {
  const viewPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
  const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
  // ⚠️ 不能加 fileSuffixFilters：`.rkreaderbackup` 是未登记后缀，
  // 华为选择器会把这类文件**直接隐藏**（BookImporter 的 .mobi 踩过）。
  options.maxSelectNumber = 1;
  const uris: string[] = await viewPicker.select(options);
  if (uris === undefined || uris === null || uris.length === 0) {
    return { ok: false, text: '' };
  }

  const src: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
  let meta: RrBackupMeta = { version: 0, rows: {} };
  let fileCount: number = 0;
  try {
    const fd: number = src.fd;
    const magic: string = readAscii(fd, MAGIC.length);
    if (magic !== MAGIC) {
      return { ok: false, text: '导入失败：这不是 Rock阅读 的书库备份' };
    }
    const metaLen: number = Number.parseInt(readAscii(fd, LEN_WIDTH), 10);
    const metaText: string = readAscii(fd, metaLen);
    meta = JSON.parse(decodeURIComponent(metaText)) as RrBackupMeta;
    if (meta === null || meta === undefined || meta.version !== 1) {
      return { ok: false, text: '导入失败：备份版本不认识' };
    }
    fileCount = Number.parseInt(readAscii(fd, LEN_WIDTH), 10);
    if (Number.isNaN(fileCount) || fileCount < 0 || fileCount > 100000) {
      return { ok: false, text: '导入失败：备份内容不完整' };
    }

    // ① 先写文件：路径来自备份，但一律拼在**自己的** filesDir 下，不写出沙箱
    for (let i: number = 0; i < fileCount; i++) {
      const relLen: number = Number.parseInt(readAscii(fd, LEN_WIDTH), 10);
      const rel: string = decodeURIComponent(readAscii(fd, relLen));
      const dataLen: number = Number.parseInt(readAscii(fd, LEN_WIDTH), 10);
      const target: string = toAbsolute(ctx, rel);
      const slash: number = target.lastIndexOf('/');
      if (slash > 0) {
        ensureDir(target.substring(0, slash));
      }
      const dst: fs.File = fs.openSync(target,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        let left: number = dataLen;
        while (left > 0) {
          const want: number = Math.min(CHUNK, left);
          const buf: ArrayBuffer = readBytes(fd, want);
          if (buf.byteLength === 0) {
            break;
          }
          fs.writeSync(dst.fd, buf);
          left -= buf.byteLength;
        }
      } finally {
        fs.closeSync(dst);
      }
    }
  } finally {
    fs.closeSync(src);
  }

  // ② 再把行插回库：整库覆盖（导入前 UI 已告知）；path 换成当前设备的绝对路径
  const books: Array<Record<string, string | number>> = meta.rows['books'] ?? [];
  for (let i: number = 0; i < books.length; i++) {
    const rel: string = String(books[i]['path'] ?? '');
    books[i]['path'] = rel.startsWith('/') ? rel : toAbsolute(ctx, rel);
  }
  for (let i: number = 0; i < RR_TABLES.length; i++) {
    await db.rrClear(RR_TABLES[i].name);
  }
  for (let i: number = 0; i < RR_TABLES.length; i++) {
    const t: RrTableSpec = RR_TABLES[i];
    await db.rrRestore(t.name, t.cols, meta.rows[t.name] ?? []);
  }
  return { ok: true, text: summaryOf(meta, fileCount) };
}
