import fs from "@ohos:file.fs";
import { ZipArchive } from "@bundle:com.rocktier.rockreader/entry/ets/engine/zip/ZipReader";
import { epubChapterTextOf, parseEpubArchive } from "@bundle:com.rocktier.rockreader/entry/ets/engine/epub/EpubParse";
import type { EpubParseResult } from "@bundle:com.rocktier.rockreader/entry/ets/engine/epub/EpubParse";
import { readAllBytes } from "@bundle:com.rocktier.rockreader/entry/ets/engine/parser/TxtParser";
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
