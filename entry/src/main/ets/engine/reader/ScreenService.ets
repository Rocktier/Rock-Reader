import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
// ⚠️ `window` 属于 **@kit.ArkUI**（不是 @kit.WindowKit —— SDK 26 里**没有** WindowKit 这个 kit）。
//    查 SDK 26 的 `kits/@kit.ArkUI.d.ts`：它 `import window from '@ohos.window'` 并导出。
import { window } from '@kit.ArkUI';

import { restoreWindowSettings } from './ScreenSettings';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/**
 * 窗口级屏幕设置（亮度 / 常亮）—— **唯一调 WindowKit 的地方**
 *
 * 为什么单独一个文件：
 *  `pages/Reader.ets` 已经 3000+ 行，而 WindowKit 的调用带 try/catch 与异步，
 *  塞进去会让那个文件更难读。而且**还原逻辑必须成对**（进阅读页设、离阅读页还原），
 *  收在这一个文件里 ⇒ 只有一个还原入口，漏不掉。
 *
 * ⚠️ **两个 SDK 约束（务必读完再改）**：
 *  ① `setWindowBrightness` 只在**窗口前台且有焦点**时生效；传 **-1 恢复系统亮度**。
 *     ⇒ 离开阅读页必须还原，否则退到书架后屏幕还压着暗 —— 用户会以为手机坏了。
 *  ② `setKeepScreenOn` 是**窗口级**开关，不是组件属性 ⇒ 同样必须成对还原。
 *
 * ⚠️ **全部调用都包 try/catch**：这两个 API 在模拟器/异常窗口状态下可能抛
 *  （1300002 窗口状态异常 / 1300003 窗口管理服务异常 / 401 参数错误）。
 *  屏幕亮没亮是**体验增强**，绝不该让阅读页因为它崩掉。
 */
export class ScreenService {
  /**
   * 施加窗口亮度 + 常亮。
   *
   * @param ctx 上下文（取窗口用）
   * @param brightness 窗口亮度（0.0~1.0；-1 = 跟随系统）
   * @param keepScreenOn 是否保持常亮
   */
  static async apply(ctx: common.UIAbilityContext, brightness: number, keepScreenOn: boolean): Promise<void> {
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      await win.setWindowBrightness(brightness);
      await win.setKeepScreenOn(keepScreenOn);
      hilog.info(DOMAIN, TAG, 'screen applied brightness=%{public}d keepOn=%{public}s', brightness, String(keepScreenOn));
    } catch (e) {
      // 亮度/常亮失败**不影响阅读** —— 只记日志，不弹提示（用户没要求这个功能）
      hilog.warn(DOMAIN, TAG, 'screen apply failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * **还原**窗口亮度与常亮（离开阅读页时必调）。
   *
   * ⚠️ 幂等：重复调用安全（`restoreWindowSettings` 返回的固定值）。
   */
  static async restore(ctx: common.UIAbilityContext): Promise<void> {
    const r = restoreWindowSettings();
    try {
      const win: window.Window = await window.getLastWindow(ctx);
      // ⚠️ 顺序：先恢复亮度（-1），再关常亮 —— 反过来也无所谓，但固定顺序便于排查
      await win.setWindowBrightness(r.brightness);
      await win.setKeepScreenOn(r.keepScreenOn);
      hilog.info(DOMAIN, TAG, 'screen restored');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'screen restore failed: %{public}s', JSON.stringify(e));
    }
  }
}
