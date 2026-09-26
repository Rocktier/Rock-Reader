/**
 * 极小 XML 读取工具（**纯 TS，零依赖 → CI 可单测**）
 *
 * 定位说明（重要，别误用）：**这不是通用 XML 解析器**。
 *   EPUB 的 container.xml / OPF / NCX / nav 都是机器生成的、结构规整的文件，
 *   我们只需要"取标签属性"和"取元素文本"两件事，用几十行扫描即可；
 *   上通用解析器（@ohos.xml）的代价是：设备才有 → CI 里无法验证。
 * 因此这里的纪律是：**只用于 EPUB 的结构文件**，出现异常一律抛错由上层降级，不静默猜。
 *
 * 支持命名空间前缀：`<opf:item>` / `<dc:title>` 都能被 `item` / `title` 命中。
 */

const NAMED_ENTITIES: Map<string, string> = new Map<string, string>([
  ['amp', '&'],
  ['lt', '<'],
  ['gt', '>'],
  ['quot', '"'],
  ['apos', '\''],
  ['nbsp', '\u00A0'],
  ['mdash', '\u2014'],
  ['ndash', '\u2013'],
  ['hellip', '\u2026'],
  ['ldquo', '\u201C'],
  ['rdquo', '\u201D'],
  ['lsquo', '\u2018'],
  ['rsquo', '\u2019'],
  ['middot', '\u00B7'],
  ['copy', '\u00A9'],
  ['trade', '\u2122'],
  ['times', '\u00D7']
]);

/** 解 XML/HTML 实体（含 &#123; 与 &#x1F; 两种数值写法） */
export function decodeEntities(input: string): string {
  if (input.indexOf('&') < 0) {
    return input;
  }
  let out: string = '';
  let i: number = 0;
  while (i < input.length) {
    const ch: string = input.charAt(i);
    if (ch !== '&') {
      out += ch;
      i += 1;
      continue;
    }
    const semi: number = input.indexOf(';', i + 1);
    if (semi < 0 || semi - i > 12) {
      out += ch;
      i += 1;
      continue;
    }
    const body: string = input.substring(i + 1, semi);
    let replaced: string | null = null;
    if (body.length > 1 && body.charAt(0) === '#') {
      const isHex: boolean = body.charAt(1) === 'x' || body.charAt(1) === 'X';
      const digits: string = isHex ? body.substring(2) : body.substring(1);
      const code: number = parseInt(digits, isHex ? 16 : 10);
      if (!Number.isNaN(code) && code > 0 && code <= 0x10FFFF) {
        replaced = code > 0xFFFF
          ? String.fromCharCode(0xD800 + ((code - 0x10000) >> 10)) +
            String.fromCharCode(0xDC00 + ((code - 0x10000) & 0x3FF))
          : String.fromCharCode(code);
      }
    } else {
      const hit: string | undefined = NAMED_ENTITIES.get(body.toLowerCase());
      replaced = hit === undefined ? null : hit;
    }
    if (replaced === null) {
      out += input.substring(i, semi + 1);
    } else {
      out += replaced;
    }
    i = semi + 1;
  }
  return out;
}

export interface TagToken {
  /** 原始标签名，可能带命名空间前缀（如 'dc:title'） */
  name: string;
  closing: boolean;
  selfClosing: boolean;
  /** 标签原文（含 `<` `>`），用于取属性 */
  text: string;
  /** 仅开标签：紧随其后的**原始**文本（到下一个 '<' 为止，未解实体） */
  innerText: string;
}

export function localNameOf(name: string): string {
  const colon: number = name.indexOf(':');
  return (colon >= 0 ? name.substring(colon + 1) : name).toLowerCase();
}

/**
 * 扫描出全部标签（按文档顺序）。
 * 这是本文件里唯一的"结构级"能力 —— NCX 的 navPoint 是**嵌套**的，
 * 按"text 与 content 顺序配对"会整章错位（真实书实测踩到），必须按结构配对。
 * 不做的事：不校验配对、不处理 CDATA（EPUB 的结构文件里没有）。
 */
