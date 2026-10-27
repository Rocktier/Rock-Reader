/**
 * 书架的纯规则层：分组、阅读状态与进度展示
 *
 * 为什么单独抽出来：这一层**不 import 任何 @ohos**，所以能在 Node 里被单测
 * （CI 没有模拟器，这是唯一能自动验证的手段，见 docs/v1-design.md §9）。
 * 页面只负责把数据喂进来，不做判断。
 */
import { BookRecord, ShelfItem } from '../../common/Types';

/** 「全部」哨兵值：不能用空串，空串会被 normalize 成「未分组」 */
export const GROUP_ALL: string = '\u0000__all__';
export const GROUP_UNFILED: string = '未分组';
/** 分组名最长字数（超出截断，避免 chip 撑破布局） */
export const MAX_GROUP_NAME: number = 12;

/** 归一化分组名：去首尾空白、折叠中间空白、超长截断；空 → 未分组 */
export function normalizeGroupName(raw: string): string {
  const text: string = (raw === undefined || raw === null) ? '' : raw.replace(/\s+/g, ' ').trim();
  if (text.length === 0) {
    return GROUP_UNFILED;
  }
  return text.length > MAX_GROUP_NAME ? text.substring(0, MAX_GROUP_NAME) : text;
}

/** 收集已有分组（去重，保持书籍顺序 —— 不排序，否则与用户直觉不符） */
export function collectGroups(books: BookRecord[]): string[] {
  const out: string[] = [];
  for (let i = 0; i < books.length; i++) {
    const g: string = normalizeGroupName(books[i].groupName);
    if (out.indexOf(g) < 0) {
      out.push(g);
    }
  }
  return out;
}

/** 按分组筛选；GROUP_ALL 表示不过滤 */
export function filterByGroup(books: BookRecord[], group: string): BookRecord[] {
  if (group === GROUP_ALL) {
    return books;
  }
  const out: BookRecord[] = [];
  for (let i = 0; i < books.length; i++) {
    if (normalizeGroupName(books[i].groupName) === group) {
      out.push(books[i]);
    }
  }
  return out;
}

/** 夹到 0~1：脏数据（NaN / 负数 / 越界）不许漏到 UI */
export function clampPercent(p: number): number {
  if (Number.isNaN(p) || p < 0) {
    return 0;
  }
  if (p > 1) {
    return 1;
  }
  return p;
}

/** 组装书架列表项；缺进度记 0（而不是 NaN） */
export function toShelfItems(books: BookRecord[], percents: Map<string, number>): ShelfItem[] {
  const out: ShelfItem[] = [];
  for (let i = 0; i < books.length; i++) {
    const b: BookRecord = books[i];
    const raw: number | undefined = percents.get(b.id);
    const percent: number = raw === undefined ? 0 : clampPercent(raw);
    const item: ShelfItem = { book: b, percent: percent };
    out.push(item);
  }
  return out;
}

/** 进度条点亮格数（10 格，与「继续阅读」卡片一致） */
export function filledCells(percent: number, total: number): number {
  return Math.round(clampPercent(percent) * total);
}

/**
 * 归一化查询串：去首尾空白、大小写折叠（英文书名 / 英文名姓隔开大小写不成问题）。
 *
 * 为什么不做拼音首字母 / 分词：用户找书的动作几乎全是「书名或作者里出现过的几个字」，
 * 子串匹配就够用；拼音表要几百 KB、分词要词库，都会直接撞家族「极致小」那条铁律，
 * 而且引入了就无法在 Node 里被真实数据测穿。够用即止。
 */
export function normalizeQuery(raw: string): string {
  const text: string = (raw === undefined || raw === null) ? '' : raw.trim();
  return text.toLowerCase();
}

/**
 * 关键字命中判定：书名或作者任一包含即命中；空查询一律放行（语义 = 不过滤）。
 * 脏数据（null / undefined）按空串处理 —— EPUB 的 OPF 里作者经常整个缺席。
 */
export function matchesQuery(title: string, author: string, query: string): boolean {
  const q: string = normalizeQuery(query);
  if (q.length === 0) {
    return true;
  }
  const titleText: string = (title === undefined || title === null) ? '' : title;
  const authorText: string = (author === undefined || author === null) ? '' : author;
  return titleText.toLowerCase().indexOf(q) >= 0 || authorText.toLowerCase().indexOf(q) >= 0;
}

/**
 * 按关键字过滤书架项。空查询原样返回同一份数组（顺序不变，省一次拷贝）。
 * 这是书架三层筛件的最外层：搜索 → 分组 → 阅读状态。
 */
export function filterByQuery(items: ShelfItem[], query: string): ShelfItem[] {
  if (normalizeQuery(query).length === 0) {
    return items;
  }
  const out: ShelfItem[] = [];
  for (let i = 0; i < items.length; i++) {
    if (matchesQuery(items[i].book.title, items[i].book.author, query)) {
      out.push(items[i]);
    }
  }
  return out;
}

/** 百分比文案 */
export function percentText(percent: number): string {
  return Math.round(clampPercent(percent) * 100) + '%';
}

// ------------------------------------------------------------------
// 阅读状态（自动分组；与用户自建分组是两个独立维度）
// ------------------------------------------------------------------

export const STATUS_ALL: string = 'st_all';
export const STATUS_UNREAD: string = 'st_unread';
export const STATUS_READING: string = 'st_reading';
export const STATUS_DONE: string = 'st_done';

/** 读完阈值：留 2% 余量 —— 最后一页读了一半也应算读完，否则永远停在「在读」 */
export const DONE_THRESHOLD: number = 0.98;

/**
 * 由进度推断阅读状态：0 → 未读；≥98% → 已读；其余 → 在读
 */
export function statusOf(percent: number): string {
  const p: number = clampPercent(percent);
  if (p <= 0) {
    return STATUS_UNREAD;
  }
  if (p >= DONE_THRESHOLD) {
    return STATUS_DONE;
  }
  return STATUS_READING;
}

export function filterByStatus(items: ShelfItem[], status: string): ShelfItem[] {
  if (status === STATUS_ALL) {
    return items;
  }
  const out: ShelfItem[] = [];
  for (let i = 0; i < items.length; i++) {
    if (statusOf(items[i].percent) === status) {
      out.push(items[i]);
    }
  }
  return out;
}
