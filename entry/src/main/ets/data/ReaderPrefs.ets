/**
 * 阅读偏好（Preferences）
 * 设计依据：docs/v1-design.md §4 —— 排版档位、主题存 Preferences（书在 relationalStore）
 *
 * 只存**档位序号**与主题名，不存任何数值 —— 数值唯一真源在 common/LayoutStyle.ets。
 * 用同步 API（getPreferencesSync / getSync / putSync）：阅读页初始化路径上不能有 await。
 */
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clampLevel, DEFAULT_LEVELS, LayoutLevels } from '../common/LayoutStyle';
import { normalizeTheme, THEME_DARK, ThemeName } from '../common/Theme';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const STORE_NAME: string = 'rockreader_prefs';
const KEY_FONT: string = 'font_level';
const KEY_LINE: string = 'line_level';
const KEY_MARGIN: string = 'margin_level';
const KEY_THEME: string = 'theme';

export class ReaderPrefs {
  private store: preferences.Preferences | null = null;
  private levels: LayoutLevels = {
    fontSizeLevel: DEFAULT_LEVELS.fontSizeLevel,
    lineHeightLevel: DEFAULT_LEVELS.lineHeightLevel,
    marginLevel: DEFAULT_LEVELS.marginLevel
  };
  private theme: ThemeName = THEME_DARK;

  /** 幂等：重复调用直接返回 */
  open(ctx: Context): void {
    if (this.store !== null) {
      return;
    }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
      this.store = store;
      this.levels = {
        fontSizeLevel: this.readLevel(store, KEY_FONT),
        lineHeightLevel: this.readLevel(store, KEY_LINE),
        marginLevel: this.readLevel(store, KEY_MARGIN)
      };
      this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
    } catch (e) {
      // 读不到就用默认档位（3/3/3 + 深色）—— 绝不因为偏好读取失败而读不了书
      hilog.error(DOMAIN, TAG, 'prefs open failed: %{public}s', JSON.stringify(e));
    }
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
    this.levels = {
      fontSizeLevel: this.readLevel(store, KEY_FONT),
      lineHeightLevel: this.readLevel(store, KEY_LINE),
      marginLevel: this.readLevel(store, KEY_MARGIN)
    };
    this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
  }

  getLevels(): LayoutLevels {
    return this.levels;
  }

  getTheme(): ThemeName {
    return this.theme;
  }

  saveLevels(levels: LayoutLevels): void {
    this.levels = levels;
    this.put(KEY_FONT, clampLevel(levels.fontSizeLevel));
    this.put(KEY_LINE, clampLevel(levels.lineHeightLevel));
    this.put(KEY_MARGIN, clampLevel(levels.marginLevel));
    this.flush();
  }

  saveTheme(theme: ThemeName): void {
    this.theme = normalizeTheme(theme);
    this.put(KEY_THEME, this.theme);
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
