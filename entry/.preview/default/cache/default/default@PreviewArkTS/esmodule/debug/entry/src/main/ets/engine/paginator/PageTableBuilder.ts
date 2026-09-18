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
/** 每页能放几行（向下取整，至少 1 行） */
export function linesPerPage(viewportHeightPx: number, lineHeightPx: number): number {
    if (lineHeightPx <= 0) {
        return 1;
    }
    const n: number = Math.floor(viewportHeightPx / lineHeightPx);
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
 * 排版签名：任一参数变化都必须重算页表。
 * 实现说明：不用 crypto（ArkTS 里同步摘要 API 有额外依赖），用稳定字符串即可作 key。
 */
export function layoutSignature(fontSizeLevel: number, lineHeightLevel: number, marginLevel: number, viewportWidthPx: number, fontFamily: string): string {
    return 'f' + fontSizeLevel + '-l' + lineHeightLevel + '-m' + marginLevel + '-w' + Math.round(viewportWidthPx) + '-' + fontFamily;
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
        }
        else if (charOffset >= p.end) {
            lo = mid + 1;
        }
        else {
            return mid + 1;
        }
    }
    return pages.length === 0 ? 1 : Math.min(Math.max(lo + 1, 1), pages.length);
}
