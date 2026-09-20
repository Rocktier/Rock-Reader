/**
 * EPUB 解析（**纯逻辑：只吃 ZipArchive，零设备 API → CI 可端到端测**）
 *
 * 与 EpubParser.ets 的分工：
 *   本文件 = 「已解析的 zip → 章节清单 / 章正文」（可在 Node 里用内存 zip 测穿）
 *   EpubParser.ets = 「文件路径 → 读字节 → ZipArchive」（设备层，只做 IO 与缓存）
 *
 * 这样 CI 能用现造的真实 zip 跑完整 EPUB 解析链路，而不是只测零散工具函数。
 */
import { ChapterRow } from '../../common/Types';
import { ZipArchive } from '../zip/ZipReader';
import { firstHeadingOf, xhtmlToText } from './Xhtml';
import {
  dirOf,
  EpubPackage,
  fallbackTitleOf,
  looksLikeTocPath,
  ManifestItem,
  parseContainer,
  parseNcx,
  parseNav,
  parseOpf,
  resolveHref,
  TitleMap
} from './Opf';

export interface EpubParseResult {
  title: string;
  author: string;
  /** zip 内路径；没有封面则为 '' */
  coverHref: string;
  chapters: ChapterRow[];
}

function isHtml(mediaType: string): boolean {
  const t: string = mediaType.toLowerCase();
  return t.indexOf('xhtml') >= 0 || t.indexOf('html') >= 0;
}

/**
 * 是否是"目录页"（P11-1）。
 *
 * EPUB 自带的目录页（EPUB3 的 nav 文档、EPUB2 的 `toc.xhtml`）通常就列在 OPF spine 里，
 * 早期实现把它们当普通章节转文本 → 读者打开书先看到一长串目录，得翻很多页才到正文。
 *
 * 判据（从强到弱）：
 *   ① OPF manifest 里标了 `properties="nav"` 的文档 —— EPUB3 规范强制，最可靠；
 *   ② 文件名像目录（toc / nav / contents / 目录）**且**页内有 ≥3 个跳转链接 ——
 *      只看文件名会误伤（有的书正文章节也叫 contents.xhtml），加链接密度才下结论。
 *
 * 拿不准时**一律不剔除**：多留一页目录顶多难看，删掉正文不可接受。
 */
function isTocDocument(zip: ZipArchive, zipPath: string, navHref: string): boolean {
  if (navHref.length > 0 && zipPath === navHref) {
    return true;
  }
  if (!looksLikeTocPath(zipPath)) {
    return false;
  }
  try {
    const links: RegExpMatchArray | null = zip.readText(zipPath).match(/<a\b[^>]*\bhref=/gi);
    return links !== null && links.length >= 3;
  } catch (e) {
    return false;
  }
}

/** 把已解析的 zip 变成章节清单 */
export function parseEpubArchive(zip: ZipArchive): EpubParseResult {
  if (!zip.has('META-INF/container.xml')) {
    throw new Error('EPUB_NO_CONTAINER');
  }
  const opfPath: string = parseContainer(zip.readText('META-INF/container.xml'));
  if (!zip.has(opfPath)) {
    throw new Error('EPUB_NO_OPF');
  }
  const opfDir: string = dirOf(opfPath);
  const pkg: EpubPackage = parseOpf(zip.readText(opfPath), opfDir);

  // 标题映射：优先 EPUB3 nav，其次 EPUB2 NCX（两者都可能缺失 → 走兜底）
  let titles: TitleMap = new Map<string, string>();
  if (pkg.navItemHref.length > 0 && zip.has(pkg.navItemHref)) {
    titles = parseNav(zip.readText(pkg.navItemHref), dirOf(pkg.navItemHref));
  } else if (pkg.ncxHref.length > 0 && zip.has(pkg.ncxHref)) {
    titles = parseNcx(zip.readText(pkg.ncxHref), dirOf(pkg.ncxHref));
  }

  const byId: Map<string, ManifestItem> = new Map<string, ManifestItem>();
  for (let i: number = 0; i < pkg.items.length; i++) {
    const item: ManifestItem = pkg.items[i];
    byId.set(item.id, item);
  }

  // ---- 目录页识别（P11-1）：EPUB 自带的目录页只供目录浮层用，不许进正文流 ----
  const tocPaths: Set<string> = new Set<string>();
  let bodyCount: number = 0;
  for (let i: number = 0; i < pkg.spine.length; i++) {
    const probe: ManifestItem | undefined = byId.get(pkg.spine[i]);
    if (probe === undefined || !isHtml(probe.mediaType)) {
      continue;
    }
    const probePath: string = resolveHref(opfDir, probe.href);
    if (!zip.has(probePath)) {
      continue;
    }
    if (isTocDocument(zip, probePath, pkg.navItemHref)) {
      tocPaths.add(probePath);
    } else {
      bodyCount += 1;
    }
  }
  // 保底：若判据把整本书都算成了目录（说明踩空），就整体放弃剔除 —— 宁可能读，不能空手
  const skipToc: boolean = bodyCount > 0;

  const chapters: ChapterRow[] = [];
  for (let i: number = 0; i < pkg.spine.length; i++) {
    const item: ManifestItem | undefined = byId.get(pkg.spine[i]);
    if (item === undefined || !isHtml(item.mediaType)) {
      continue;
    }
    const zipPath: string = resolveHref(opfDir, item.href);
    if (!zip.has(zipPath)) {
      continue;
    }
    if (skipToc && tocPaths.has(zipPath)) {
      continue;
    }
    const fromNav: string | undefined = titles.get(zipPath);
    let title: string = fromNav === undefined ? '' : fromNav;
    if (title.length === 0) {
      // 没有 nav/ncx 时，才去解这一章取第一个标题（只在必要时付出代价）
      try {
        title = firstHeadingOf(zip.readText(zipPath));
      } catch (e) {
        title = '';
      }
    }
    if (title.length === 0) {
      title = fallbackTitleOf(zipPath);
    }
    const row: ChapterRow = {
      bookId: '',
      index: chapters.length,
      title: title,
      startChar: 0,
      endChar: 0,
      startByte: 0,
      endByte: 0,
      href: zipPath
    };
    chapters.push(row);
  }

  if (chapters.length === 0) {
    throw new Error('EPUB_NO_CHAPTERS');
  }
  return {
    title: pkg.title,
    author: pkg.author,
    coverHref: pkg.coverHref,
    chapters: chapters
  };
}

/** 从已解析的 zip 取某章正文 */
export function epubChapterTextOf(zip: ZipArchive, href: string): string {
  if (href.length === 0) {
    return '';
  }
  if (!zip.has(href)) {
    throw new Error('EPUB_NO_ENTRY:' + href);
  }
  return xhtmlToText(zip.readText(href));
}
