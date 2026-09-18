/**
 * 章节切分（纯逻辑，可 CI 单测）
 *
 * 设计依据：docs/v1-design.md §1.1 —— 默认规则 `第[X]+[章回节卷]` 行首匹配；
 * 无匹配时按固定字数兜底切章，保证任何 TXT 都能读。
 * 同时产出**字节偏移**（UTF-8）供大文件按 offset 随机读。
 */

export interface ChapterMeta {
  index: number;
  title: string;
  /** 该章在原文中的起始字符下标 */
  startChar: number;
  /** 该章结束字符下标（不含） */
  endChar: number;
  /** UTF-8 字节偏移 */
  startByte: number;
  endByte: number;
}

const CHAPTER_LINE_RE: RegExp = new RegExp(
  '^[\\s\\u3000]*(第\\s*[0-9０-９一二三四五六七八九十百千零〇两]{1,10}\\s*[章回节卷篇])(.{0,40})$'
);

/** UTF-8 编码后的字节长度（不依赖 TextEncoder，保证 ArkTS/Node 行为一致） */
export function utf8ByteLength(text: string): number {
  let n: number = 0;
  for (let i: number = 0; i < text.length; i++) {
    const c: number = text.charCodeAt(i);
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c >= 0xD800 && c <= 0xDBFF) {
      // 代理对（emoji 等）：本字符 + 低代理一起算 4 字节
      n += 4;
      i += 1;
    } else {
      n += 3;
    }
  }
  return n;
}

/** 判断某行是否章标题；是则返回标题文本，否则返回 null */
export function matchChapterTitle(line: string): string | null {
  const m: RegExpMatchArray | null = line.match(CHAPTER_LINE_RE);
  if (m === null) {
    return null;
  }
  const title: string = (m[1] + m[2]).trim();
  return title.length === 0 ? null : title;
}

/**
 * 切分章节。
 * @param text 全文
 * @param fallbackChars 找不到任何章标题时，每多少字切一章
 */
export function splitChapters(text: string, fallbackChars: number = 3000): ChapterMeta[] {
  const lines: string[] = text.split('\n');
  const chapters: ChapterMeta[] = [];

  let charPos: number = 0;
  let curStartChar: number = 0;
  let curStartByte: number = 0;
  let bytePos: number = 0;
  let curTitle: string = '';
  let started: boolean = false;

  for (let i: number = 0; i < lines.length; i++) {
    const rawLine: string = lines[i];
    const line: string = rawLine.endsWith('\r') ? rawLine.substring(0, rawLine.length - 1) : rawLine;
    const title: string | null = matchChapterTitle(line);

    if (title !== null) {
      if (started) {
        chapters.push({
          index: chapters.length,
          title: curTitle,
          startChar: curStartChar,
          endChar: charPos,
          startByte: curStartByte,
          endByte: bytePos
        });
      } else if (charPos > 0) {
        // 首个标题之前还有内容（书名/作者/前言）→ 单独成「前言」章，保证不丢字
        chapters.push({
          index: chapters.length,
          title: '前言',
          startChar: 0,
          endChar: charPos,
          startByte: 0,
          endByte: bytePos
        });
      }
      curStartChar = charPos;
      curStartByte = bytePos;
      curTitle = title;
      started = true;
    }

    // 含被 split 吃掉的 \n；末行没有 \n，且 split 尾部可能多一个空元素 → 按剩余长度夹紧
    const avail: number = text.length - charPos;
    const want: number = rawLine.length + 1;
    const lineLen: number = want <= avail ? want : (avail > 0 ? avail : 0);
    charPos += lineLen;
    bytePos += utf8ByteLength(text.substring(charPos - lineLen, charPos));
  }

  if (started) {
    chapters.push({
      index: chapters.length,
      title: curTitle,
      startChar: curStartChar,
      endChar: charPos,
      startByte: curStartByte,
      endByte: bytePos
    });
  }

  if (chapters.length > 0) {
    return chapters;
  }
  return fallbackSplit(text, fallbackChars);
}

/** 兜底：按固定字数硬切（不破坏任何内容，只是切得不好看） */
export function fallbackSplit(text: string, chunkChars: number): ChapterMeta[] {
  const chapters: ChapterMeta[] = [];
  const total: number = text.length;
  let start: number = 0;
  let byteStart: number = 0;
  while (start < total) {
    const end: number = Math.min(start + chunkChars, total);
    const slice: string = text.substring(start, end);
    const bytes: number = utf8ByteLength(slice);
    chapters.push({
      index: chapters.length,
      title: '第 ' + (chapters.length + 1) + ' 节',
      startChar: start,
      endChar: end,
      startByte: byteStart,
      endByte: byteStart + bytes
    });
    start = end;
    byteStart += bytes;
  }
  return chapters;
}
