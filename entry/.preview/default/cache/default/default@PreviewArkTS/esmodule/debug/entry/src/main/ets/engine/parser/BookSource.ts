import type { BookRecord, ChapterRow } from '../../common/Types';
import { clearTextCache, readChapterTextByChars } from "@bundle:com.rocktier.rockreader/entry/ets/engine/parser/TxtParser";
import { clearEpubCache, readEpubChapterText } from "@bundle:com.rocktier.rockreader/entry/ets/engine/parser/EpubParser";
export interface BookSource {
    /** 取该章全文；失败抛错（调用方降级提示，不崩） */
    chapterText(chapter: ChapterRow): string;
    /** 换书 / 退出阅读页时释放（大文件缓存必须能放掉） */
    release(): void;
}
/** TXT：整本解码后缓存，按字符偏移随机切章 */
export class TxtSource implements BookSource {
    private path: string;
    constructor(path: string) {
        this.path = path;
    }
    chapterText(chapter: ChapterRow): string {
        return readChapterTextByChars(this.path, chapter.startChar, chapter.endChar);
    }
    release(): void {
        clearTextCache();
    }
}
/** EPUB：按需从 zip 解出该章 XHTML 并转纯文本（不解压到磁盘） */
export class EpubSource implements BookSource {
    private path: string;
    constructor(path: string) {
        this.path = path;
    }
    chapterText(chapter: ChapterRow): string {
        return readEpubChapterText(this.path, chapter.href);
    }
    release(): void {
        clearEpubCache();
    }
}
/** 还不能读的格式：返回空文本，由阅读页提示，不崩 */
export class UnsupportedSource implements BookSource {
    chapterText(chapter: ChapterRow): string {
        return '';
    }
    release(): void {
    }
}
export function createBookSource(book: BookRecord): BookSource {
    if (book.format === 'txt') {
        return new TxtSource(book.path);
    }
    if (book.format === 'epub') {
        return new EpubSource(book.path);
    }
    return new UnsupportedSource();
}
