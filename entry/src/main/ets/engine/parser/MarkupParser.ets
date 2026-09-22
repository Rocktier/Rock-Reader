/**
 * HTML / Markdown / FB2 的**导入**处理（IO 部分；纯逻辑在 `../text/Markup`）
 *
 * 流程：读文件 → 检测编码 → 转成类 Markdown 纯文本 → 切章 → **预切章落盘**。
 * 落盘后磁盘上的章文件与 TXT 完全同构，所以**阅读端直接复用 `TxtSource`，
 * 阅读页对这三种格式零改动**。
 *
 * ## 与 PDF 的根本区别（记在这里，免得后人混淆）
 *
 * 这三种是**可重排**的 —— 转成文本后，字号 / 行距 / 字体 / 护眼主题照常生效。
 * PDF 是**固定版式**，要走鸿蒙 `@kit.PDFKit` 的 PdfView 另开一条路，
 * 排版设置对它**不生效**。别把它们混进同一条解析链。
 */
import { detectEncoding, EncodingGuess } from '../text/Encoding';
import { ChapterMeta } from '../text/ChapterSplitter';
import {
  decodeEntities,
  fb2ToMarkdownish,
  htmlToMarkdownish,
  splitMarkdownChapters
} from '../text/Markup';
import { firstElementText, stripTags } from '../epub/Xml';
import { decodeBytes, readAllBytes, writeChapterFiles } from './TxtParser';
import { ChapterRow } from '../../common/Types';

export interface MarkupResult {
  title: string;
  author: string;
  charCount: number;
  chapters: ChapterRow[];
}

/**
 * 解析一个标记类文件（html / md / fb2）。
 *
 * 失败由调用方兜住（书照样进书架，只是没目录）—— 与 TXT / EPUB 的处置一致。
 */
export function parseMarkupSync(path: string, kind: string): MarkupResult {
  const bytes: Uint8Array = readAllBytes(path);
  const guess: EncodingGuess = detectEncoding(bytes);
  let raw: string = '';
  try {
    raw = decodeBytes(bytes, guess.encoding);
  } catch (e) {
    raw = decodeBytes(bytes, 'utf-8');
  }

  let text: string = raw;
  let title: string = '';
  let author: string = '';
  if (kind === 'html') {
    title = decodeEntities(stripTags(firstElementText(raw, 'title'))).trim();
    text = htmlToMarkdownish(raw);
  } else if (kind === 'fb2') {
    title = decodeEntities(stripTags(firstElementText(raw, 'book-title'))).trim();
    const first: string = firstElementText(raw, 'first-name');
    const last: string = firstElementText(raw, 'last-name');
    author = (last + ' ' + first).trim();
    text = fb2ToMarkdownish(raw);
  }

  const metas: ChapterMeta[] = splitMarkdownChapters(text);
  const rows: ChapterRow[] = [];
  for (let i: number = 0; i < metas.length; i++) {
    rows.push({
      bookId: '',
      index: metas[i].index,
      title: metas[i].title,
      startChar: metas[i].startChar,
      endChar: metas[i].endChar,
      startByte: 0,
      endByte: 0,
      href: ''
    });
  }

  // 与 TXT 一样：这一次读入顺手把每章落盘，阅读期就不必再整本读
  writeChapterFiles(path, text, rows);

  if (title.length === 0 && rows.length > 0) {
    // 没有 <title> / book-title 时，用第一章的标题当书名（比文件名可读）
    title = rows[0].title;
  }
  return { title: title, author: author, charCount: text.length, chapters: rows };
}
