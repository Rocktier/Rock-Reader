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
  /** 字重档位 1..3（常规 / 中粗 / 加粗）。会影响断行，所以必须进排版签名 */
  fontWeightLevel: number;
}

export const DEFAULT_LEVELS: LayoutLevels = {
  fontSizeLevel: 3,
  lineHeightLevel: 3,
  marginLevel: 3,
  fontWeightLevel: 1
};

/** 字重档位范围（与字号等档位不同：只有 3 档，够用且更省事） */
export const WEIGHT_MIN: number = 1;
export const WEIGHT_MAX: number = 3;

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

// ── 大屏适配（P0-5，2026-10-22）────────────────────────────────────
// 纯逻辑、可 CI 单测（不碰 UIContext）：断点判定写在这里，
// UI 层只传视口宽度进来取结果。理由：断点错了一眼看不见，
// 且模拟器没有 wm 命令改分辨率验证 —— 用单测守门更可靠。

/** 断点档位（vp）：华为官方 breakpoint 标准档位 */
export const BP_SMALL_VP: number = 600;
export const BP_LARGE_VP: number = 840;
/**
 * 超宽档（vp）—— 2026-11-13 为 PC（2in1）加的第三档。
 *
 * 前两档是给平板设计的：840vp 以上 6 列，在 1280 平板横屏上每列约 200vp 正好。
 * 但 PC 是 1642vp（MateBook Pro 3120px ÷ 304dpi × 160），6 列会变成每列 260vp ——
 * 封面高近 350vp，一屏放不下两行，书架退化成"每个封面一张大图"。
 * 1400 而不是 1200：1280 的平板横屏/折叠屏展开仍是 6 列（不改平板观感），
 * 只有真正到 PC 宽度才切 8 列（每列约 195vp）。
 */
export const BP_XL_VP: number = 1400;
/** 每行的最大字数（中文）：超过后逐行扫视易丢行 */
export const MAX_LINE_CHARS: number = 35;

/**
 * 次级页（设置 / 关于 / 统计 / 隐私政策）版心封顶值（vp）。
 *
 * 这些页在平板横屏上会被拉成 1000+vp 宽 —— 表单行长得没法扫视，
 * 且整页内容摊成一条扁带，与"纸面"质感相反。封顶居中即可。
 * （与阅读页同思路：阅读页封的是"行长字数"，这里封的是"表单宽度"。）
 */
export const FORM_MAX_VP: number = 560;

/**
 * 次级页版心的单侧补丁（vp）：版心封顶 FORM_MAX_VP 居中所需的**额外**左右补白。
 *
 * UI 层写法是 `padding: basePadVp + formPadOf(w, basePadVp)` —— 也就是说
 * **基础边距是调用方先给的，这里必须减掉它**，否则版心会窄 `2 * basePadVp`。
 * ⚠️ 2026-11-13 2in1 实拍抓到过这个：`Settings` 内容区 520vp 而非 560vp，
 *    单测却全绿 —— 因为单测锁的是"函数自身语义"，而 UI 层还叠了一层基础边距，
 *    契约在第 111 行和调用点之间断裂。现在把 base 显式传进来，两边不可能再对不上。
 * 手机竖屏 / 未测量（0）返回 0 ⇒ 行为与旧版逐字一致。
 */
export function formPadOf(viewWidthVp: number, basePadVp: number): number {
  if (viewWidthVp <= 0 || viewWidthVp <= FORM_MAX_VP) {
    return 0;
  }
  const extra: number = Math.round((viewWidthVp - FORM_MAX_VP) / 2) - basePadVp;
  return extra > 0 ? extra : 0;
}

/** 书架网格列数：<600 = 3 列（手机竖屏）/ 600~839 = 4 列 / 840~1399 = 6 列（平板横屏）/ ≥1400 = 8 列（PC） */
export function shelfColsOf(widthVp: number): number {
  if (widthVp >= BP_XL_VP) {
    return 8;
  }
  if (widthVp >= BP_LARGE_VP) {
    return 6;
  }
  if (widthVp >= BP_SMALL_VP) {
    return 4;
  }
  return 3;
}

/**
 * 阅读页等效左右边距（vp）：行长超过 MAX_LINE_CHARS 个字时把版心封顶居中。
 * 返回等效边距 —— 渲染端 padding 用它，正文宽度 = 视口宽 − 2×边距，自动收窄居中。
 * 手机竖屏到不了封顶 ⇒ 原样返回档位边距（行为与旧版完全一致）。
 */
