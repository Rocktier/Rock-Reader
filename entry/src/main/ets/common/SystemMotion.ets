/**
 * 系统「减少动态效果」读取层（2026-11-06 接入）。
 *
 * ## 为什么单独一个文件
 *
 * 判断逻辑（`isReducedMotion`）在 `Motion.ets` 里，是**纯函数**，node:test 直接测。
 * 但这个文件必须 `import settings from '@ohos.settings'` —— 一旦把它混进去，
 * `Motion.ets` 在 Node 里就求值失败了，整套动效单测全废。
 * ⇒ 分离：**纯逻辑可测，SDK 调用隔离在这一个文件里**。
 *
 * ## 读的是哪个键（已查证，不是猜的）
 *
 * `@ohos.settings` 的 `settings.display.ANIMATOR_DURATION_SCALE`。
 * d.ts 原话：「indicates the scaling factor for the animation duration ...
 * If the value is 0, the animation ends immediately. The default value is 1.」
 * 系统的「移除动画 / 减少动效」开关就是把这个倍率压到 0 —— 与 Android 同源。
 *
 * ⚠️ 该常量标注 **@deprecated since 21**。本工程 `compileSdkVersion` 是 20，
 *   现在编译不会报废弃；**升到 21 那天必须回来**，先看 d.ts 的 `@useinstead` 再换读取方式。
 *
 * ## 失败一律当"正常动效"
 *
 * `getValueSync` 在部分精简镜像（本地 x86 模拟器就没有 settingsdata 目录）上会抛错。
 * 这里 catch 之后返回默认值 `'1'` ⇒ 动效照常播。
 * **宁可多播一次动效，也不要因为一次读取失败让整个应用变成硬切** ——
 * 后者是所有人都看得到的回归，前者只有需要减少动效的人受影响。
 */

import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import settings from '@ohos.settings';
import { ANIM_SCALE_DEFAULT, isReducedMotion } from './Motion';

const DOMAIN: number = 0x0000;
const TAG: string = 'Motion';

/** 读系统动效倍率原值（读不到返回默认 '1'） */
export function readAnimScale(context: common.Context): string {
  try {
    const v: string = settings.getValueSync(context, settings.display.ANIMATOR_DURATION_SCALE,
      ANIM_SCALE_DEFAULT);
    // 打日志不是因为爱打日志：「动效为什么没降级」没有别的观测手段 ——
    // 系统开关在设置里，用户打开后应用这侧看不见任何可见反馈。
    hilog.info(DOMAIN, TAG, 'anim scale=%{public}s', v);
    return v;
  } catch (e) {
    // 本地 x86 模拟器没有 settingsdata，必然走到这里 —— 不是错误，是预期分支。
    hilog.warn(DOMAIN, TAG, 'read anim scale failed, fallback=%{public}s: %{public}s',
      ANIM_SCALE_DEFAULT, JSON.stringify(e));
    return ANIM_SCALE_DEFAULT;
  }
}

/** 系统是否要求减少动态效果 */
export function systemReducesMotion(context: common.Context): boolean {
  return isReducedMotion(readAnimScale(context));
}
