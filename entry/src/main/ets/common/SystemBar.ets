/**
 * 主题 → 系统层（状态栏/导航栏文字颜色 + 系统深色模式）
 *
 * 为什么必须有这个文件（发现的真 bug）：
 *   应用内切到「浅色」主题时，页面底变成 #FFFFFF，但**系统状态栏的文字仍是白色**（时间、电量）
 *   → 白底白字，用户会以为坏了。必须跟着主题把状态栏内容色改成黑色。
 *
 * 同时把系统 colorMode 也一起设上：弹窗（如"移除这本书？"）由系统绘制，
 * 它跟随的是 colorMode，而不是我们的 Palette。
 */
import { window } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { THEME_LIGHT, ThemeName } from './Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 只应在主题**发生变化**时调用（避免无谓的配置变更） */
export function applyThemeToSystem(ctx: Context, theme: ThemeName): void {
  const light: boolean = theme === THEME_LIGHT;
  const contentColor: string = light ? '#000000' : '#FFFFFF';

  try {
    ctx.getApplicationContext().setColorMode(light
      ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
      : ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(e));
  }

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
