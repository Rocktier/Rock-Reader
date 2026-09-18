/**
 * EPUB 设备层：文件路径 → 字节 → ZipArchive（+ 单本缓存）
 *
 * 纯解析逻辑在 engine/epub/EpubParse.ets（CI 可测）；本文件只做 IO 与缓存，
 * 因此**不写任何算法**，只写"读文件、缓存、错误码"。
 *
 * 关键取舍：**不把 epub 解压到磁盘**。整本字节读进内存（上限 100MB），
 * 只按需 inflate 要用的条目 —— 不产生临时文件，读一章只解一章。
 *
 * ponytail: 同步实现（与 TXT 解析一致）。导入是用户主动等待的操作，v1 不做异步化；
 *   真机上大书若卡顿，M6 再移到 taskpool（已记入 task_list）。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { ZipArchive } from '../zip/ZipReader';
import { epubChapterTextOf, EpubParseResult, parseEpubArchive } from '../epub/EpubParse';
import { readAllBytes } from './TxtParser';

/** 单本 EPUB 上限（与 TXT 同一口径；超过先拒绝，不硬撑） */
export const MAX_EPUB_BYTES: number = 100 * 1024 * 1024;

/** 当前打开的档案（只缓存一本） */
let archivePath: string = '';
let archive: ZipArchive | null = null;
/** 章文本单条 memo：切换档位会重排同一章，避免重复 inflate */
let memoHref: string = '';
let memoText: string = '';

export function openArchive(path: string): ZipArchive {
  if (archive !== null && archivePath === path) {
    return archive;
  }
  const stat = fs.statSync(path);
  if (stat.size <= 0) {
    throw new Error('EMPTY_FILE');
  }
  if (stat.size > MAX_EPUB_BYTES) {
    throw new Error('FILE_TOO_LARGE');
  }
  const opened: ZipArchive = ZipArchive.parse(readAllBytes(path));
  archivePath = path;
  archive = opened;
  memoHref = '';
  memoText = '';
  return opened;
}

/** 解析成章节清单（导入时调用一次） */
export function parseEpub(path: string): EpubParseResult {
  return parseEpubArchive(openArchive(path));
}

/** 取某一章的正文（按需解压 + 单条 memo） */
export function readEpubChapterText(path: string, href: string): string {
  if (href.length === 0) {
    return '';
  }
  if (memoHref === href && memoText.length > 0) {
    return memoText;
  }
  const text: string = epubChapterTextOf(openArchive(path), href);
  memoHref = href;
  memoText = text;
  return text;
}

/** 取封面图片字节（书架用；v1 未接图片渲染，先留接口位） */
export function readEpubResource(path: string, href: string): Uint8Array {
  return openArchive(path).read(href);
}

export function clearEpubCache(): void {
  archivePath = '';
  archive = null;
  memoHref = '';
  memoText = '';
}
