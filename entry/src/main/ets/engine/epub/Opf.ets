/**
 * EPUB 结构解析：container.xml / OPF / NCX / Nav（**纯 TS，零依赖 → CI 可单测**）
 *
 * 只做 EPUB 规范里必需的四件事：
 *   ① container.xml → OPF 路径
 *   ② OPF → 书名/作者/manifest/spine/封面
 *   ③ NCX（EPUB2）或 nav.xhtml（EPUB3）→ 章节标题
 *   ④ 相对路径解析（含 ../、%20、#fragment）
 * 一律不猜：结构不对就抛错，由上层降级（"EPUB 非标准 → 明确提示，不崩"）。
 */
import {
  attrOf,
  decodeEntities,
  findTags,
  firstElementText,
  localNameOf,
  scanTags,
  stripProlog,
  stripTags,
  TagToken
} from './Xml';

export interface ManifestItem {
  id: string;
  href: string;
  mediaType: string;
  properties: string;
}

export interface EpubPackage {
  title: string;
  author: string;
  /** OPF 所在目录（'' 或 'OEBPS/'），用于把 href 解析成 zip 内路径 */
  opfDir: string;
  items: ManifestItem[];
  /** spine 的 idref 顺序 */
  spine: string[];
  /**
   * spine 里标了 `linear="no"` 的 manifest id 集合。
   * EPUB 规范：`linear="no"` 表示该文档**不属于线性阅读顺序** —— 目录页 / 版权页 /
   * 彩插 / 附录常这么标。此前完全没读这个属性，所以这一整类页面照旧排进了正文流。
   */
  spineNoLinear: Set<string>;
  /** EPUB2 `guide` 里 `<reference type="toc">` 指向的 zip 内路径；'' = 没有 */
  guideTocHref: string;
  /**
   * EPUB2 `guide` 里 `<reference type="cover">` 指向的**封面页**；'' = 没有。
   * 它是一张图（或一页图），不是可读内容 —— 不剔的话目录开头会多一条「Cover」（真机反馈 #6）。
   */
  guideCoverHref: string;
  coverHref: string;
  navItemHref: string;
  ncxHref: string;
}

/** container.xml → OPF 的 zip 内路径 */
export function parseContainer(xml: string): string {
  const tags: string[] = findTags(xml, 'rootfile');
  for (let i: number = 0; i < tags.length; i++) {
    const full: string = attrOf(tags[i], 'full-path');
    if (full.length > 0) {
      return normalizePath(full);
    }
  }
  throw new Error('EPUB_BAD_CONTAINER');
}

export function dirOf(path: string): string {
  const i: number = path.lastIndexOf('/');
  return i < 0 ? '' : path.substring(0, i + 1);
}

function baseNameOf(path: string): string {
  const i: number = path.lastIndexOf('/');
  return i < 0 ? path : path.substring(i + 1);
}

/** 剥掉 #fragment，并做一次 percent-decode（有些 epub 的 href 里是 %20） */
export function normalizeHref(href: string): string {
  const hash: number = href.indexOf('#');
  const cut: string = hash >= 0 ? href.substring(0, hash) : href;
  try {
    return decodeURIComponent(cut);
  } catch (e) {
    return cut;
  }
}

/** 规范化 zip 内路径：合并 //、消掉 ./ 与 ../ */
export function normalizePath(path: string): string {
  const parts: string[] = path.split('/');
  const stack: string[] = [];
  for (let i: number = 0; i < parts.length; i++) {
    const part: string = parts[i];
    if (part.length === 0 || part === '.') {
      continue;
    }
    if (part === '..') {
      if (stack.length > 0) {
        stack.pop();
      }
      continue;
    }
    stack.push(part);
  }
  return stack.join('/');
}

/** href 相对 baseDir 解析成 zip 内路径（baseDir 已含结尾 '/'） */
export function resolveHref(baseDir: string, href: string): string {
  return normalizePath(baseDir + normalizeHref(href));
}

/** 文件名去掉目录与扩展名，小写 —— 封面启发式用 */
function stemOf(href: string): string {
  const slash: number = href.lastIndexOf('/');
  const base: string = slash < 0 ? href : href.substring(slash + 1);
  const dot: number = base.lastIndexOf('.');
  const stem: string = dot > 0 ? base.substring(0, dot) : base;
  return stem.toLowerCase();
}

function isImagePath(href: string): boolean {
  const h: string = href.toLowerCase();
  return h.endsWith('.jpg') || h.endsWith('.jpeg') || h.endsWith('.png') || h.endsWith('.gif') ||
    h.endsWith('.webp') || h.endsWith('.bmp');
}