export function scanTags(xml: string): TagToken[] {
  const tokens: TagToken[] = [];
  let i: number = 0;
  while (i < xml.length) {
    const lt: number = xml.indexOf('<', i);
    if (lt < 0) {
      break;
    }
    if (xml.startsWith('<!--', lt)) {
      const endComment: number = xml.indexOf('-->', lt);
      i = endComment < 0 ? xml.length : endComment + 3;
      continue;
    }
    if (xml.startsWith('<!', lt)) {
      const endDecl: number = xml.indexOf('>', lt);
      i = endDecl < 0 ? xml.length : endDecl + 1;
      continue;
    }
    const gt: number = xml.indexOf('>', lt);
    if (gt < 0) {
      break;
    }
    const raw: string = xml.substring(lt, gt + 1);
    const body: string = xml.substring(lt + 1, gt);
    const closing: boolean = body.startsWith('/');
    const selfClosing: boolean = body.endsWith('/');
    let namePart: string = closing ? body.substring(1) : body;
    if (selfClosing) {
      namePart = namePart.substring(0, namePart.length - 1);
    }
    const space: number = namePart.search(/[\s/]/);
    const name: string = space > 0 ? namePart.substring(0, space) : namePart;
    if (name.length > 0) {
      const nextLt: number = xml.indexOf('<', gt + 1);
      const inner: string = xml.substring(gt + 1, nextLt < 0 ? xml.length : nextLt);
      tokens.push({
        name: name,
        closing: closing,
        selfClosing: selfClosing,
        text: raw,
        innerText: closing ? '' : inner
      });
    }
    i = gt + 1;
  }
  return tokens;
}

/** 转义正则元字符（标签名由调用方给常量，但防御一下） */
function escapeRe(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/** 找所有开标签（含自闭合），返回标签原文数组（含属性） */
export function findTags(xml: string, tag: string): string[] {
  const re: RegExp = new RegExp('<(?:[A-Za-z_][\\w.-]*:)?' + escapeRe(tag) + '\\b[^>]*>', 'g');
  const out: string[] = [];
  let m: RegExpExecArray | null = re.exec(xml);
  while (m !== null) {
    out.push(m[0]);
    m = re.exec(xml);
  }
  return out;
}

/** 从标签原文里取属性值（支持 " 与 ' 两种引号）；取不到返回 '' */
export function attrOf(tagText: string, name: string): string {
  const pattern: string = '(?:^|[\\s])' + escapeRe(name) + '\\s*=\\s*("[^"]*"|\'[^\']*\')';
  const re: RegExp = new RegExp(pattern);
  const m: RegExpMatchArray | null = tagText.match(re);
  if (m === null) {
    return '';
  }
  const quoted: string = m[1];
  return decodeEntities(quoted.substring(1, quoted.length - 1));
}

/**
 * 取某标签的**全部元素文本**（含前缀的同类标签都算）。
 * 只处理"有闭合标签"的元素；自闭合与非闭合会被跳过 —— 对本项目的用途足够。
 */
export function findElementTexts(xml: string, tag: string): string[] {
  const out: string[] = [];
  const openRe: RegExp = new RegExp('<(?:[A-Za-z_][\\w.-]*:)?' + escapeRe(tag) + '\\b[^>]*>', 'g');
  let m: RegExpExecArray | null = openRe.exec(xml);
  while (m !== null) {
    const openTag: string = m[0];
    if (openTag.endsWith('/>')) {
      m = openRe.exec(xml);
      continue;
    }
    const closeRe: RegExp = new RegExp('</(?:[A-Za-z_][\\w.-]*:)?' + escapeRe(tag) + '\\s*>');
    const rest: string = xml.substring(m.index + openTag.length);
    const closeMatch: RegExpMatchArray | null = rest.match(closeRe);
    if (closeMatch === null || closeMatch.index === undefined) {
      m = openRe.exec(xml);
      continue;
    }
    const inner: string = rest.substring(0, closeMatch.index);
    out.push(decodeEntities(stripTags(inner)).trim());
    openRe.lastIndex = m.index + openTag.length + closeMatch.index + closeMatch[0].length;
    m = openRe.exec(xml);
  }
  return out;
}

/** 取第一个元素文本；没有返回 '' */
export function firstElementText(xml: string, tag: string): string {
  const all: string[] = findElementTexts(xml, tag);
  return all.length > 0 ? all[0] : '';
}

/** 剥掉所有标签（保留内部文本） */
export function stripTags(input: string): string {
  let out: string = '';
  let i: number = 0;
  while (i < input.length) {
    const ch: string = input.charAt(i);
    if (ch === '<') {
      const end: number = input.indexOf('>', i);
      if (end < 0) {
        // 未闭合的 '<'（审查报告 B13）：旧版直接 break，"价格 <100 元" 之后的
        // 整段正文全被吞。把 '<' 当普通文字输出，继续处理后面的内容。
        out += ch;
        i += 1;
        continue;
      }
      i = end + 1;
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

/** 去掉 `<?xml?>` / 注释 / DOCTYPE（这些会干扰简单扫描） */
export function stripProlog(xml: string): string {
  let out: string = xml;
  let idx: number = out.indexOf('<!--');
  while (idx >= 0) {
    const end: number = out.indexOf('-->', idx);
    if (end < 0) {
      break;
    }
    out = out.substring(0, idx) + out.substring(end + 3);
    idx = out.indexOf('<!--');
  }
  const declEnd: number = out.indexOf('?>');
  if (declEnd >= 0 && out.indexOf('<?xml') >= 0 && out.indexOf('<?xml') < declEnd) {
    out = out.substring(declEnd + 2);
  }
  return out;
}
