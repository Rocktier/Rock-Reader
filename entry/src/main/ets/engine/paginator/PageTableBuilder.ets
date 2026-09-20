/**
 * 页表构建（纯逻辑，可 CI 单测）
 *
 * 设计依据：docs/v1-design.md §3 / §6
 * 核心思想：**一次排版拿到整章每行的字符区间**（@ohos.graphics.text 的 LineMetrics.startIndex/endIndex），
 * 之后分页退化成"按行数切页"，翻页时零计算。
 */

export interface PageRange {
  start: number;
  end: number;
}

export interface PageTable {
  /** 排版签名：变了就说明要重算 */
  signature: string;
  pages: PageRange[];
  totalChars: number;
  linesPerPage: number;
}

/**
 * 分页安全余量（单位：行）。
 *
 * 为什么不是 0：本式隐含一个**从未被验证**的假设 —— "渲染端行盒高度 == lineHeight"。
 * 字体有自己的 ascent / descent，**行盒压不到比字体自然行高更小**；行距最低档是
 * 1.4×字号（`LayoutStyle.LINE_HEIGHT_RATIO`），而多数中文字体自然行高在 1.4~1.5em，
 * 所以该档下行盒有可能被字体"顶回" → 渲染端实际行高大于 lineHeight
 * → 按 lineHeight 算出的行数偏多 → **末行溢出容器被裁**。
 * 推导见 `docs/best-minds-review-2026-09-20.md` §2。
 *
 * 留半行缓冲：代价是每页最多少放 1 行（页底多一点留白，用户几乎看不见），
 * 收益是末行不会被裁（裁字用户一眼能看见）。**这个方向是有意选的。**
 * 真机实测（device-test B1/B4）若发现缺口更大，把本值调到 1.5；若确认渲染端
 * 严格按 lineHeight 渲染，可调回 0。
 */
const LINE_SAFETY_LINES: number = 0.5;

/** 每页能放几行（向下取整，至少 1 行） */
export function linesPerPage(viewportHeightPx: number, lineHeightPx: number): number {
  if (lineHeightPx <= 0) {
    return 1;
  }
  const usablePx: number = viewportHeightPx - lineHeightPx * LINE_SAFETY_LINES;
  const n: number = Math.floor(usablePx / lineHeightPx);
  return n < 1 ? 1 : n;
}

/**
 * 由行尾索引数组构建页表。
 * @param lineEnds 每行结束字符下标（不含），来自 LineMetrics.endIndex
 * @param perPage 每页行数
 * @param totalChars 本章总字符数
 */
export function buildPageTable(lineEnds: number[], perPage: number, totalChars: number): PageTable {
  const pages: PageRange[] = [];
  const per: number = perPage < 1 ? 1 : perPage;
  let line: number = 0;
  while (line < lineEnds.length) {
    const start: number = line === 0 ? 0 : lineEnds[line - 1];
    const endLine: number = Math.min(line + per - 1, lineEnds.length - 1);
    pages.push({ start: start, end: lineEnds[endLine] });
    line = endLine + 1;
  }
  if (pages.length === 0) {
    pages.push({ start: 0, end: totalChars });
  }
  return {
    signature: '',
    pages: pages,
    totalChars: totalChars,
    linesPerPage: per
  };
}

/**
 * 当前页落在第几页（页码从 1 开始）；给"按进度恢复阅读位置"用。
 * 用二分查找，页数多时也不慢。
 */
export function pageOfChar(pages: PageRange[], charOffset: number): number {
  let lo: number = 0;
  let hi: number = pages.length - 1;
  while (lo <= hi) {
    const mid: number = (lo + hi) >> 1;
    const p: PageRange = pages[mid];
    if (charOffset < p.start) {
      hi = mid - 1;
    } else if (charOffset >= p.end) {
      lo = mid + 1;
    } else {
      return mid + 1;
    }
  }
  return pages.length === 0 ? 1 : Math.min(Math.max(lo + 1, 1), pages.length);
}
