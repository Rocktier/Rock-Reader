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
import { clearEpubCache, readEpubChapterText } from './EpubParser';
import { ReaderPrefs } from '../../data/ReaderPrefs';
import { convertByMode } from '../text/ChineseConvert';
import { defaultPurifyRules, purifyText } from '../text/Purify';

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

/**
 * 加工层：在取出的原文上做**正文净化（去广告）**与**简繁转换**
 *
 * 为什么是装饰器：TXT/EPUB/将来的 Reader Kit 都走同一套加工，阅读页零改动。
 * 为什么在这里而不是改缓存：净化/简繁是**展示偏好**，不该污染导入时建立的字符偏移索引
 * （净化会改变字符数，若导入时净化，进度偏移就对不上了）。
 */
export class ProcessedSource implements BookSource {
  private inner: BookSource;
  private prefs: ReaderPrefs;

  constructor(inner: BookSource, prefs: ReaderPrefs) {
    this.inner = inner;
    this.prefs = prefs;
  }

  chapterText(chapter: ChapterRow): string {
    let text: string = this.inner.chapterText(chapter);
    if (this.prefs.isPurifyOn()) {
      text = purifyText(text, defaultPurifyRules());
    }
    return convertByMode(text, this.prefs.getConvertMode());
  }

  release(): void {
    this.inner.release();
  }
}

function rawSource(book: BookRecord): BookSource {
  if (book.format === 'txt') {
    return new TxtSource(book.path);
  }
  if (book.format === 'epub') {
    return new EpubSource(book.path);
  }
  return new UnsupportedSource();
}

export function createBookSource(book: BookRecord, prefs: ReaderPrefs): BookSource {
  return new ProcessedSource(rawSource(book), prefs);
}
