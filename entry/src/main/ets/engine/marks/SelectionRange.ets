/**
 * 划词选区 → 摘录坐标的换算（纯逻辑，零设备 API → CI 可单测）
 *
 * 背景（2026-11-03）：
 *   Apple Books / Kindle / 静读天下都有「长按选词 → 菜单里点『加入摘录』」，
 *   我们此前只有「长按 → 定格整页快照 → 手动裁剪」（1.0.9 的土办法）。
 *
 * ⚠️ **坐标系（本文件存在的全部理由）**：
 *   摘录存在 `highlights` 表里，坐标是 **(chapter_index, start_char, end_char)**，
 *   其中 start/end 是**章内偏移**（`Reader.ets` 的 `openHighlightPanel` 里
 *   `range.start/range.end` 来自页表，页表的 offset 也是章内偏移）。
 *
 *   而划词回调给的是 **`onTextSelectionChange(selectionStart, selectionEnd)`**，
 *   它是**当前 Text 组件内容里的下标** —— 而那个 Text 的内容是 `this.pageText`，
 *   即**当页文本**（`pageText = chapterText.substring(range.start, range.end)`）。
 *
 *   ⇒ **换算公式**：章内偏移 = 当页起始偏移 + 页内下标
 *
 *   ⚠️ 公式的前提是「选区不跨页」。而 Text 组件的内容就是当页文本，
 *      选区**天然不可能跨页**（用户只能选当前显示的这一段）⇒ 前提恒成立。
 */

/**
 * 把「当页内的选区」换算成「章内的偏移区间」。
 *
 * @param pageStart 当页在章内的起始偏移（页表 `PageRange.start`）
 * @param pageLength 当页文本长度（= `pageText.length`）
 * @param selStart 选区起点（页内下标）
 * @param selEnd 选区终点（页内下标）
 * @returns 章内的 [start, end)；无效时返回 null
 */
export interface ChapterRange {
  start: number;
  end: number;
}

export function toChapterRange(pageStart: number, pageLength: number, selStart: number, selEnd: number): ChapterRange | null {
  // 选区非法：起点为负、终点不在起点之后
  // ⚠️ `selEnd <= selStart` 而不是 `<` —— 空选区（相等）也要拒：
  //    用户在正文里随手一点（没真选）也会触发回调，那次 start==end，
  //    放过去就会存一条**空摘录**进 DB（噪音条目 + 标记页出现空白行）。
  if (!Number.isFinite(pageStart) || !Number.isFinite(pageLength) ||
    !Number.isFinite(selStart) || !Number.isFinite(selEnd)) {
    return null;
  }
  if (selStart < 0 || selEnd <= selStart) {
    return null;
  }
  // 选区超出当页文本长度（理论上不会发生，但脏数据不能进 DB）
  if (selEnd > pageLength) {
    return null;
  }
  return { start: pageStart + selStart, end: pageStart + selEnd };
}

/**
 * 从选中文本里截出摘录快照。
 *
 * @param pageText 当页全文
 * @param selStart 选区起点（页内下标）
 * @param selEnd 选区终点（页内下标）
 * @param maxLen 快照最大长度（默认 200 —— 与整页快照同口径）
 */
export function excerptOfSelection(pageText: string, selStart: number, selEnd: number, maxLen: number = 200): string {
  if (selStart < 0 || selEnd <= selStart || selEnd > pageText.length) {
    return '';
  }
  const raw: string = pageText.substring(selStart, selEnd);
  // 归一化空白（与既有整页快照同一口径：换行/连续空格压成单空格）
  const flat: string = raw.replace(/\s+/g, ' ').trim();
  return flat.substring(0, maxLen);
}

/**
 * 选区是否"值得"做成摘录。
 *
 * ⚠️ 单字符选区多半是误触（长按手滑），且存进 DB 只会变成噪音条目。
 *    门槛 = 至少 2 个字符（中文 1 字也允许？不 —— 中文单字选区太容易误触，统一 2）。
 *
 * ⚠️⚠️ **2026-11-03 模拟器实测修正**：这个门槛**不能**用来拦「点加入摘录」。
 *    系统长按选词在中文里的默认粒度就是**一个词/一个字**（实测 range 3-4 = 1 字），
 *    用 2 字门槛拦 ⇒ 用户点了「加入摘录」却**毫无反应**（静默丢弃）＝ 死路。
 *    ⇒ 门槛降级为「要不要提示用户选区偏短」，
 *      **是否进面板**改由 `selectionIsEmpty`（只拒空选区）决定。
 */
export const MIN_SELECTION_LEN: number = 2;

export function selectionWorthKeeping(selStart: number, selEnd: number): boolean {
  return Number.isFinite(selStart) && Number.isFinite(selEnd) &&
    selStart >= 0 && selEnd - selStart >= MIN_SELECTION_LEN;
}

/**
 * 选区是否为空（用户随手一点也会触发回调，那时 start == end）。
 *
 * ⚠️ 这是「要不要打开摘录面板」的**唯一**门槛：
 *    面板是可编辑的（用户能把 1 个字改成整句）⇒ 只要非空就让他进，
 *    绝不能因为「太短」而让用户的点击变成死路。
 */
export function selectionIsEmpty(selStart: number, selEnd: number): boolean {
  if (!Number.isFinite(selStart) || !Number.isFinite(selEnd)) {
    return true;
  }
  if (selStart < 0 || selEnd <= selStart) {
    return true;
  }
  return false;
}