/**
 * manifest 里这条是不是图片。
 * media-type 优先，但**错标很常见**（自制 EPUB 会把 jpg 写成 application/octet-stream），
 * 所以扩展名也算数。
 */
function isImageItem(item: ManifestItem): boolean {
  if (item.mediaType.toLowerCase().indexOf('image/') === 0) {
    return true;
  }
  return isImagePath(item.href);
}

/**
 * 「这张图有多像封面」：0 = 不像，3 = 名字就叫封面。
 *
 * 分级而不是布尔，是为了在同时存在 `cover.jpg` 与 `cover-thumb.jpg` /
 * `cover_back.jpg` 的书里挑对正封（都是"含 cover"，但只有前者精确命中）。
 */
export function coverScoreOf(item: ManifestItem): number {
  if (!isImageItem(item)) {
    return 0;
  }
  const stem: string = stemOf(item.href);
  const id: string = item.id.toLowerCase();
  if (id === 'cover' || id === 'cover-image' || id === 'coverimage' ||
    stem === 'cover' || stem === 'cover-image' || stem === 'coverimage') {
    return 3;
  }
  if (id.indexOf('cover') >= 0 || stem.indexOf('cover') >= 0) {
    return 2;
  }
  if (stem.indexOf('封面') >= 0) {
    return 2;
  }
  return 0;
}

/**
 * 从 manifest 里猜封面。同分取**先出现的** —— OPF 的 manifest 顺序通常就是作者建书的顺序，
 * 正封一般排在封底/缩略图之前。
 */
export function guessCoverHref(opfDir: string, items: ManifestItem[]): string {
  let best: ManifestItem | null = null;
  let bestScore: number = 0;
  for (let i: number = 0; i < items.length; i++) {
    const score: number = coverScoreOf(items[i]);
    if (score > bestScore) {
      bestScore = score;
      best = items[i];
    }
  }
  return best === null ? '' : resolveHref(opfDir, best.href);
}

/**
 * 从「封面页」里抠出真正的图片路径（EPUB2 的 guide 形态）。
 *
 * 老书的 `<guide><reference type="cover" href="Text/cover.xhtml"/></guide>` 指的是**一页 XHTML**，
 * 那一页里通常只有一个 `<img src="../Images/cover.jpg"/>`（也有用 SVG 的 `<image xlink:href>`）。
 * 直接把这一页的字节当封面写下去 = 写进一段 HTML 文本 → `Image` 解不出、静默空白。
 *
 * 返回 zip 内路径；抠不到返回 `''`（调用方回退首字占位）。
 */
export function coverImageOfPage(xhtml: string, pageHref: string): string {
  const base: string = dirOf(pageHref);
  const imgTags: string[] = findTags(xhtml, 'img');
  for (let i: number = 0; i < imgTags.length; i++) {
    const src: string = attrOf(imgTags[i], 'src');
    if (src.length > 0) {
      const resolved: string = resolveHref(base, src);
      if (isImagePath(resolved)) {
        return resolved;
      }
    }
  }
  // SVG 封面：<svg><image xlink:href="cover.jpg"/></svg>
  const imageTags: string[] = findTags(xhtml, 'image');
  for (let i: number = 0; i < imageTags.length; i++) {
    let href: string = attrOf(imageTags[i], 'xlink:href');
    if (href.length === 0) {
      href = attrOf(imageTags[i], 'href');
    }
    if (href.length > 0) {
      const resolved: string = resolveHref(base, href);
      if (isImagePath(resolved)) {
        return resolved;
      }
    }
  }
  return '';
}

