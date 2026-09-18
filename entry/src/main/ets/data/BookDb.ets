/**
 * 本地库（relationalStore）
 *
 * 表设计（尽量少，够用即可）：
 *   books     书籍本身
 *   chapters  章节索引（TXT：字符偏移 + UTF-8 字节偏移，供按 offset 随机读）
 *   progress  阅读进度（一本书一行）
 *
 * ponytail: 不做「页表缓存表」—— 页表按章重算只要 10ms 级，且要处理排版签名失效，
 *   先放内存缓存，等真机上量到卡顿再加表。
 * ponytail: 不做 sha256 去重（官方示例有，但那是为省缓存空间；v1 重复导入由用户自己删）。
 */
import { relationalStore } from '@kit.ArkData';
import { BookRecord, ChapterRow, ReadingProgress } from '../common/Types';

const DB_NAME = 'rockreader.db';

const SQL_BOOKS = 'CREATE TABLE IF NOT EXISTS books(' +
  'id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT, format TEXT, ' +
  'path TEXT NOT NULL, size INTEGER, added_at INTEGER, last_read_at INTEGER)';

const SQL_CHAPTERS = 'CREATE TABLE IF NOT EXISTS chapters(' +
  'book_id TEXT NOT NULL, idx INTEGER NOT NULL, title TEXT, ' +
  'start_char INTEGER, end_char INTEGER, start_byte INTEGER, end_byte INTEGER, ' +
  'href TEXT, ' +
  'PRIMARY KEY(book_id, idx))';

/** href 是 M4（EPUB）新增列；老库需要补列（无发布版本，仍做一次兜底迁移） */
const SQL_CHAPTERS_ADD_HREF = 'ALTER TABLE chapters ADD COLUMN href TEXT';

const SQL_PROGRESS = 'CREATE TABLE IF NOT EXISTS progress(' +
  'book_id TEXT PRIMARY KEY, chapter_index INTEGER, char_offset INTEGER, percent REAL, updated_at INTEGER)';

export class BookDb {
  private store: relationalStore.RdbStore | null = null;

  async open(context: Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    await store.executeSql(SQL_BOOKS);
    await store.executeSql(SQL_CHAPTERS);
    await store.executeSql(SQL_PROGRESS);
    try {
      // 已存在该列时会报错，属预期（幂等迁移）
      await store.executeSql(SQL_CHAPTERS_ADD_HREF);
    } catch (e) {
      // 忽略：列已存在
    }
    this.store = store;
  }

  private ready(): relationalStore.RdbStore {
    if (this.store === null) {
      throw new Error('BookDb not opened');
    }
    return this.store;
  }

