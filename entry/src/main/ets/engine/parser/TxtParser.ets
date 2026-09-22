/**
 * TXT 解析（导入时建章节索引 + **预切章落地**；阅读时只读一章）
 *
 * 设计依据：docs/v1-design.md §3 / §5 —— 解析器与排版器都是可替换实现，
 * 这里只做「TXT → 章节索引 + 取某章文本」这一件事。
 *
 * ## 内存路线（2026-09-20 定案）
 *
 * 原决策写的是"大文件不整体读入，走字节偏移索引 + 随机读"，但**从未落地**：
 * 取一章会把整本读进内存并缓存全文（JS 字符串是 UTF-16，约为文件字节的 2 倍），
 * 50MB 的 TXT 阅读时峰值可达 150MB+ —— 真机上这就是 OOM 风险。
 *
 * 现在改成 **预切章**：导入时（本来就已经整本解码过）顺手把每章正文写成
 * `books/<id>/ch/<index>.txt`（UTF-8），阅读时只读那一章 → **峰值 = 一章**（几十 KB ~ 几百 KB）。
 *
 * 为什么不用 `startByte/endByte` 直接 seek：
 *   它们是「解码后再按 UTF-8 重编码」的长度（见 ChapterSplitter），**对 GBK 文件与磁盘真实
 *   字节不一致** —— 按它 seek 会切在字符中间。要拿到真实字节偏移得再做一遍字节扫描、
 *   并把编码一起落库（DB 迁移），复杂度与风险都高于预切章。
 * 代价：磁盘约 1.5 倍（GBK 中文 2 字节 → UTF-8 3 字节）。**这是有意的空间换内存。**
 *
 * ⚠️ 导入时仍会整本读入（解析必须），峰值 ≈ 文件字节 + 解码字符串，上限见 MAX_TXT_BYTES。
 *   那是导入期的一次性代价；阅读期不再有。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { detectEncoding, EncodingGuess } from '../text/Encoding';
import { splitChapters, ChapterMeta, chapterSliceOf } from '../text/ChapterSplitter';
import { ChapterRow } from '../../common/Types';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 超过这个大小就拒绝导入（避免主线程/内存被拖死） */
export const MAX_TXT_BYTES: number = 100 * 1024 * 1024;

/** 预切章目录名（与书文件同目录） */
export const CHAPTER_DIR: string = 'ch';

/** 某本书的章文件目录 */
export function chapterDirOf(bookPath: string): string {
  const slash: number = bookPath.lastIndexOf('/');
  const dir: string = slash < 0 ? '' : bookPath.substring(0, slash + 1);
  return dir + CHAPTER_DIR;
}

/** 第 index 章的预切文件路径 */
export function chapterFilePath(bookPath: string, index: number): string {
  return chapterDirOf(bookPath) + '/' + index + '.txt';
}

// 区间切分算法在 ChapterSplitter（纯逻辑、可 CI 单测）—— 本文件只 import 使用，不再复制一份

export interface TxtParseResult {
  encoding: string;
  charCount: number;
  chapters: ChapterRow[];
}

/** 读整个文件到内存（同步）。导出给 EPUB 解析复用；超过上限抛 FILE_TOO_LARGE */
export function readAllBytes(path: string): Uint8Array {
  const stat = fs.statSync(path);
  if (stat.size <= 0) {
    throw new Error('EMPTY_FILE');
  }
  if (stat.size > MAX_TXT_BYTES) {
    throw new Error('FILE_TOO_LARGE');
  }
  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buf = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buf);
    return new Uint8Array(buf);
  } finally {
    fs.closeSync(file);
  }
}

/** 按编码解码；TextDecoder 不支持该编码时抛错，由调用方降级 */
/** 按检测出的编码解码（导出给 MarkupParser 复用 —— 解码逻辑只能有一份） */
export function decodeBytes(bytes: Uint8Array, encoding: string): string {
  const decoder = util.TextDecoder.create(encoding);
  let text = decoder.decodeToString(bytes);
  // 剥掉 BOM
  if (text.length > 0 && text.charCodeAt(0) === 0xFEFF) {
    text = text.substring(1);
  }
  return text;
}

/**
 * 解析整个 TXT：探测编码 → 解码 → 切章。
 * 同步实现（供 taskpool 调用）；结果只含章节索引，**不留全文**。
 */
