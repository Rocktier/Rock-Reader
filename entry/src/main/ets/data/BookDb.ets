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
import { ReadSession } from '../engine/stats/ReadStats';

const DB_NAME = 'rockreader.db';

const SQL_BOOKS = 'CREATE TABLE IF NOT EXISTS books(' +
  'id TEXT PRIMARY KEY, title TEXT NOT NULL, author TEXT, format TEXT, ' +
  'path TEXT NOT NULL, size INTEGER, added_at INTEGER, last_read_at INTEGER, group_name TEXT)';

/** group_name 是后续新增列；老库需要补列（无发布版本，仍做一次兜底迁移） */
const SQL_BOOKS_ADD_GROUP = 'ALTER TABLE books ADD COLUMN group_name TEXT';

const SQL_CHAPTERS = 'CREATE TABLE IF NOT EXISTS chapters(' +
  'book_id TEXT NOT NULL, idx INTEGER NOT NULL, title TEXT, ' +
  'start_char INTEGER, end_char INTEGER, start_byte INTEGER, end_byte INTEGER, ' +
  'href TEXT, ' +
  'PRIMARY KEY(book_id, idx))';

/** href 是 M4（EPUB）新增列；老库需要补列（无发布版本，仍做一次兜底迁移） */
const SQL_CHAPTERS_ADD_HREF = 'ALTER TABLE chapters ADD COLUMN href TEXT';

const SQL_PROGRESS = 'CREATE TABLE IF NOT EXISTS progress(' +
  'book_id TEXT PRIMARY KEY, chapter_index INTEGER, char_offset INTEGER, percent REAL, updated_at INTEGER)';

/** 阅读会话（统计用）：每次进入某章到切章/离开之间记一条 */
const SQL_SESSIONS = 'CREATE TABLE IF NOT EXISTS read_sessions(' +
  'book_id TEXT NOT NULL, chapter_index INTEGER, start_at INTEGER, end_at INTEGER)';