  async addBook(book: BookRecord): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'id': book.id,
      'title': book.title,
      'author': book.author,
      'format': book.format,
      'path': book.path,
      'size': book.size,
      'added_at': book.addedAt,
      'last_read_at': book.lastReadAt
    };
    await this.ready().insert('books', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async listBooks(): Promise<BookRecord[]> {    const rs = await this.ready().querySql(
      'SELECT id, title, author, format, path, size, added_at, last_read_at FROM books ' +
      'ORDER BY last_read_at DESC, added_at DESC');
    const out: BookRecord[] = [];
    while (rs.goToNextRow()) {
      out.push({
        id: rs.getString(rs.getColumnIndex('id')),
        title: rs.getString(rs.getColumnIndex('title')),
        author: rs.getString(rs.getColumnIndex('author')),
        format: rs.getString(rs.getColumnIndex('format')),
        path: rs.getString(rs.getColumnIndex('path')),
        size: rs.getLong(rs.getColumnIndex('size')),
        addedAt: rs.getLong(rs.getColumnIndex('added_at')),
        lastReadAt: rs.getLong(rs.getColumnIndex('last_read_at'))
      });
    }
    rs.close();
    return out;
  }

  async getBook(bookId: string): Promise<BookRecord | null> {
    const rs = await this.ready().querySql(
      'SELECT id, title, author, format, path, size, added_at, last_read_at FROM books WHERE id = ?', [bookId]);
    let book: BookRecord | null = null;
    if (rs.goToNextRow()) {
      book = {
        id: rs.getString(rs.getColumnIndex('id')),
        title: rs.getString(rs.getColumnIndex('title')),
        author: rs.getString(rs.getColumnIndex('author')),
        format: rs.getString(rs.getColumnIndex('format')),
        path: rs.getString(rs.getColumnIndex('path')),
        size: rs.getLong(rs.getColumnIndex('size')),
        addedAt: rs.getLong(rs.getColumnIndex('added_at')),
        lastReadAt: rs.getLong(rs.getColumnIndex('last_read_at'))
      };
    }
    rs.close();
    return book;
  }

  async deleteBook(bookId: string): Promise<void> {
    const store = this.ready();
    await store.executeSql('DELETE FROM books WHERE id = ?', [bookId]);
    await store.executeSql('DELETE FROM chapters WHERE book_id = ?', [bookId]);
    await store.executeSql('DELETE FROM progress WHERE book_id = ?', [bookId]);
  }

  async addChapters(bookId: string, chapters: ChapterRow[]): Promise<void> {
    if (chapters.length === 0) {
      return;
    }
    const buckets: relationalStore.ValuesBucket[] = chapters.map((c: ChapterRow) => {
      const b: relationalStore.ValuesBucket = {
        'book_id': bookId,
        'idx': c.index,
        'title': c.title,
        'start_char': c.startChar,
        'end_char': c.endChar,
        'start_byte': c.startByte,
        'end_byte': c.endByte,
        'href': c.href
      };
      return b;
    });
    await this.ready().batchInsert('chapters', buckets);
  }

  async listChapters(bookId: string): Promise<ChapterRow[]> {
    const rs = await this.ready().querySql(
      'SELECT idx, title, start_char, end_char, start_byte, end_byte, href FROM chapters ' +
      'WHERE book_id = ? ORDER BY idx ASC', [bookId]);
    const out: ChapterRow[] = [];
    while (rs.goToNextRow()) {
      const href: string = rs.getString(rs.getColumnIndex('href'));
      out.push({
        bookId: bookId,
        index: rs.getLong(rs.getColumnIndex('idx')),
        title: rs.getString(rs.getColumnIndex('title')),
        startChar: rs.getLong(rs.getColumnIndex('start_char')),
        endChar: rs.getLong(rs.getColumnIndex('end_char')),
        startByte: rs.getLong(rs.getColumnIndex('start_byte')),
        endByte: rs.getLong(rs.getColumnIndex('end_byte')),
        href: href === null ? '' : href
      });
    }
    rs.close();
    return out;
  }

  async getProgress(bookId: string): Promise<ReadingProgress | null> {
    const rs = await this.ready().querySql(
      'SELECT chapter_index, char_offset, percent, updated_at FROM progress WHERE book_id = ?', [bookId]);
    let result: ReadingProgress | null = null;
    if (rs.goToNextRow()) {
      result = {
        bookId: bookId,
        chapterIndex: rs.getLong(rs.getColumnIndex('chapter_index')),
        charOffset: rs.getLong(rs.getColumnIndex('char_offset')),
        percent: rs.getDouble(rs.getColumnIndex('percent')),
        updatedAt: rs.getLong(rs.getColumnIndex('updated_at'))
      };
    }
    rs.close();
    return result;
  }

  async saveProgress(p: ReadingProgress): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'book_id': p.bookId,
      'chapter_index': p.chapterIndex,
      'char_offset': p.charOffset,
      'percent': p.percent,
      'updated_at': p.updatedAt
    };
    await this.ready().insert('progress', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async touchLastRead(bookId: string, when: number): Promise<void> {
    await this.ready().executeSql('UPDATE books SET last_read_at = ? WHERE id = ?', [when, bookId]);
  }
}
