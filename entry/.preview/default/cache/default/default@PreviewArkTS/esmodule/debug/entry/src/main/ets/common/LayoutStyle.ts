/**
 * 排版档位 —— **唯一真源**
 * 设计依据：docs/v1-design.md §8「档位 → 实际数值」表
 *
 * 纪律（来自 spec）：
 *  1. 字号/行距/边距**共用同一序号**，各自查同一张表的同一行；
 *  2. **只有这张表有数值** —— UI 芯片只写序号，排版层按序号查表；禁止任何地方再写一份数值；
 *  3. 只有档位、没有连续值（"设置页不许出现滑块"这条家族铁律的技术落点）。
 */
export const LEVEL_MIN: number = 1;
export const LEVEL_MAX: number = 5;
export interface LayoutLevels {
    fontSizeLevel: number;
    lineHeightLevel: number;
    marginLevel: number;
}
export const DEFAULT_LEVELS: LayoutLevels = {
    fontSizeLevel: 3,
    lineHeightLevel: 3,
    marginLevel: 3
};
/** 字号（fp）。索引 = 档位 - 1 */
const FONT_SIZE_FP: number[] = [14, 16, 18, 20, 22];
/** 行距倍率（lineHeight = fontSize × ratio） */
const LINE_HEIGHT_RATIO: number[] = [1.4, 1.6, 1.9, 2.2, 2.5];
/** 左右页边距（vp） */
const MARGIN_VP: number[] = [12, 16, 20, 24, 28];
/**
 * 夹到 [1,5]。NaN（preferences 里读到脏值）回落默认档 3 —— 否则会算出 0 字号/0 宽度。
 * 注意：0 与负数按"越界"夹到 1，**不是**回落默认档。
 */
export function clampLevel(level: number): number {
    if (Number.isNaN(level)) {
        return 3;
    }
    const value: number = Math.floor(level);
    if (value < LEVEL_MIN) {
        return LEVEL_MIN;
    }
    if (value > LEVEL_MAX) {
        return LEVEL_MAX;
    }
    return value;
}
function at(table: number[], level: number): number {
    return table[clampLevel(level) - 1];
}
export function fontSizeFpOf(level: number): number {
    return at(FONT_SIZE_FP, level);
}
export function lineHeightRatioOf(level: number): number {
    return at(LINE_HEIGHT_RATIO, level);
}
export function marginVpOf(level: number): number {
    return at(MARGIN_VP, level);
}
/**
 * 页表缓存键（layoutSignature）。
 *
 * 比 PageTableBuilder.layoutSignature 多带了**实际 px 值**：
 * 系统字体缩放变化时档位不变、但字号 px 会变，只按档位做 key 会错用旧页表。
 * 单位换算（fp→px / vp→px）依赖设备，必须体现到 key 里。
 */
export function layoutKey(levels: LayoutLevels, fontSizePx: number, lineHeightPx: number, widthPx: number, fontFamily: string): string {
    return 'f' + clampLevel(levels.fontSizeLevel) +
        '-l' + clampLevel(levels.lineHeightLevel) +
        '-m' + clampLevel(levels.marginLevel) +
        '-fs' + Math.round(fontSizePx) +
        '-lh' + Math.round(lineHeightPx) +
        '-w' + Math.round(widthPx) +
        // 字体必须进签名：换字体会改断行，沿用旧页表会切错页（'sys' = 系统默认）
        '-ff' + (fontFamily.length > 0 ? fontFamily : 'sys');
}
