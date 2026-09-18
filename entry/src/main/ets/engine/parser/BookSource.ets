/**
 * 书源抽象：**"怎么取某一章的文字"** 这一件事
 *
 * 为什么单独抽一层：阅读页（pages/Reader.ets）不该关心书是 TXT 还是 EPUB。
 *   TXT  → 从整本解码文本里按字符偏移切（本文件）
 *   EPUB → 按 spine 条目从 zip 里取 XHTML 再转纯文本（M4 加 EpubSource）
 *   将来 Reader Kit 可用 → 再加一个实现，阅读页零改动
 *
 * layoutSignature / 分页 / 进度 全部对"章内字符偏移"工作，因此两种格式共用同一条管线。
 */
import { BookRecord, ChapterRow } from '../../common/Types';
import { clearTextCache, readChapterTextByChars } from './TxtParser';

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
  return new UnsupportedSource();
}
