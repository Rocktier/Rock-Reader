/**
 * 系统深浅色接入 —— **纯逻辑，零设备 API**，CI 可单测（2026-11-08 P0-1）。
 *
 * 照抄 Rock私记 `common/Appearance.ets` 修过的三个坑（2026-10-25 / 10-26 华为复评）：
 *   ① 跟随系统档不能只判 `isDark(mode) === true`，null 会让它恒为浅色；
 *   ② 系统深浅只在切模式那一刻读一次 ⇒ 系统后来切深色应用纹丝不动，
 *      必须在 `onConfigurationUpdate` 用**回调参数**重算；
 *   ③ 换色板走 AppStorage，**绝不调运行时 setColorMode**（会重建 UIContent、丢页面栈，
 *      2026-10-16 私记实测切完直接退回桌面）。
 *
 * 与私记的差别：本应用色板是 TS 里的 `Palette`（四套纸色 + 自动昼夜），
 * 不是 `resources/dark/` 限定符，所以这里只负责「系统深浅数值 → 生效主题」的纯判断，
 * 不碰 preferences、不碰 AppStorage、不引任何 `@kit.*`。
 */
import { THEME_SYSTEM, ThemeName, resolveTheme } from './Theme';

/**
 * 系统 `Configuration.colorMode` 的取值（来自 `ConfigurationConstant.ColorMode`）。
 * 抄成常量是为了让判定留在纯逻辑层 —— CI 上跑不了 `@kit.AbilityKit`。
 * ⚠️ 改前对一眼 SDK：`NOT_SET = -1, DARK = 0, LIGHT = 1`（**DARK 是 0 不是 1**）。
 */
export const COLOR_MODE_NOT_SET: number = -1;
export const COLOR_MODE_DARK: number = 0;
export const COLOR_MODE_LIGHT: number = 1;

/** 系统当前是否深色。NOT_SET / LIGHT / 读不到一律回落浅色（不会比现状更差）。 */
export function isSystemDarkColorMode(colorMode: number | undefined): boolean {
  return colorMode === COLOR_MODE_DARK;
}

/**
 * AppStorage 里存系统深浅的键名。
 *
 * ⚠️ 页面侧 `@StorageProp('systemDark')` **必须写字面量**（ArkUI 装饰器要求），
 *    不能引用这个常量 —— 所以这里只给 EntryAbility 的 `setOrCreate` / `Set` 用，
 *    两边字符串要一起改。
 */
export const SYSTEM_DARK_KEY: string = 'systemDark';

/**
 * 跟随系统档下，色板要不要重算。
 *
 * 只判断"该不该动"，不动状态：显式选了纸色 / 深色 / 自动昼夜的人**不该被系统覆盖**；
 * 系统深浅没变、或解析出的生效主题与当前一致时也不必动（省一次无谓的 UI 刷新）。
 */
export function followSystemNeedsRefresh(
  theme: ThemeName, systemDark: boolean, hour: number, activeTheme: ThemeName
): boolean {
  if (theme !== THEME_SYSTEM) {
    return false;
  }
  return resolveTheme(theme, hour, systemDark) !== activeTheme;
}

/**
 * 六格真值表用的纯函数：给定用户意图与系统深浅，直接返回生效主题名。
 * 页面不必自己拼 `if`，单测也不用模拟 AppStorage。
 */
export function effectiveTheme(theme: ThemeName, hour: number, systemDark: boolean): ThemeName {
  return resolveTheme(theme, hour, systemDark);
}