export function parseOpf(xml: string, opfDir: string): EpubPackage {
  const clean: string = stripProlog(xml);
  const items: ManifestItem[] = [];
  const itemTags: string[] = findTags(clean, 'item');
  for (let i: number = 0; i < itemTags.length; i++) {
    const tag: string = itemTags[i];
    const id: string = attrOf(tag, 'id');
    const href: string = attrOf(tag, 'href');
    if (id.length === 0 || href.length === 0) {
      continue;
    }
    const item: ManifestItem = {
      id: id,
      href: href,
      mediaType: attrOf(tag, 'media-type'),
      properties: attrOf(tag, 'properties')
    };
    items.push(item);
  }

  const spine: string[] = [];
  const spineNoLinear: Set<string> = new Set<string>();
  const spineTags: string[] = findTags(clean, 'itemref');
  for (let i: number = 0; i < spineTags.length; i++) {
    const idref: string = attrOf(spineTags[i], 'idref');
    if (idref.length > 0) {
      spine.push(idref);
      // linear="no"（EPUB 规范）：该文档**不属于线性阅读顺序**。目录/版权/彩插/附录常这么标。
      if (attrOf(spineTags[i], 'linear').toLowerCase() === 'no') {
        spineNoLinear.add(idref);
      }
    }
  }
  if (spine.length === 0) {
    throw new Error('EPUB_BAD_SPINE');
  }

  // guide（EPUB2）：`<reference type="toc">` 是目录页指针，`<reference type="cover">` 是封面页 ——
  // 两者都是**规范定义的标记**，比文件名启发式可靠，优先用它们。
  // 实测样书（暗恋·橘生淮南，EPUB2）102 个 itemref 里一个 linear 属性都没有 ——
  // 所以对老书来说，guide 几乎是唯一能认出封面页/目录页的硬依据。
  let guideTocHref: string = '';
  let guideCoverHref: string = '';
  const guideTags: string[] = findTags(clean, 'reference');
  for (let i: number = 0; i < guideTags.length; i++) {
    const href: string = attrOf(guideTags[i], 'href');
    if (href.length === 0) {
      continue;
    }
    const type: string = attrOf(guideTags[i], 'type').toLowerCase();
    if (type === 'toc' && guideTocHref.length === 0) {
      guideTocHref = resolveHref(opfDir, href);
    } else if (type === 'cover' && guideCoverHref.length === 0) {
      guideCoverHref = resolveHref(opfDir, href);
    }
  }

  // 封面：① manifest 里 properties 含 cover-image ② meta name="cover" 指向的 item id
  let coverHref: string = '';
  let navItemHref: string = '';
  let ncxHref: string = '';
  for (let i: number = 0; i < items.length; i++) {
    const item: ManifestItem = items[i];
    if (item.properties.indexOf('cover-image') >= 0) {
      coverHref = resolveHref(opfDir, item.href);
    }
    if (item.properties.indexOf('nav') >= 0) {
      navItemHref = resolveHref(opfDir, item.href);
    }
    if (item.mediaType === 'application/x-dtbncx+xml') {
      ncxHref = resolveHref(opfDir, item.href);
    }
  }
  if (coverHref.length === 0) {
    const metaTags: string[] = findTags(clean, 'meta');
    for (let i: number = 0; i < metaTags.length; i++) {
      if (attrOf(metaTags[i], 'name').toLowerCase() === 'cover') {
        const coverId: string = attrOf(metaTags[i], 'content');
        for (let k: number = 0; k < items.length; k++) {
          if (items[k].id === coverId) {
            coverHref = resolveHref(opfDir, items[k].href);
            break;
          }
        }
        // 规范说 content 是 item 的 id，但**相当多的自制 EPUB 写成文件名**
        // （`content="cover.jpg"`），按 id 找必然落空 —— 于是这本永远没有封面。
        // 再按 href / 文件名找一次，成本为零。
        if (coverHref.length === 0) {
          const wanted: string = coverId.toLowerCase();
          for (let k: number = 0; k < items.length; k++) {
            const hrefLower: string = items[k].href.toLowerCase();
            if (hrefLower === wanted || stemOf(hrefLower) === stemOf(wanted)) {
              coverHref = resolveHref(opfDir, items[k].href);
              break;
            }
          }
        }
        break;
      }
    }
  }
  // ③ 命名启发式（最后一道）：既没有 properties="cover-image"，也没有 <meta name="cover">。
  //    自制 EPUB 里极其常见，规范没要求这么写，但实务上封面文件几乎一定叫 cover.*
  //    —— 这是"要不要给一本没声明封面的书找封面"的取舍：只在名字明确指向封面时才认，
  //    认错的表现是书架显示了一张不相干的图，比永远显示首字更糟，所以门槛设得保守。
  if (coverHref.length === 0) {
    coverHref = guessCoverHref(opfDir, items);
  }

  return {
    title: firstElementText(clean, 'title').trim(),
    author: firstElementText(clean, 'creator').trim(),
    opfDir: opfDir,
    items: items,
    spine: spine,
    spineNoLinear: spineNoLinear,
    guideTocHref: guideTocHref,
    guideCoverHref: guideCoverHref,
    coverHref: coverHref,
    navItemHref: navItemHref,
    ncxHref: ncxHref
  };
}

/** 章节标题映射：zip 内路径 → 标题 */
export type TitleMap = Map<string, string>;

interface NcxContext {
  label: string;
  src: string;
}

/**
 * NCX（EPUB2）→ 标题映射（zip 内路径 → 标题）。
 *
 * ⚠️ 必须按**结构**配对，不能按"text 与 content 的出现顺序"配对：
 *   calibre 生成的 NCX 里 navPoint 是嵌套的，父节点常常**有 navLabel 但没有自己的 content**，
 *   一旦按顺序配对，整本目录会错位一章（真实出版书实测踩到，已写成回归测试）。
 * 做法：用栈跟踪当前最内层 navPoint，把它的 navLabel 文本与自己的 content 配成一对。
 */
