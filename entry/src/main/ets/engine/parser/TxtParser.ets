/**
 * TXT 解析（导入时建章节索引；阅读时按字节偏移随机读）
 *
 * 设计依据：docs/v1-design.md §3 / §5 —— 解析器与排版器都是可替换实现，
 * 这里只做「TXT → 章节索引 + 取某章文本」这一件事。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { detectEncoding, EncodingGuess } from '../text/Encoding';
import { splitChapters, ChapterMeta } from '../text/ChapterSplitter';
import { ChapterRow } from '../../common/Types';

/** 超过这个大小就拒绝导入（避免主线程/内存被拖死） */
export const MAX_TXT_BYTES: number = 100 * 1024 * 1024;

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
function decodeBytes(bytes: Uint8Array, encoding: string): string {
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
  return { encoding: encoding, charCount: text.length, chapters: rows };
}

/**
 * 取某一章文本 —— 按**字符偏移**从「全量解码后的文本」里切。
 *
 * 为什么不用字节偏移直接随机读？
 *   ChapterSplitter 的 startByte/endByte 是按「解码后再按 UTF-8 重编码的长度」累加的，
 *   **对 GBK 文件与磁盘真实字节不一致**（GBK 中文 2 字节，UTF-8 3 字节），按字节取会取错。
 *   v1 走字符偏移，UTF-8 / GBK 都正确。
 *
 * ponytail: 全文缓存在内存（只缓存当前这一本）。
 *   代价：大文件占内存（JS 字符串是 UTF-16，约为原文字节的 2 倍）。
 *   升级路径：真机实测大文件卡顿后，改成「按磁盘真实字节扫描建索引 + fs.read 随机读」。
 */
let cachedPath: string = '';
let cachedText: string = '';

export function loadTextCached(path: string): string {
  if (cachedPath === path && cachedText.length > 0) {
    return cachedText;
  }
  const bytes = readAllBytes(path);
  const guess: EncodingGuess = detectEncoding(bytes);
  let text: string = '';
  try {
    text = decodeBytes(bytes, guess.encoding);
  } catch (e) {
    text = decodeBytes(bytes, 'utf-8');
  }
  cachedPath = path;
  cachedText = text;
  return text;
}

export function readChapterTextByChars(path: string, startChar: number, endChar: number): string {
  const text: string = loadTextCached(path);
  const s: number = Math.max(0, Math.min(startChar, text.length));
  const e: number = Math.max(s, Math.min(endChar, text.length));
  return text.substring(s, e);
}

/** 换书/退出阅读页时调用，释放内存 */
export function clearTextCache(): void {
  cachedPath = '';
  cachedText = '';
}
