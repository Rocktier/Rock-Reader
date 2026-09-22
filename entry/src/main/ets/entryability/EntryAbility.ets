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
    this.takeIncomingUri(want);
  }

  /**
   * 「用其他应用打开」带来的文件 —— 应用**已经在跑**时也会走到这里。
   *
   * 为什么必须单独处理：系统 picker 对 `.mobi` / `.azw3` 这类没登记过的后缀不显示，
   * 这条路是导入的保底入口（详见 module.json5 里第二个 skill 的注释）。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.takeIncomingUri(want);
  }

  /**
   * 把 want 里的文件 uri 交给书架页去导入。
   *
   * 走 AppStorage 而不是在这里直接导入：这个时点 UI 还没起来，
   * 而导入需要书架页的 DB 与列表刷新。
   * 键名 `'pendingImportUri'` 与 Index.ets 里的 @StorageLink **必须一致**（ArkUI 装饰器
   * 要求字面量，没法抽成常量，所以两边都写死，改的时候要一起改）。
   */
  private takeIncomingUri(want: Want): void {
    const uri: string = typeof want.uri === 'string' ? want.uri : '';
    if (uri.length === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingImportUri', uri);
    hilog.info(DOMAIN, TAG, 'incoming file uri: %{public}s', uri);
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