/** 结果集 → BookRecord（分组列可能为 null：老库补列前的行） */
function rowToBook(rs: relationalStore.ResultSet): BookRecord {
  const group: string = rs.getString(rs.getColumnIndex('group_name'));
  return {
    id: rs.getString(rs.getColumnIndex('id')),
    title: rs.getString(rs.getColumnIndex('title')),
    author: rs.getString(rs.getColumnIndex('author')),
    format: rs.getString(rs.getColumnIndex('format')),
    path: rs.getString(rs.getColumnIndex('path')),
    size: rs.getLong(rs.getColumnIndex('size')),
    addedAt: rs.getLong(rs.getColumnIndex('added_at')),
    lastReadAt: rs.getLong(rs.getColumnIndex('last_read_at')),
    groupName: group === null ? '' : group
  };
}

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
    await store.executeSql(SQL_SESSIONS);
    try {
      // 已存在该列时会报错，属预期（幂等迁移）
      await store.executeSql(SQL_CHAPTERS_ADD_HREF);
    } catch (e) {
      // 忽略：列已存在
    }
    try {
      await store.executeSql(SQL_BOOKS_ADD_GROUP);
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
      'last_read_at': book.lastReadAt,
      'group_name': book.groupName
    };
    await this.ready().insert('books', bucket, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async listBooks(): Promise<BookRecord[]> {
    const rs = await this.ready().querySql(
      'SELECT id, title, author, format, path, size, added_at, last_read_at, group_name FROM books ' +
      'ORDER BY last_read_at DESC, added_at DESC');
    const out: BookRecord[] = [];
    while (rs.goToNextRow()) {
      out.push(rowToBook(rs));
    }
    rs.close();
    return out;
  }

  async getBook(bookId: string): Promise<BookRecord | null> {
    const rs = await this.ready().querySql(
      'SELECT id, title, author, format, path, size, added_at, last_read_at, group_name FROM books WHERE id = ?',
      [bookId]);
    let book: BookRecord | null = null;
    if (rs.goToNextRow()) {
      book = rowToBook(rs);
    }
    rs.close();
    return book;
  }

  /** 重命名（只改书名，不动沙箱文件） */
  async renameBook(bookId: string, title: string): Promise<void> {
    await this.ready().executeSql('UPDATE books SET title = ? WHERE id = ?', [title, bookId]);
  }

  /** 移动分组（分组名由调用方用 ShelfRules.normalizeGroupName 归一化后再传） */
  async setBookGroup(bookId: string, group: string): Promise<void> {
    await this.ready().executeSql('UPDATE books SET group_name = ? WHERE id = ?', [group, bookId]);
  }

  /** 已有分组（数据库侧 DISTINCT；展示层再用 ShelfRules 归一化去重） */
  async listGroupNames(): Promise<string[]> {
    const rs = await this.ready().querySql('SELECT DISTINCT group_name FROM books');
    const out: string[] = [];
    while (rs.goToNextRow()) {
      out.push(rs.getString(rs.getColumnIndex('group_name')));
    }
    rs.close();
    return out;
  }

  /** 一次取全部书的进度，避免书架里 N+1 查询（铁律 1：快） */
  async listAllProgress(): Promise<Map<string, number>> {
    const rs = await this.ready().querySql('SELECT book_id, percent FROM progress');
    const out: Map<string, number> = new Map<string, number>();
    while (rs.goToNextRow()) {
      const id: string = rs.getString(rs.getColumnIndex('book_id'));
      const percent: number = rs.getDouble(rs.getColumnIndex('percent'));
      // 脏数据不放进去：缺进度由 ShelfRules 记 0，不许 NaN 漏到 UI
      if (!Number.isNaN(percent)) {
        out.set(id, percent);
      }
    }
    rs.close();
    return out;
  }

  async deleteBook(bookId: string): Promise<void> {
    const store = this.ready();
    await store.executeSql('DELETE FROM books WHERE id = ?', [bookId]);
    await store.executeSql('DELETE FROM chapters WHERE book_id = ?', [bookId]);
    await store.executeSql('DELETE FROM progress WHERE book_id = ?', [bookId]);
    await this.deleteSessionsOf(bookId);
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

  // ------------------------------------------------------------------
  // 阅读会话（统计）
  // ------------------------------------------------------------------

  async addSession(s: ReadSession): Promise<void> {
    const bucket: relationalStore.ValuesBucket = {
      'book_id': s.bookId,
      'chapter_index': s.chapterIndex,
      'start_at': s.startAt,
      'end_at': s.endAt
    };
    await this.ready().insert('read_sessions', bucket);
  }

  /** 取会话；since 用于只取近 N 天（默认全部） */
  async listSessions(since: number = 0): Promise<ReadSession[]> {
    const rs = await this.ready().querySql(
      'SELECT book_id, chapter_index, start_at, end_at FROM read_sessions WHERE end_at >= ? ORDER BY start_at ASC',
      [since]);
    const out: ReadSession[] = [];
    while (rs.goToNextRow()) {
      const s: ReadSession = {
        bookId: rs.getString(rs.getColumnIndex('book_id')),
        chapterIndex: rs.getLong(rs.getColumnIndex('chapter_index')),
        startAt: rs.getLong(rs.getColumnIndex('start_at')),
        endAt: rs.getLong(rs.getColumnIndex('end_at'))
      };
      out.push(s);
    }
    rs.close();
    return out;
  }

  /** 清理过老的会话（统计只需要近期；避免表无限增长） */
  async pruneSessions(before: number): Promise<void> {
    await this.ready().executeSql('DELETE FROM read_sessions WHERE end_at < ?', [before]);
  }

  /** 删书时一并清掉它的会话 */
  private async deleteSessionsOf(bookId: string): Promise<void> {
    await this.ready().executeSql('DELETE FROM read_sessions WHERE book_id = ?', [bookId]);
  }
}
