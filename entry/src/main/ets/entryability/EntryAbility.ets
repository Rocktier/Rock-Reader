import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { ReaderPrefs } from '../data/ReaderPrefs';
import { isLightTheme, THEME_DARK, ThemeName } from '../common/Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 系统深色模式跟随**用户选的阅读主题**（不是跟随系统）：
    // 否则浅色主题下，系统绘制的弹窗/状态栏仍是深色，与页面反差突兀。
    let theme: ThemeName = THEME_DARK;
    try {
      const prefs = new ReaderPrefs();
      prefs.open(this.context);
      theme = prefs.getTheme();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'read theme failed: %{public}s', JSON.stringify(e));
    }
    try {
      // 纸 / 绿 同属浅色系（isLightTheme），以后再加护眼色不用改这里
      this.context.getApplicationContext().setColorMode(isLightTheme(theme)
        ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
        : ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setColorMode failed: %{public}s', JSON.stringify(e));
    }
    hilog.info(DOMAIN, TAG, 'onCreate theme=%{public}s', theme);
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'loadContent succeeded');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
