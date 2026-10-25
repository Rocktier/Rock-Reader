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
    this.takeOpenBook(want);
  }

  /**
   * 「用其他应用打开」带来的文件 —— 应用**已经在跑**时也会走到这里。
   *
   * 为什么必须单独处理：系统 picker 对 `.mobi` / `.azw3` 这类没登记过的后缀不显示，
   * 这条路是导入的保底入口（详见 module.json5 里第二个 skill 的注释）。
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.takeIncomingUri(want);
    this.takeOpenBook(want);
  }

  /**
   * B1 服务卡片「继续读」：postCardAction('router') 带 params.bookId 拉起本 Ability
   * （冷启动走 onCreate，热启动走 onNewWant）。同样落 AppStorage 由书架页转发 ——
   * 键名 'pendingOpenBook' 与 Index.ets 的 @StorageLink 两边写死，改要一起改。
   *
   * 参数形态双保险：直接扁平放（params.bookId）与嵌一层（params.params.bookId）
   * 都接 —— 官方示例是扁平形态，但卡片框架版本差异历史上改过形状，宁多认一种。
   */
  private takeOpenBook(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const raw: Object | undefined = params['bookId'];
    const nested: Object | undefined = params['params'] as Object | undefined;
    const fromNested: Object | undefined = nested === undefined || nested === null
      ? undefined
      : (nested as Record<string, Object>)['bookId'];
    const pick: Object | undefined = raw !== undefined ? raw : fromNested;
    const bookId: string = typeof pick === 'string'
      ? pick
      : (typeof pick === 'number' ? String(pick) : '');
    if (bookId.length === 0) {
      return;
    }
    AppStorage.setOrCreate('pendingOpenBook', bookId);
    hilog.info(DOMAIN, TAG, 'open book from card: %{public}s', bookId);
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
