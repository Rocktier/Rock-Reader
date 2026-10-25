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
import { BookRecord, BookmarkRow, ChapterRow, HighlightRow, ReadingProgress } from '../common/Types';
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
  // 本章真实字数（净化/简繁转换**之前**的原始长度）。0 = 还没量过。
  // EPUB 导入时只读目录不读正文（性能考虑），拿不到字数 ——
  // 只能在 Reader 展开该章时回填（那时整章全文已在内存，零额外开销）。
  // 用途：让全书进度按真实字数算，而不是按「第几章 ÷ 总章数」瞎估。
  'char_count INTEGER, ' +
  'PRIMARY KEY(book_id, idx))';

/** char_count 是后续新增列；老库需要补列（无发布版本，仍做一次兜底迁移） */
const SQL_CHAPTERS_ADD_CHAR_COUNT = 'ALTER TABLE chapters ADD COLUMN char_count INTEGER';

/** href 是 M4（EPUB）新增列；老库需要补列（无发布版本，仍做一次兜底迁移） */
const SQL_CHAPTERS_ADD_HREF = 'ALTER TABLE chapters ADD COLUMN href TEXT';

const SQL_PROGRESS = 'CREATE TABLE IF NOT EXISTS progress(' +
  'book_id TEXT PRIMARY KEY, chapter_index INTEGER, char_offset INTEGER, percent REAL, updated_at INTEGER)';

/** 阅读会话（统计用）：每次进入某章到切章/离开之间记一条 */
const SQL_SESSIONS = 'CREATE TABLE IF NOT EXISTS read_sessions(' +
  'book_id TEXT NOT NULL, chapter_index INTEGER, start_at INTEGER, end_at INTEGER)';

/** 书签（2026-10-22 P0-2 三件套） */
const SQL_BOOKMARKS = 'CREATE TABLE IF NOT EXISTS bookmarks(' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL, ' +
  'chapter_index INTEGER NOT NULL, char_offset INTEGER NOT NULL, ' +
  'excerpt TEXT, created_at INTEGER)';

