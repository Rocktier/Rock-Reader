/**
 * HTML / Markdown / FB2 的**纯逻辑**处理（转纯文本 + 切章）
 *
 * 为什么与 `parser/MarkupParser.ets` 分开：那边要读写文件（`fileIo`），
 * 一旦拖上它就不能在 CI 里单测（Node 没有 @kit.CoreFileKit）。
 * 所以"能测的部分"全部放这里 —— 与 `ChapterSplitter` 同样的道理。
 *
 * 统一思路：三种格式都转成"**类 Markdown 纯文本**"（标题行 = `# ...`），
 * 之后切章、落盘、阅读、进度全部复用 TXT 那一条链。
 */
import { ChapterMeta, splitChapters } from './ChapterSplitter';
import { stripTags } from '../epub/Xml';

/** Markdown 标题行：`#` ~ `######` + 空格 + 标题文字（允许行尾的闭合 #） */
const MD_HEADING_RE: RegExp = new RegExp('^[ \\t]*(#{1,6})[ \\t]+(.+?)[ \\t]*#*[ \\t]*$');

/** 一个标题都没有时按多少字硬切一章（与 TXT 兜底保持一致） */
const FALLBACK_CHARS: number = 3000;

/** 去掉 `<tag ...>...</tag>` 整块（script / style / head 不该进正文） */
function removeBlocks(html: string, tag: string): string {
  const re: RegExp = new RegExp('<' + tag + '\\b[^>]*>[\\s\\S]*?</' + tag + '\\s*>', 'gi');
  return html.replace(re, '');
}

/**
 * 解码数字实体（`&#123;` / `&#x1F600;`）。
 * 手扫而不是用 `replace` 回调：ArkTS 里函数式替换的写法不划算，扫一遍更直白。
 */
function decodeNumeric(s: string): string {
  let out: string = '';
  let i: number = 0;
  while (i < s.length) {
    const amp: number = s.indexOf('&#', i);
    if (amp < 0) {
      out += s.substring(i);
      break;
    }
    out += s.substring(i, amp);
    const semi: number = s.indexOf(';', amp);
    // 实体体部长得离谱就不是实体了（避免把正常的 "&#" 文本吃掉）
    if (semi < 0 || semi - amp > 12) {
      out += s.substring(amp, amp + 2);
      i = amp + 2;
      continue;
    }
    const body: string = s.substring(amp + 2, semi);
    let code: number = -1;
    if (body.length > 1 && (body.charAt(0) === 'x' || body.charAt(0) === 'X')) {
      code = parseInt(body.substring(1), 16);
    } else {
      code = parseInt(body, 10);
    }
    if (code > 0 && code < 0x110000) {
      out += String.fromCharCode(code);
    } else {
      out += s.substring(amp, semi + 1);
    }
    i = semi + 1;
  }
  return out;
}

/**
 * 解码常见命名实体。
 * 只列书里真会遇到的那几个 —— 全表几百项，漏掉的生僻实体只是显示成原文，不影响阅读。
 */
