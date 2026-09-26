/**
 * 阅读偏好（Preferences）
 * 设计依据：docs/v1-design.md §4 —— 排版档位、主题存 Preferences（书在 relationalStore）
 *
 * 只存**档位序号**与主题名，不存任何数值 —— 数值唯一真源在 common/LayoutStyle.ets。
 * 用同步 API（getPreferencesSync / getSync / putSync）：阅读页初始化路径上不能有 await。
 */
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clampLevel, clampWeightLevel, DEFAULT_LEVELS, LayoutLevels } from '../common/LayoutStyle';
import { normalizeTheme, THEME_DARK, ThemeName } from '../common/Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const STORE_NAME: string = 'rockreader_prefs';
const KEY_FONT: string = 'font_level';
const KEY_LINE: string = 'line_level';
const KEY_MARGIN: string = 'margin_level';
const KEY_THEME: string = 'theme';
/** 字体族；'' = 系统默认（体积为 0：只列系统已装字体，不内置字体文件） */
const KEY_FAMILY: string = 'font_family';
const KEY_WEIGHT: string = 'weight_level';
/** TXT 正文净化（去广告）开关；默认开（国内 TXT 广告太多） */
const KEY_PURIFY: string = 'purify_on';
/** 简繁：'off' | 's2t' | 't2s' */
const KEY_CONVERT: string = 'convert_mode';

export const CONVERT_OFF: string = 'off';

/**
 * 用户已确认阅读的**隐私政策版本**（0 = 从未确认）。
 * 2026-09-26 审核驳回第 1 条：首次启动必须提示用户阅读隐私政策。
 * 存**版本号**而不是布尔值 —— 将来政策有实质变更时把 PRIVACY_VERSION 加一，
 * 老用户会重新看到弹窗（布尔值做不到这点）。
 */
const KEY_PRIVACY_AGREED: string = 'privacy_agreed_version';

export class ReaderPrefs {
  private store: preferences.Preferences | null = null;
  private levels: LayoutLevels = {
    fontSizeLevel: DEFAULT_LEVELS.fontSizeLevel,
    lineHeightLevel: DEFAULT_LEVELS.lineHeightLevel,
    marginLevel: DEFAULT_LEVELS.marginLevel,
    fontWeightLevel: DEFAULT_LEVELS.fontWeightLevel
  };
  private theme: ThemeName = THEME_DARK;
  private fontFamily: string = '';
  private purifyOn: boolean = true;
  private convertMode: string = CONVERT_OFF;

