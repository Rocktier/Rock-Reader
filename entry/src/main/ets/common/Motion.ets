/**
 * 动效 token —— 时长 / 曲线 / 错峰 / 降级（2026-11-06 去 AI 味改版建立）
 *
 * 为什么单独立一层：
 *   ① 时长原来散在各页 `.animation({ duration: 300 })` 里，想统一改一次要翻五个文件；
 *   ② **降级**必须是一处开关 —— 「减少动态效果」不是"动画慢一点"，是**根本不该动**，
 *      如果每个调用点各写一份 `if`，漏一处就是一次前庭不适（HIG《动作》明写要尊重此设置）。
 *
 * ⚠️ **鸿蒙侧「减少动态效果」的系统开关**（2026-11-06 已查证）：
 *   `settings.display.ANIMATOR_DURATION_SCALE`（`@ohos.settings`，d.ts 原话：
 *   "If the value is 0, the animation ends immediately. The default value is 1"）。
 *   读它的代码在 `common/SystemMotion.ets`（那个文件引了 `@ohos.settings`，**不能进单测**）；
 *   判断逻辑留在本文件（纯函数，可测）。
 *   ⚠️ 该常量标注 `@deprecated since 21`，本工程 compileSdk 是 20 故暂不受影响 ——
 *   **升到 21 那天要回来换读取方式**（届时先查 d.ts 的 `@useinstead`）。
 *
 * 曲线：本文件**不导出 `Curve` 常量** —— `Curve` 是 ArkUI 的全局枚举，导出它会让本文件
 *   在 Node 里无法求值（单测跑不动）。页面统一用 `Curve.EaseOut`：
 *   书架是"落位"语义（书放回架子），EaseOut 合适；弹簧留给按钮和收藏星那种"手感"场合。
 */

/** 系统动效倍率的默认值（读不到时用） */
export const ANIM_SCALE_DEFAULT: string = '1';

/**
 * 系统动效倍率 → 是否该降级。
 *
 * 判据：倍率 **≤ 0** 即"动画立即结束"⇒ 用户已要求减少动态效果。
 * 读不到 / 脏值（空串、'abc'）一律当 **正常动效** —— 宁可多播一次动效，
 * 也不要因为一次读取失败让整个应用变成"硬切"。
 */
export function isReducedMotion(scale: string): boolean {
  // ⚠️ 必须先挡空串：JS 里 `Number('')` 是 **0** 不是 NaN ——
  //    直接判 `Number(x) <= 0` 会把"读不到"当成"用户要求关闭动画"，
  //    结果是整台机器的动效静默消失且没人知道原因（单测抓到的）。
  const s: string = scale.trim();
  if (s.length === 0) {
    return false;
  }
  const v: number = Number(s);
  if (Number.isNaN(v)) {
    return false;
  }
  return v <= 0;
}

/** 入场（淡入 + 微缩放）总时长 */
export const MOTION_MS_ENTER: number = 280;

/** 相邻元素之间的错峰步长 */
export const MOTION_MS_STEP: number = 60;

/** 按压反馈时长（比入场短：手感要"跟手"，不是"播动画"） */
export const MOTION_MS_PRESS: number = 140;

/** 入场起始缩放（0.96 → 1：只做"轻微推近"，不做弹跳） */
export const MOTION_SCALE_ENTER: number = 0.96;

/** 入场起始纵向位移（8vp 上移归位） */
export const MOTION_SHIFT_ENTER: number = 8;

/**
 * 按「是否减少动态效果」折算时长。
 *
 * 返回 0 而不是一个更小的值：`.animation({ duration: 0 })` 在 ArkUI 里等价于直接跳到终态，
 * 这正是"减少动态"要的结果（内容该出现还是出现，只是不表演）。
 */
export function motionMs(base: number, reduced: boolean): number {
  if (reduced) {
    return 0;
  }
  return base < 0 ? 0 : base;
}

/**
 * 第 `index` 项的错峰延时。
 *
 * `cap` 是"最多错峰到第几项"——书架上可能有一百本书，若按 index 线性累加，
 * 第一百本要等 6 秒才出现（比不动效更糟）。超出 cap 的一律取 cap 的延时，一起落位。
 */
export function staggerMs(index: number, cap: number, step: number = MOTION_MS_STEP): number {
  const i: number = index < 0 ? 0 : index;
  const c: number = cap < 0 ? 0 : cap;
  return (i > c ? c : i) * step;
}