/** 摘录/金句（2026-10-22 P0-2 三件套） */
const SQL_HIGHLIGHTS = 'CREATE TABLE IF NOT EXISTS highlights(' +
  'id INTEGER PRIMARY KEY AUTOINCREMENT, book_id TEXT NOT NULL, ' +
  'chapter_index INTEGER NOT NULL, start_char INTEGER NOT NULL, end_char INTEGER NOT NULL, ' +
  'excerpt TEXT NOT NULL, note TEXT, created_at INTEGER)';

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
    await store.executeSql(SQL_BOOKMARKS);
    await store.executeSql(SQL_HIGHLIGHTS);
    try {
      // 已存在该列时会报错，属预期（幂等迁移）
      await store.executeSql(SQL_CHAPTERS_ADD_HREF);
    } catch (e) {
      // 忽略：列已存在
    }
    try {
      await store.executeSql(SQL_CHAPTERS_ADD_CHAR_COUNT);
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
    // P2-6 决策记录（2026-10-22）：不提供"排序/网格切换"偏好项。
    // 现排序 last_read_at DESC（未读按 added_at DESC 兜底）已是阅读器最优默认 ——
    // 刚读的书浮顶，符合"拿起就读"的主路径；排序切换器与网格视图属低频伪需求，
    // 引入 prefs 键 + 设置 UI + 三种 SQL 的维护面，收益不成比例。
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
    // 书签/摘录跟着书走（三件套数据不外泄给下一本同名书）
    await store.executeSql('DELETE FROM bookmarks WHERE book_id = ?', [bookId]);
    await store.executeSql('DELETE FROM highlights WHERE book_id = ?', [bookId]);
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

  /**
   * 回填某章真实字数。
   *
   * 调用时机：Reader 展开该章之后 —— 那时整章全文已经在内存里，`text.length` 白拿，
   * 不需要为了统计专门再去解一次压缩包。（EPUB 导入阶段刻意不读正文，就是为了
   * 不让「导入」变成「解压 100 个 HTML」，这里是唯一低成本的量点。）
   *
   * 只写不读、失败无所谓：拿不到字数就退化成未确认，进度换算自动用平均值顶上。
   */
  async saveChapterCharCount(bookId: string, idx: number, count: number): Promise<void> {
    try {
      await this.ready().executeSql(
        'UPDATE chapters SET char_count = ? WHERE book_id = ? AND idx = ?', [count, bookId, idx]);
    } catch (e) {
      // 忽略：统计性质的数据，丢了不影响主链路，下次展开会再写一次
    }
  }

  /**
   * 各章已确认字数（下标 = 章序，未量过 = 0）。
   * 给 Reader 算「按真实字数的全书进度」用。
   */
  async loadCharCounts(bookId: string): Promise<number[]> {
    try {
      const rs = await this.ready().querySql(
        'SELECT char_count FROM chapters WHERE book_id = ? ORDER BY idx ASC', [bookId]);
      const out: number[] = [];
      while (rs.goToNextRow()) {
        const raw: number = rs.getLong(rs.getColumnIndex('char_count'));
        // 新增列在老行上是 null / 0 → 一律当「没量过」
        out.push(raw > 0 ? raw : 0);
      }
      rs.close();
      return out;
    } catch (e) {
      return [];
    }
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

  // ------------------------------------------------------------------
  // 书签 / 摘录（2026-10-22 P0-2 三件套）
  // ------------------------------------------------------------------

  async addBookmark(b: BookmarkRow): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'book_id': b.bookId,
      'chapter_index': b.chapterIndex,
      'char_offset': b.charOffset,
      'excerpt': b.excerpt,
      'created_at': b.createdAt
    };
    const id: number = await this.ready().insert('bookmarks', bucket);
    return id;
  }

  async listBookmarks(bookId: string): Promise<BookmarkRow[]> {
    const rs = await this.ready().querySql(
      'SELECT id, chapter_index, char_offset, excerpt, created_at FROM bookmarks ' +
      'WHERE book_id = ? ORDER BY chapter_index ASC, char_offset ASC', [bookId]);
    const out: BookmarkRow[] = [];
    while (rs.goToNextRow()) {
      const ex: string = rs.getString(rs.getColumnIndex('excerpt'));
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        bookId: bookId,
        chapterIndex: rs.getLong(rs.getColumnIndex('chapter_index')),
        charOffset: rs.getLong(rs.getColumnIndex('char_offset')),
        excerpt: ex === null ? '' : ex,
        createdAt: rs.getLong(rs.getColumnIndex('created_at'))
      });
    }
    rs.close();
    return out;
  }

  async deleteBookmark(id: number): Promise<void> {
    await this.ready().executeSql('DELETE FROM bookmarks WHERE id = ?', [id]);
  }

  async addHighlight(h: HighlightRow): Promise<number> {
    const bucket: relationalStore.ValuesBucket = {
      'book_id': h.bookId,
      'chapter_index': h.chapterIndex,
      'start_char': h.startChar,
      'end_char': h.endChar,
      'excerpt': h.excerpt,
      'note': h.note,
      'created_at': h.createdAt
    };
    const id: number = await this.ready().insert('highlights', bucket);
    return id;
  }

  async listHighlights(bookId: string): Promise<HighlightRow[]> {
    const rs = await this.ready().querySql(
      'SELECT id, chapter_index, start_char, end_char, excerpt, note, created_at FROM highlights ' +
      'WHERE book_id = ? ORDER BY chapter_index ASC, start_char ASC', [bookId]);
    const out: HighlightRow[] = [];
    while (rs.goToNextRow()) {
      const ex: string = rs.getString(rs.getColumnIndex('excerpt'));
      const nt: string = rs.getString(rs.getColumnIndex('note'));
      out.push({
        id: rs.getLong(rs.getColumnIndex('id')),
        bookId: bookId,
        chapterIndex: rs.getLong(rs.getColumnIndex('chapter_index')),
        startChar: rs.getLong(rs.getColumnIndex('start_char')),
        endChar: rs.getLong(rs.getColumnIndex('end_char')),
        excerpt: ex === null ? '' : ex,
        note: nt === null ? '' : nt,
        createdAt: rs.getLong(rs.getColumnIndex('created_at'))
      });
    }
    rs.close();
    return out;
  }

  async deleteHighlight(id: number): Promise<void> {
    await this.ready().executeSql('DELETE FROM highlights WHERE id = ?', [id]);
  }
}
