/**
 * 高亮调色板（P0-1，纯逻辑，零设备 API → CI 可单测）
 *
 * 设计取舍：
 *  - **存索引不存色值**：DB 只存 0~N-1 的整数。主题切换（白/棕/灰/夜）时高亮色
 *    随主题走，不会在夜间主题里冒出一坨刺眼的亮黄。
 *  - 颜色本身是**语义名**（COLOR_KEYS），真正的十六进制值由 UI 按当前主题解析
 *    （见 Reader.ets 的 highlightInk）。纯逻辑层只管"有几个颜色、索引合不合法"。
 *  - 老库补列前的行 color 为 null → 归一化成 0（默认黄），展示与新建一致。
 */
export const COLOR_KEYS: string[] = [
  'amber',   // 0 默认 · 琥珀黄
  'rose',    // 1 玫红
  'jade',    // 2 青绿
  'sky',     // 3 天蓝
  'violet'   // 4 紫罗兰
];

export const COLOR_DEFAULT: number = 0;

/** 每套主题下各语义色的实际值（hex）。key 顺序与 COLOR_KEYS 对齐。 */
const INK_LIGHT: string[] = ['#E8A317', '#D9536B', '#2E9E7B', '#3B82C4', '#8B6FC0'];
const INK_DARK: string[] = ['#F0B429', '#F2788D', '#4FD1A5', '#6BA6E8', '#B49AE0'];

/**
 * 索引归一化：脏值（null/undefined/NaN/负数/越界）一律回落到默认色。
 * 这是老库兼容的关键 —— 补列前的行读出来是 null，绝不能把 undefined 漏进数组下标。
 */
export function normalizeColor(color: number | null | undefined): number {
  if (color === null || color === undefined || Number.isNaN(color)) {
    return COLOR_DEFAULT;
  }
  const i: number = Math.floor(color);
  if (i < 0 || i >= COLOR_KEYS.length) {
    return COLOR_DEFAULT;
  }
  return i;
}

/** 取某索引在指定主题下的实际色值。dark=true 用夜间高亮组。 */
export function highlightInk(color: number, dark: boolean): string {
  const i: number = normalizeColor(color);
  return dark ? INK_DARK[i] : INK_LIGHT[i];
}

/** 供 UI 遍历的索引数组 [0,1,2,3,4]（纯逻辑手搓，避免 ArkTS 对 Array.keys 的限制） */
export function colorIndices(): number[] {
  const out: number[] = [];
  for (let i = 0; i < COLOR_KEYS.length; i++) {
    out.push(i);
  }
  return out;
}