export function readingMarginOf(viewWidthVp: number, marginVp: number, fontSizeFp: number): number {
  const contentVp: number = viewWidthVp - marginVp * 2;
  const maxVp: number = fontSizeFp * MAX_LINE_CHARS;
  if (contentVp <= maxVp) {
    return marginVp;
  }
  // 超大字号 + 窄屏：35 个字的版心比可用宽度还宽 ⇒ 放弃收窄（否则边距为负、
  // 正文溢出屏幕）。宁可行长超限，也不能让文字被裁掉。
  const eff: number = Math.round((viewWidthVp - maxVp) / 2);
  return eff > marginVp ? eff : marginVp;
}

/**
 * 顶栏 / 底栏的对齐补白（vp）：宽屏下让它们与**正文左缘**对齐。
 *
 * 阅读页正文有版心（`readingMarginOf` 把行宽封在 35 字内），而顶栏与中央菜单
 * 一直用固定 token 边距 ⇒ 平板 1440vp 上正文从 405vp 起、顶栏「‹ 书架」贴在 12vp，
 * 菜单六项横跨整屏、相邻按钮间距 240vp（2026-11-13 实拍）。
 *
 * 返回值**加在**各处自身的边距上：`left: RR_SP_2XL + chromePadOf(...)`。
 *
 * ⚠️ 判据必须用**档位边距**（`baseMarginVp`）而不是渲染时的等效边距：
 *    版心一旦封顶，等效边距就等于 `(视口−封顶)/2`，拿它回推"有没有封顶"会恒真。
 * ⚠️ 手机竖屏（360vp、18fp、边距 20）：`360 − 40 = 320 ≤ 630` ⇒ **0**，
 *    顶栏底栏行为与旧版逐字一致 —— 这条由单测锁死。
 * ⚠️ 另加 `BP_LARGE_VP`（840）下限：手机横屏约 780vp 虽然也会让正文封顶，
 *    但那是既有观感，本轮只对平板/PC 动 —— 免得老用户升级后觉得"横屏界面变了"。
 */
export function chromePadOf(viewWidthVp: number, fontSizeFp: number,
  baseMarginVp: number, basePadVp: number): number {
  if (viewWidthVp < BP_LARGE_VP || fontSizeFp <= 0) {
    return 0;
  }
  const maxVp: number = fontSizeFp * MAX_LINE_CHARS;
  if (viewWidthVp - baseMarginVp * 2 <= maxVp) {
    return 0;
  }
  const extra: number = Math.round((viewWidthVp - maxVp) / 2) - basePadVp;
  return extra > 0 ? extra : 0;
}

/** 字重值（FontWeight 用的数字）。索引 = 档位 - 1 */
const FONT_WEIGHT: number[] = [400, 500, 700];
/** 夹到 [1,3]；NaN 回落默认档 1（常规）—— 否则会拿到 undefined 字重 */
export function clampWeightLevel(level: number): number {
  if (Number.isNaN(level)) {
    return 1;
  }
  const value: number = Math.floor(level);
  if (value < WEIGHT_MIN) {
    return WEIGHT_MIN;
  }
  if (value > WEIGHT_MAX) {
    return WEIGHT_MAX;
  }
  return value;
}

export function fontWeightOf(level: number): number {
  return FONT_WEIGHT[clampWeightLevel(level) - 1];
}

/**
 * 页表缓存键（layoutSignature）。
 *
 * 比 PageTableBuilder.layoutSignature 多带了**实际 px 值**：
 * 系统字体缩放变化时档位不变、但字号 px 会变，只按档位做 key 会错用旧页表。
 * 单位换算（fp→px / vp→px）依赖设备，必须体现到 key 里。
 */
export function layoutKey(
  levels: LayoutLevels,
  fontSizePx: number,
  lineHeightPx: number,
  widthPx: number,
  fontFamily: string
): string {
  return 'f' + clampLevel(levels.fontSizeLevel) +
    '-l' + clampLevel(levels.lineHeightLevel) +
    '-m' + clampLevel(levels.marginLevel) +
    '-fs' + Math.round(fontSizePx) +
    '-lh' + Math.round(lineHeightPx) +
    '-w' + Math.round(widthPx) +
    // 字重必须进签名：加粗会改变字宽与断行，沿用旧页表会切错页
    '-wt' + clampWeightLevel(levels.fontWeightLevel) +
    // 字体必须进签名：换字体会改断行，沿用旧页表会切错页（'sys' = 系统默认）
    '-ff' + (fontFamily.length > 0 ? fontFamily : 'sys');
}
