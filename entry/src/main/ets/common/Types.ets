/**
 * 跨层共享的少量类型（book / 进度）
 * 设计依据：docs/v1-design.md §4 数据模型
 */

export interface BookRecord {
  id: string;
  title: string;
  author: string;
  /** 'txt' | 'epub' */
  format: string;
  /** 沙箱内绝对路径 */
  path: string;
  size: number;
  addedAt: number;
  lastReadAt: number;
}

export interface ReadingProgress {
  bookId: string;
  chapterIndex: number;
  /** 章内字符偏移（页表用它反查页码） */
  charOffset: number;
  /** 0~1 */
  percent: number;
  updatedAt: number;
}

export interface ChapterRow {
  bookId: string;
  index: number;
  title: string;
  startChar: number;
  endChar: number;
  startByte: number;
  endByte: number;
}
