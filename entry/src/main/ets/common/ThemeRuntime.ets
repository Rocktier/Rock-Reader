/**
 * 页面取色板的**统一入口**（2026-11-08 P0-1）。
 *
 * 为什么要有这一层：七个页面各自 `@State palette`，而"用户意图"里多了
 * `system` / `auto` 两种**不能直接取色板**的档位。若各页面自己拼
 * `paletteOf(this.theme)`，system 会恒回落深色 —— 白天又是全黑。
 *
 * 这里只读全局状态、不持有状态；页面侧的响应式由
 * `@StorageProp('systemDark') @Watch(...)` 负责，系统切深浅时重调本函数换 palette。
 * ⚠️ 键名必须与 `Appearance.ets` 的 `SYSTEM_DARK_KEY` 一致（装饰器只能写字面量）。
 */
import { Palette, ThemeName, paletteFor, resolveTheme } from './Theme';

/** AppStorage 里读系统深浅；读不到 / 脏值当浅色（与 EntryAbility 的回落口径一致） */
export function systemIsDark(): boolean {
  return AppStorage.get<boolean>('systemDark') === true;
}

/** 用户意图 → 当前该用的色板 */
export function currentPalette(theme: ThemeName): Palette {
  return paletteFor(theme, new Date().getHours(), systemIsDark());
}

/** 用户意图 → 当前生效的主题名（状态栏字色、抽屉「当前生效」提示用） */
export function currentEffectiveTheme(theme: ThemeName): ThemeName {
  return resolveTheme(theme, new Date().getHours(), systemIsDark());
}
