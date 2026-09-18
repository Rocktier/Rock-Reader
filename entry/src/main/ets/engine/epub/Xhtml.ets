/**
 * XHTML → 纯文本（**纯 TS，零依赖 → CI 可单测**）
 *
 * 设计依据：docs/v1-design.md §1.2 —— **v1 不解析 CSS**。
 *   电子书作者写的样式（字号/颜色/行距）一律丢弃，排版参数只由我们的档位决定；
 *   这是"阅读体验可控 + 排版可测"的前提（否则每个 epub 都是一个渲染引擎）。
 *
 * 段落模型（v1）：**纯文本 + 空行分段**，不做富文本 —— 与 TXT 走同一条排版管线（Paginator）。
 *   代价：标题不会加粗变大。收益：TXT 与 EPUB 的分页/进度/设置逻辑完全复用。
 */
import { decodeEntities, stripTags } from './Xml';

/** 这些标签的**结束**位置视作一次分段（换两行） */
const BLOCK_TAGS: string[] = [
  'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'li', 'blockquote', 'tr', 'td', 'section', 'article', 'figcaption', 'dd', 'dt', 'pre'
];

function dropElements(input: string, tag: string): string {
  let out: string = input;
  let guard: number = 0;
  while (guard < 200) {
    guard += 1;
    const openRe: RegExp = new RegExp('<' + tag + '\\b[^>]*>', 'i');
    const m: RegExpMatchArray | null = out.match(openRe);
    if (m === null || m.index === undefined) {
      break;
    }
    const closeRe: RegExp = new RegExp('</' + tag + '\\s*>', 'i');
    const rest: string = out.substring(m.index + m[0].length);
    const closeMatch: RegExpMatchArray | null = rest.match(closeRe);
    if (closeMatch === null || closeMatch.index === undefined) {
      // 没有闭合标签：只把开标签丢掉，避免把后面全部正文吞掉
      out = out.substring(0, m.index) + rest;
      continue;
    }
    out = out.substring(0, m.index) + rest.substring(closeMatch.index + closeMatch[0].length);
  }
  return out;
}

function removeComments(input: string): string {
  let out: string = input;
  let guard: number = 0;
  while (guard < 500) {
    guard += 1;
    const start: number = out.indexOf('<!--');
    if (start < 0) {
      break;
    }
    const end: number = out.indexOf('-->', start);
    if (end < 0) {
      out = out.substring(0, start);
      break;
    }
    out = out.substring(0, start) + out.substring(end + 3);
  }
  return out;
}

/** 把 <br> 与块级结束标签换成换行符 */
function blockify(input: string): string {
  let out: string = input;
  out = out.replace(/<br\b[^>]*>/gi, '\n');
  for (let i: number = 0; i < BLOCK_TAGS.length; i++) {
    const tag: string = BLOCK_TAGS[i];
    const re: RegExp = new RegExp('</(?:[A-Za-z_][\\w.-]*:)?' + tag + '\\s*>', 'gi');
    out = out.replace(re, '\n\n');
  }
  return out;
}

/** 逐行清理：去首尾空白、压缩 3 个以上连续换行为 2 个 */
function normalizeLines(input: string): string {
  const lines: string[] = input.replace(/\r\n?/g, '\n').split('\n');
  const out: string[] = [];
  let blanks: number = 0;
  for (let i: number = 0; i < lines.length; i++) {
    const line: string = lines[i].replace(/[\t\u00A0\u3000 ]+/g, ' ').trim();
    if (line.length === 0) {
      blanks += 1;
      if (blanks <= 1) {
        out.push('');
      }
      continue;
    }
    blanks = 0;
    out.push(line);
  }
  // 去掉首尾空行
  while (out.length > 0 && out[0].length === 0) {
    out.shift();
  }
  while (out.length > 0 && out[out.length - 1].length === 0) {
    out.pop();
  }
  return out.join('\n');
}

export function xhtmlToText(xhtml: string): string {
  let out: string = removeComments(xhtml);
  out = dropElements(out, 'script');
  out = dropElements(out, 'style');
  out = dropElements(out, 'head');
  out = dropElements(out, 'svg');
  out = blockify(out);
  out = stripTags(out);
  out = decodeEntities(out);
  return normalizeLines(out);
}

/** 取章节内的第一个标题文本（供 EPUB 目录没用 nav/ncx 时兜底） */
export function firstHeadingOf(xhtml: string): string {
  const cleaned: string = removeComments(xhtml);
  const tags: string[] = ['h1', 'h2', 'h3', 'title'];
  for (let i: number = 0; i < tags.length; i++) {
    const openRe: RegExp = new RegExp('<(?:[A-Za-z_][\\w.-]*:)?' + tags[i] + '\\b[^>]*>', 'i');
    const m: RegExpMatchArray | null = cleaned.match(openRe);
    if (m === null || m.index === undefined) {
      continue;
    }
    const rest: string = cleaned.substring(m.index + m[0].length);
    const closeRe: RegExp = new RegExp('</(?:[A-Za-z_][\\w.-]*:)?' + tags[i] + '\\s*>', 'i');
    const closeMatch: RegExpMatchArray | null = rest.match(closeRe);
    if (closeMatch === null || closeMatch.index === undefined) {
      continue;
    }
    const text: string = decodeEntities(stripTags(rest.substring(0, closeMatch.index))).trim();
    if (text.length > 0) {
      return text;
    }
  }
  return '';
}
