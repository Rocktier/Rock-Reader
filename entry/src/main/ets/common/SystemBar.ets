/**
 * 主题 → 系统层（**只管状态栏/导航栏文字颜色**）
 *
 * 为什么必须有这个文件（发现的真 bug）：
 *   应用内切到「浅色」主题时，页面底变成 #FFFFFF，但**系统状态栏的文字仍是白色**（时间、电量）
 *   → 白底白字，用户会以为坏了。必须跟着主题把状态栏内容色改成黑色。
 *
 * ⚠️ 2026-11-08 P0-1：**删掉了 setColorMode**。app 层 colorMode 现在恒为 NOT_SET
 *    （跟随系统，只在 EntryAbility.onCreate 设一次），这里再按主题钉死会导致：
 *      ① 系统主题变化不再回调 onConfigurationUpdate ⇒ 跟随系统失效；
 *      ② 运行中调 setColorMode 重建 UIContent、丢页面栈（私记 2026-10-16 实测）。
 *    系统绘制的弹窗跟随系统深浅，页面视觉由 Palette 决定 —— 两套机制不再互相打架。
 */
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isLightTheme, ThemeName } from './Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 只应在**生效主题**发生变化时调用（避免无谓的系统栏重设） */
export function applyThemeToSystem(ctx: Context, theme: ThemeName): void {
  // 纸 / 绿 都是浅色系 → 状态栏用深字（isLightTheme 的写法保证新增护眼色不会漏登记）
  const light: boolean = isLightTheme(theme);
  const contentColor: string = light ? '#000000' : '#FFFFFF';

  window.getLastWindow(ctx).then((win: window.Window) => {
    win.setWindowSystemBarProperties({
      statusBarContentColor: contentColor,
      navigationBarContentColor: contentColor
    }).catch((e: Error) => {
      hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', e.message);
    });
  }).catch((e: Error) => {
    hilog.warn(DOMAIN, TAG, 'getLastWindow failed: %{public}s', e.message);
  });
}
