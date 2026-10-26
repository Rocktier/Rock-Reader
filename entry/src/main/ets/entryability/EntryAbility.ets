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
   * ⚠️⚠️ **卡片参数不能按自定义键名取**（2026-10-26 在 Rock私记 上实测抓到，
   *    症状是"点了卡片应用起来了，但没跳到那本书"）：
   *    卡片里写 `params: { bookId: 'xxx' }`，系统拉起 ability 时传过来的
   *    want.parameters 长这样：
   *      { "a9": "xxx", "formID": 123, "params": "{\"a9\":\"xxx\"}", ...系统自己的一堆... }
   *    —— **自定义键被重命名成 a0/a1/a2…（按位置排）**，原键名彻底丢失。
   *    ⇒ `params['bookId']` 永远读不到。
   *    ⇒ 正确读法：解析系统塞回来的 `params` 字段（**只含卡片自定义参数**的 JSON 字符串），
   *      取**最后一个**键的值 —— 本卡片只传一个自定义参数（bookId），末位即它。
   *      ⚠️ 将来卡片要加第二个自定义参数时，这里必须改成"按值域特征挑"而不是末位。
   */
  private takeOpenBook(want: Want): void {
    const params: Record<string, Object> | undefined = want.parameters;
    if (params === undefined) {
      return;
    }
    const bookId: string = this.pickBookId(params);
    if (bookId.length === 0) {
      hilog.info(DOMAIN, TAG, 'card params carry no bookId');
      return;
    }
    AppStorage.setOrCreate('pendingOpenBook', bookId);
    hilog.info(DOMAIN, TAG, 'open book from card: %{public}s', bookId);
  }

  /** 从卡片 want 的参数里取出 bookId（**不依赖键名**） */
  private pickBookId(params: Record<string, Object>): string {
    // (a) 首选：系统把卡片自定义参数原样塞在 params 字段里（JSON 字符串）
    const nested: Object | undefined = params['params'];
    if (typeof nested === 'string') {
      const hit: string = this.lastValueInJson(nested);
      if (hit.length > 0) {
        return hit;
      }
    }
    // (b) 兜底：扁平键 a0/a1/…（自定义键被系统重命名后的形态），取最后一个非空
    let last: string = '';
    for (let i: number = 0; i < 32; i++) {
      const v: Object | undefined = params['a' + i];
      if (typeof v === 'string' && v.length > 0) {
        last = v;
      }
    }
    return last;
  }

  /** JSON 字符串里取最后一个值（取不到返回空串） */
  private lastValueInJson(json: string): string {
    try {
      const obj = JSON.parse(json) as Record<string, Object>;
      const keys: string[] = Object.keys(obj);
      let last: string = '';
      for (const k of keys) {
        const v: Object = obj[k];
        if (typeof v === 'string' && v.length > 0) {
          last = v;
        }
      }
      return last;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'parse card params failed: %{public}s', JSON.stringify(e));
      return '';
    }
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