  /** 幂等：重复调用直接返回 */
  open(ctx: Context): void {
    if (this.store !== null) {
      return;
    }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
      this.store = store;
      this.levels = this.readLevels(store);
      this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
      this.fontFamily = this.readText(store, KEY_FAMILY, '');
      this.purifyOn = this.readBool(store, KEY_PURIFY, true);
      this.convertMode = this.readText(store, KEY_CONVERT, CONVERT_OFF);
    } catch (e) {
      // 读不到就用默认档位（3/3/3 + 深色）—— 绝不因为偏好读取失败而读不了书
      hilog.error(DOMAIN, TAG, 'prefs open failed: %{public}s', JSON.stringify(e));
    }
  }

  private readLevels(store: preferences.Preferences): LayoutLevels {
    return {
      fontSizeLevel: this.readLevel(store, KEY_FONT),
      lineHeightLevel: this.readLevel(store, KEY_LINE),
      marginLevel: this.readLevel(store, KEY_MARGIN),
      fontWeightLevel: this.readWeight(store, KEY_WEIGHT)
    };
  }

  private readWeight(store: preferences.Preferences, key: string): number {
    const raw: preferences.ValueType = store.getSync(key, DEFAULT_LEVELS.fontWeightLevel);
    if (typeof raw === 'number') {
      return clampWeightLevel(raw);
    }
    return DEFAULT_LEVELS.fontWeightLevel;
  }

  private readBool(store: preferences.Preferences, key: string, fallback: boolean): boolean {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'boolean') {
      return raw;
    }
    return fallback;
  }

  /** 通用整数读取（无 clamp —— 用于版本号这类不需要夹取的值） */
  private readInt(store: preferences.Preferences, key: string, fallback: number): number {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'number') {
      return raw;
    }
    return fallback;
  }

  private readLevel(store: preferences.Preferences, key: string): number {
    const raw: preferences.ValueType = store.getSync(key, DEFAULT_LEVELS.fontSizeLevel);
    if (typeof raw === 'number') {
      return clampLevel(raw);
    }
    return 3;
  }

  private readText(store: preferences.Preferences, key: string, fallback: string): string {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'string') {
      return raw;
    }
    return fallback;
  }

  /**
   * 重新从 store 读一遍。
   * 必要性：设置页与阅读页各持一个 ReaderPrefs 实例，设置页改了档位后，
   * 阅读页 onPageShow 里必须重读，否则会拿着旧档位排版（切了档位不生效）。
   */
  reload(): void {
    if (this.store === null) {
      return;
    }
    const store: preferences.Preferences = this.store;
    this.levels = this.readLevels(store);
    this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
    this.fontFamily = this.readText(store, KEY_FAMILY, '');
    this.purifyOn = this.readBool(store, KEY_PURIFY, true);
    this.convertMode = this.readText(store, KEY_CONVERT, CONVERT_OFF);
  }

  getLevels(): LayoutLevels {
    return this.levels;
  }

  getTheme(): ThemeName {
    return this.theme;
  }

  /** 已确认阅读的隐私政策版本（0 = 从未确认 → 首次启动要弹提示） */
  getPrivacyAgreedVersion(): number {
    if (this.store === null) {
      return 0;
    }
    return this.readInt(this.store, KEY_PRIVACY_AGREED, 0);
  }

  /** 记录"已阅读第 v 版隐私政策" */
  setPrivacyAgreedVersion(v: number): void {
    this.put(KEY_PRIVACY_AGREED, v);
    this.flush();
    // 临时诊断：写后立即回读，确认内存缓存里确实写进去了
    const readback: number = this.getPrivacyAgreedVersion();
    hilog.info(DOMAIN, TAG,
      'privacy set: v=%{public}d readback=%{public}d storeNull=%{public}s',
      v, readback, String(this.store === null));
  }

  /** '' = 系统默认字体 */
  getFontFamily(): string {
    return this.fontFamily;
  }

  saveFontFamily(family: string): void {
    this.fontFamily = family;
    this.put(KEY_FAMILY, family);
    this.flush();
  }

  saveLevels(levels: LayoutLevels): void {
    this.levels = levels;
    this.put(KEY_FONT, clampLevel(levels.fontSizeLevel));
    this.put(KEY_LINE, clampLevel(levels.lineHeightLevel));
    this.put(KEY_MARGIN, clampLevel(levels.marginLevel));
    this.put(KEY_WEIGHT, clampWeightLevel(levels.fontWeightLevel));
    this.flush();
  }

  saveTheme(theme: ThemeName): void {
    this.theme = normalizeTheme(theme);
    this.put(KEY_THEME, this.theme);
    this.flush();
  }

  /** TXT 去广告（默认开） */
  isPurifyOn(): boolean {
    return this.purifyOn;
  }

  setPurify(on: boolean): void {
    this.purifyOn = on;
    this.put(KEY_PURIFY, on);
    this.flush();
  }

  /** 'off' | 's2t' | 't2s' */
  getConvertMode(): string {
    return this.convertMode;
  }

  setConvertMode(mode: string): void {
    this.convertMode = mode;
    this.put(KEY_CONVERT, mode);
    this.flush();
  }

  private put(key: string, value: preferences.ValueType): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'prefs put failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 落盘；失败只记日志（偏好丢了不该影响读书） */
  private flush(): void {
    if (this.store === null) {
      return;
    }
    this.store.flush().catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'prefs flush failed: %{public}s', e.message);
    });
  }
}
