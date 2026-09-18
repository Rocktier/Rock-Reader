import type { ChapterRow } from '../../common/Types';
import type { ZipArchive } from '../zip/ZipReader';
import { firstHeadingOf, xhtmlToText } from "@bundle:com.rocktier.rockreader/entry/ets/engine/epub/Xhtml";
import { dirOf, fallbackTitleOf, parseContainer, parseNcx, parseNav, parseOpf, resolveHref } from "@bundle:com.rocktier.rockreader/entry/ets/engine/epub/Opf";
import type { EpubPackage, ManifestItem, TitleMap } from "@bundle:com.rocktier.rockreader/entry/ets/engine/epub/Opf";
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
    }
    else if (pkg.ncxHref.length > 0 && zip.has(pkg.ncxHref)) {
        titles = parseNcx(zip.readText(pkg.ncxHref), dirOf(pkg.ncxHref));
    }
    const byId: Map<string, ManifestItem> = new Map<string, ManifestItem>();
    for (let i: number = 0; i < pkg.items.length; i++) {
        const item: ManifestItem = pkg.items[i];
        byId.set(item.id, item);
    }
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
        const fromNav: string | undefined = titles.get(zipPath);
        let title: string = fromNav === undefined ? '' : fromNav;
        if (title.length === 0) {
            // 没有 nav/ncx 时，才去解这一章取第一个标题（只在必要时付出代价）
            try {
                title = firstHeadingOf(zip.readText(zipPath));
            }
            catch (e) {
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