export function decodeEntities(s: string): string {
  let out: string = s;
  out = out.replace(/&nbsp;/g, ' ');
  out = out.replace(/&amp;/g, '&');
  out = out.replace(/&lt;/g, '<');
  out = out.replace(/&gt;/g, '>');
  out = out.replace(/&quot;/g, '"');
  out = out.replace(/&#39;/g, "'");
  out = out.replace(/&apos;/g, "'");
  out = out.replace(/&mdash;/g, '—');
  out = out.replace(/&ldquo;/g, '“');
  out = out.replace(/&rdquo;/g, '”');
  out = out.replace(/&hellip;/g, '…');
  return decodeNumeric(out);
}

/**
 * HTML → 类 Markdown 纯文本。
 *
 * 关键一步是**在去标签之前**把 `h1/h2/h3` 改写成 `#` 标题行 —— 一旦 `stripTags`
 * 把标签全剥掉，标题和普通段落就再没区别，切章也就无从下手。
 */
export function htmlToMarkdownish(html: string): string {
  let s: string = html;
  s = removeBlocks(s, 'script');
  s = removeBlocks(s, 'style');
  s = removeBlocks(s, 'head');
  s = s.replace(/<!--[\s\S]*?-->/g, '');
  // 标题 → Markdown 标题行（必须在 stripTags 之前）
  s = s.replace(/<h1\b[^>]*>/gi, '\n# ');
  s = s.replace(/<h2\b[^>]*>/gi, '\n## ');
  s = s.replace(/<h3\b[^>]*>/gi, '\n### ');
  // **MOBI(KF7) 没有 h1-h3** —— 它用 `<mbp:pagebreak/>` 分章（实测样本 ×122）。
  // 不认它，MOBI 就一个标题都没有 → 只能退化成按字数硬切。
  s = s.replace(/<mbp:pagebreak\s*\/?>/gi, '\n# ');
  // 块级结构 → 换行（否则整本书会粘成一坨）
  s = s.replace(/<br\s*\/?>/gi, '\n');
  s = s.replace(/<\/(p|div|li|tr|blockquote|section|article|h[1-6])\s*>/gi, '\n');
  s = decodeEntities(stripTags(s));
  // 压掉缩进产生的行尾空白与连续空行（保留段落间的一个空行）
  s = s.replace(/[ \t]+\n/g, '\n');
  // pagebreak 后面常跟一个空段落占位（实测样本里每个都有），会让 `# ` 后面直接换行
  // → 章名为空。把这种换行吃掉，让真正的章名接上来。
  s = s.replace(/#([ \t]*)\n+/g, '# ');
  s = s.replace(/\n{3,}/g, '\n\n');
  return s;
}

/**
 * FB2（FictionBook XML）→ 类 Markdown 纯文本。
 *
 * FB2 结构是 `<body><section><title><p>章名</p></title><p>正文</p>…`，
 * 所以按"title → `#` 标题行、p → 段落"扫一遍即可。
 * **嵌套 section（子章节）在本版不单独成章**，会并进父章 —— 记在这里：
 * FB2 在中文书里本就罕见，等真遇到需要再说。
 */
export function fb2ToMarkdownish(xml: string): string {
  // 标签名后必须是 `>` 或空白 —— 写成 `\b[^>]*>` 的话，`<title-info>`（FB2 的元数据块）
  // 也会被当成 `<title>`，于是整段 description 被当成章节标题、真正的章名反被跳过。
  const re: RegExp = new RegExp('<(title|p)(?:\\s[^>]*)?>([\\s\\S]*?)</\\1\\s*>', 'gi');
  let out: string = '';
  let m: RegExpExecArray | null = re.exec(xml);
  while (m !== null) {
    const isTitle: boolean = m[1].toLowerCase() === 'title';
    // 内层可能还有 <emphasis> / <strong> 之类，先剥掉再取文字
    const plain: string = decodeEntities(stripTags(m[2])).trim();
    if (plain.length > 0) {
      out += (isTitle ? '# ' : '') + plain + '\n\n';
    }
    m = re.exec(xml);
  }
  return out;
}

/** 按 Markdown 标题行切章；一个标题都没有时返回空数组（交给调用方兜底） */
function splitByMarkdownHeadings(text: string): ChapterMeta[] {
  const starts: number[] = [];
  const titles: string[] = [];
  let start: number = 0;
  while (start <= text.length) {
    let end: number = text.indexOf('\n', start);
    if (end < 0) {
      end = text.length;
    }
    const line: string = text.substring(start, end);
    const m: RegExpMatchArray | null = line.match(MD_HEADING_RE);
    if (m !== null) {
      const t: string = m[2].trim();
      if (t.length > 0) {
        starts.push(start);
        titles.push(t);
      }
    }
    if (end >= text.length) {
      break;
    }
    start = end + 1;
  }
  if (starts.length === 0) {
    return [];
  }

  const out: ChapterMeta[] = [];
  // 第一个标题之前的实质文字（前言 / 简介）留成独立一章，别丢
  if (starts[0] > 0 && text.substring(0, starts[0]).trim().length > 0) {
    out.push({ index: 0, title: '前言', startChar: 0, endChar: starts[0], startByte: 0, endByte: 0 });
  }
  for (let i: number = 0; i < starts.length; i++) {
    const s: number = starts[i];
    const e: number = i + 1 < starts.length ? starts[i + 1] : text.length;
    out.push({
      index: out.length,
      title: titles[i],
      startChar: s,
      endChar: e,
      // 字节偏移这几种格式用不上（不做磁盘 seek，见 ChapterSplitter 文件头），留 0
      startByte: 0,
      endByte: 0
    });
  }
  return out;
}

/**
 * 切章：优先按 Markdown 标题；一个标题都没有就**整份退回 TXT 那套**
 * （中文"第N章"规则 + 再不行按字数硬切）—— 保证任何文件都能读，不会白导入。
 */
export function splitMarkdownChapters(text: string): ChapterMeta[] {
  const byHeading: ChapterMeta[] = splitByMarkdownHeadings(text);
  if (byHeading.length > 0) {
    return byHeading;
  }
  return splitChapters(text, FALLBACK_CHARS);
}
