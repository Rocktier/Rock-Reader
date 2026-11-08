import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { isSystemDarkColorMode, SYSTEM_DARK_KEY } from '../common/Appearance';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 2026-11-08 P0-1：app 层 colorMode 一律 NOT_SET（跟随系统），
    // **只在 onCreate / loadContent 之前调这一次**。
    //
    // 原来按用户主题钉死 LIGHT/DARK，两个代价：系统白天、应用全黑（党哥 11-08 实测）；
    // app 一旦被钉死，系统主题变化就**不再回调 onConfigurationUpdate**，
    // "跟随系统"永远跟不上（Rock私记 2026-10-26 华为复评实测）。
    // ⚠️ 运行中绝不再调 setColorMode：它会重建 UIContent、丢页面栈
    //    （私记 2026-10-16 装机实测：切完直接退回桌面）。视觉一律由 Palette 决定。
    try {
      this.context.getApplicationContext()
        .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'startup setColorMode failed: %{public}s', JSON.stringify(e));
    }
    // 系统深浅写进 AppStorage：页面 @StorageProp('systemDark') 首帧就能拿到，
    // 不用等 onConfigurationUpdate，也不会先闪一下反色。
    this.writeSystemDark(this.context.config.colorMode);
    this.takeIncomingUri(want);
    this.takeOpenBook(want);
  }

  /** 系统深浅 → AppStorage（值没变就不写，省一次全 UI 刷新） */
  private writeSystemDark(colorMode: number | undefined): void {
    try {
      const dark: boolean = isSystemDarkColorMode(colorMode);
      if ((AppStorage.get<boolean>(SYSTEM_DARK_KEY) === true) !== dark) {
        AppStorage.setOrCreate(SYSTEM_DARK_KEY, dark);
      }
      hilog.info(DOMAIN, TAG, 'system colorMode=%{public}d dark=%{public}s',
        Number(colorMode === undefined ? -1 : colorMode), dark ? 'yes' : 'no');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'write systemDark failed: %{public}s', JSON.stringify(e));
    }
  }

  /**
   * 系统深浅变了（用户在控制中心切深色）。
   * ⚠️ 不调 super：UIAbility 基类未实现该方法，调了会黑屏（私记 2026-10-25 实测）。
   * ⚠️ 必须用**回调参数** newConfig.colorMode，不能读 this.context.config.colorMode ——
   *    回调那一刻 ctx.config 可能还是旧值，会算出"系统没变"（华为复评实测）。
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    this.writeSystemDark(newConfig.colorMode);
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
    // 兜底：应用在后台时系统切了深浅，少数机型不走 onConfigurationUpdate。
    // 回前台对一次账，跟随系统档下色板必须与系统一致（私记同款兜底）。
    this.writeSystemDark(this.context.config.colorMode);
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'onBackground');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'onDestroy');
  }
}
