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
  /** 分组名（空串或空值按「未分组」处理，见 engine/shelf/ShelfRules） */
  groupName: string;
}

/** 书架列表项：书 + 阅读进度（0~1） */
export interface ShelfItem {
  book: BookRecord;
  percent: number;
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

/**
 * 阅读页写完进度库后**推给书架的进度快照**（经 AppStorage 的 'progressSaved' 键）。
 *
 * 为什么需要它：只靠"onPageShow 重查库"的链路在 **API 24 真机上不刷新**
 * （华为 1.0.1 审核反馈，nova 14 Pro / Pura 80 Ultra 实测）。
 * 收到快照后书架**直接改本地 @State** → ArkUI 立即重渲染：不查库、不等 onPageShow、不依赖版本行为。
 */
export interface ProgressSnapshot {
  bookId: string;
  /** 0~1 */
  percent: number;
}

export interface ChapterRow {
  bookId: string;
  index: number;
  title: string;
  /** TXT：该章在全文中的字符区间（EPUB 不用，置 0） */
  startChar: number;
  endChar: number;
  /** TXT：UTF-8 字节偏移（EPUB 不用，置 0） */
  startByte: number;
  endByte: number;
  /** EPUB：该章在 zip 内的路径；TXT 为空串 */
  href: string;
}

/**
 * 书签（2026-10-22 评审 P0-2「阅读器三件套」之一）：
 * 定位 = 章 + 章内字符偏移（与 progress 同一坐标系，页表可反查页码）。
 * excerpt 存书签处一行文本快照 —— 列表展示用，删书后正文没了也能看懂当时为什么签它。
 */
export interface BookmarkRow {
  id: number;
  bookId: string;
  chapterIndex: number;
  charOffset: number;
  /** 书签处的一行文本快照（列表展示；截断到 60 字） */
  excerpt: string;
  /** P0-2（2026-10-29）：书签备注（可空）。老库补列前的行按 '' 读 */
  note: string;
  createdAt: number;
}

/**
 * 摘录（金句；P0-2 之三。阅读页是整页 Text 无选区，交互取「长按整页摘录」——
 * 语义诚实：存的是"这一页里打动我的话"，用户可在面板里删改成真正的金句）。
 * startChar/endChar 是页区间（回跳用）；excerpt 为用户确认后的文本（≤200 字快照）。
 */
export interface HighlightRow {
  id: number;
  bookId: string;
  chapterIndex: number;
  startChar: number;
  endChar: number;
  /** 摘录文本快照（≤200 字，用户可在面板编辑） */
  excerpt: string;
  /** 一句注（可空） */
  note: string;
  /**
   * P0-1（2026-10-29）：高亮颜色索引（0=默认黄 … 见 HighlightPalette.COLOR_KEYS）。
   * 存索引不存色值 —— 主题切换时高亮色随主题走，老库补列前的行按 0（默认）读。
   */
  color: number;
  createdAt: number;
}

/** 全文搜索的一条命中（P0-2 之二）：章 + 命中位置 + 上下文片段 */
export interface SearchHitRow {
  chapterIndex: number;
  chapterTitle: string;
  /** 命中字符在该章全文中的偏移（跳转用） */
  charOffset: number;
  /** 命中行上下文（命中词前后各 ~30 字） */
  snippet: string;
}