export function parseNcx(xml: string, baseDir: string): TitleMap {
  const clean: string = stripProlog(xml);
  const tokens: TagToken[] = scanTags(clean);
  const map: TitleMap = new Map<string, string>();
  /** 带 #fragment 的条目（小节标题）先存这里：章级标题优先，避免小节标题盖住章标题 */
  const sectionMap: TitleMap = new Map<string, string>();
  const stack: NcxContext[] = [];

  for (let i: number = 0; i < tokens.length; i++) {
    const token: TagToken = tokens[i];
    const local: string = localNameOf(token.name);

    if (local === 'navpoint') {
      if (token.closing) {
        const done: NcxContext | undefined = stack.pop();
        if (done !== undefined && done.src.length > 0 && done.label.length > 0) {
          const path: string = resolveHref(baseDir, done.src);
          if (path.length > 0) {
            const isSection: boolean = done.src.indexOf('#') >= 0;
            const target: TitleMap = isSection ? sectionMap : map;
            if (!target.has(path)) {
              target.set(path, done.label);
            }
          }
        }
      } else if (!token.selfClosing) {
        // 审查报告 B17：自闭合 <navPoint/> 不入栈 —— 旧版一律 push，
        // 遇到自闭合条目栈里多出一个永远等不到 </navPoint> 的空壳，
        // 把它后面真正的父级配对顶掉 → 父级标题成片丢失
        stack.push({ label: '', src: '' });
      }
      continue;
    }
    if (stack.length === 0) {
      continue;
    }
    const top: NcxContext = stack[stack.length - 1];
    if (local === 'text' && !token.closing && top.label.length === 0) {
      top.label = decodeEntities(stripTags(token.innerText)).trim();
    } else if (local === 'content' && !token.closing && top.src.length === 0) {
      top.src = attrOf(token.text, 'src');
    }
  }

  // 只有"该文件没有任何章级标题"时，才退回小节标题
  sectionMap.forEach((label: string, path: string) => {
    if (!map.has(path)) {
      map.set(path, label);
    }
  });
  return map;
}

/** nav.xhtml（EPUB3）→ 标题映射；取每个 <a href> 与其内部文本 */
export function parseNav(xhtml: string, baseDir: string): TitleMap {
  const clean: string = stripProlog(xhtml);
  const map: TitleMap = new Map<string, string>();
  // 用 exec 循环（而不是 indexOf 找标签原文）：同名标签出现多次时 indexOf 会全部落到第一处
  const openRe: RegExp = new RegExp('<(?:[A-Za-z_][\\w.-]*:)?a\\b[^>]*>', 'gi');
  let m: RegExpExecArray | null = openRe.exec(clean);
  while (m !== null) {
    const tag: string = m[0];
    const href: string = attrOf(tag, 'href');
    if (href.length > 0) {
      const rest: string = clean.substring(m.index + tag.length);
      const closeIdx: number = rest.indexOf('</a>');
      if (closeIdx >= 0) {
        const label: string = decodeEntities(rest.substring(0, closeIdx).replace(/<[^>]*>/g, '')).trim();
        const path: string = resolveHref(baseDir, href);
        if (path.length > 0 && label.length > 0 && !map.has(path)) {
          map.set(path, label);
        }
      }
    }
    m = openRe.exec(clean);
  }
  return map;
}

/**
 * 文件名是否"像目录页"：toc / nav / contents / 目录（忽略扩展名与大小写）。
 *
 * ⚠️ 这只是**必要条件**，不是结论 —— 有的书正文章节也叫 `contents.xhtml`。
 * 是否真是目录页，还要看内容（见 `EpubParse.isTocDocument` 的链接密度判据）。
 */
export function looksLikeTocPath(zipPath: string): boolean {
  const name: string = baseNameOf(zipPath).toLowerCase();
  const dot: number = name.lastIndexOf('.');
  const stem: string = dot > 0 ? name.substring(0, dot) : name;
  return stem === 'toc' || stem === 'nav' || stem === 'contents' || stem === '目录';
}

/** 章标题兜底：用文件名（去扩展名），保证目录里不出现空标题 */
export function fallbackTitleOf(zipPath: string): string {
  const name: string = baseNameOf(zipPath);
  const dot: number = name.lastIndexOf('.');
  const raw: string = dot > 0 ? name.substring(0, dot) : name;
  return raw.length > 0 ? raw : '正文';
}