export function parseTxtSync(path: string): TxtParseResult {
  const bytes = readAllBytes(path);
  const guess: EncodingGuess = detectEncoding(bytes);

  let encoding: string = guess.encoding;
  let text: string = '';
  try {
    text = decodeBytes(bytes, encoding);
  } catch (e) {
    // 兜底（家族 findings：TextDecoder 的 GB18030 支持待实测）→ 退 UTF-8，保证「能读」
    encoding = 'utf-8';
    text = decodeBytes(bytes, 'utf-8');
  }

  const chapters: ChapterMeta[] = splitChapters(text);
  const rows: ChapterRow[] = chapters.map((c: ChapterMeta) => {
    const row: ChapterRow = {
      bookId: '',
      index: c.index,
      title: c.title,
      startChar: c.startChar,
      endChar: c.endChar,
      startByte: c.startByte,
      endByte: c.endByte,
      href: ''
    };
    return row;
  });

  // 预切章：这一次读入顺手把每章落盘，阅读期就不必再整本读（见文件头「内存路线」）
  const written: number = writeChapterFiles(path, text, rows);
  if (written < rows.length) {
    // 写盘失败不是致命错：阅读时会走降级路径（整本读 + 切区间），书照样能读
    hilog.warn(DOMAIN, TAG, 'prewrite chapters: %{public}d/%{public}d written',
      written, rows.length);
  }
  return { encoding: encoding, charCount: text.length, chapters: rows };
}

/**
 * 预切章：把每章正文写成独立 UTF-8 文件。
 * 返回**成功写出的章数**；任何失败都不抛（调用方降级为整本读，书照样能读）。
 *
 * 为什么逐章 write 而不是先切出一个字符串数组：一次切出全部章正文等于在内存里
 * 再复制一整本书 —— 那正是本次要消掉的峰值。
 */
export function writeChapterFiles(bookPath: string, text: string, chapters: ChapterRow[]): number {
  const dir: string = chapterDirOf(bookPath);
  let written: number = 0;
  try {
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'mkdir chapters failed: %{public}s', JSON.stringify(e));
    return 0;
  }
  for (let i: number = 0; i < chapters.length; i++) {
    const file: string = chapterFilePath(bookPath, chapters[i].index);
    try {
      const f = fs.openSync(file, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(f.fd, chapterSliceOf(text, chapters[i].startChar, chapters[i].endChar));
      } finally {
        fs.closeSync(f);
      }
      written += 1;
    } catch (e) {
      // 单章失败不影响其它章；缺的那几章由阅读时的降级路径兜住
      hilog.error(DOMAIN, TAG, 'write chapter %{public}d failed: %{public}s',
        chapters[i].index, JSON.stringify(e));
    }
  }
  return written;
}

/** 读预切章文件；不存在 / 空 / 读失败一律返回 null（交给降级路径） */
export function readChapterFile(bookPath: string, index: number): string | null {
  const file: string = chapterFilePath(bookPath, index);
  try {
    if (!fs.accessSync(file)) {
      return null;
    }
    const stat = fs.statSync(file);
    if (stat.size <= 0) {
      return null;
    }
    const f = fs.openSync(file, fs.OpenMode.READ_ONLY);
    try {
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(f.fd, buf);
      return decodeBytes(new Uint8Array(buf), 'utf-8');
    } finally {
      fs.closeSync(f);
    }
  } catch (e) {
    return null;
  }
}

/**
 * 取某一章文本 —— **阅读路径的唯一入口**。
 *   ① 预切章文件在 → 只读这一章（内存峰值 = 一章）
 *   ② 否则降级：整本读 + 切字符区间（慢、占内存，但保证一定读得到）
 */
export function readChapterText(bookPath: string, chapter: ChapterRow): string {
  const fromFile: string | null = readChapterFile(bookPath, chapter.index);
  if (fromFile !== null) {
    return fromFile;
  }
  return readChapterTextByChars(bookPath, chapter);
}

/**
 * **降级路径**：整本读入 → 按字符区间切。
 *
 * 只在预切章文件缺失时走这里（写盘失败 / 章文件被清理掉）。**故意不做全文缓存** ——
 * 缓存全文正是本次要消掉的内存大头（UTF-16 字符串 ≈ 文件字节的 2 倍）。
 * 异常路径上慢一次，比每次阅读都吃 150MB 强。
 */
export function readChapterTextByChars(path: string, chapter: ChapterRow): string {
  const bytes: Uint8Array = readAllBytes(path);
  const guess: EncodingGuess = detectEncoding(bytes);
  let text: string = '';
  try {
    text = decodeBytes(bytes, guess.encoding);
  } catch (e) {
    text = decodeBytes(bytes, 'utf-8');
  }
  return chapterSliceOf(text, chapter.startChar, chapter.endChar);
}
