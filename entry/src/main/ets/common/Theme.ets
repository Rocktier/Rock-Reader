/**
 * 主题与色板（**鸿蒙原生 HDS**）
 * 设计依据：docs/v1-design.md §8（2026-10-10 起基调改为鸿蒙原生，见 task_plan Phase 21）
 *
 * 为什么色板写在 TS 里、而不是 color.json：
 *   主题由用户在应用内选择（昼/夜），**与系统深浅色解耦**，必须能在运行时切换；
 *   资源限定符（resources/dark/）只能跟随系统，做不到"用户自己挑"。
 *   因此 window 背景等系统级颜色仍用资源（见 color.json），页面内容一律读这里的 Palette。
 *
 * ⚠️ 2026-10-10 基调变更（党哥拍板）：抛弃第一版 Nothing OS 表述，一切往鸿蒙原生靠。
 *   本文件按华为官方《色彩-视觉风格》对齐：
 *     - 深色背景 #000000（官方「背景色(首页、设置页)」深色值）／深色卡片 #303030
 *     - 文本走官方 α 分级：主文本 86%、次级 60%
 *     - 强调色 = 官方系统高亮色：深色 #317AF7、浅色 #0A59F7
 *   **唯一的有意偏离**：官方三级文本是 40%，但 40% 白在纯黑底只有 3.66:1（低于 WCAG AA 4.5:1），
 *   而 text3 承担页码/章节号这类**功能性**信息（theme.test.ts 有断言兜底），
 *   故深色取 50%（5.28:1）、浅色取 56%（≈4.94:1）—— 层级感保留，AA 不破。
 */

/** 'dark' | 'light'（不用字面量联合类型，保证 ArkTS 各版本都能编译） */
export type ThemeName = string;

export const THEME_DARK: string = 'dark';
export const THEME_LIGHT: string = 'light';
/**
 * 纸（sepia）：米黄底 + **深褐**字。
 * 来源：Kindle / Apple Books 的 sepia 主题就是这一路 —— 关键不是"换个黄底"，
 * 而是**正文不用纯黑**（纯白配纯黑是 21:1，太刺眼），用深褐把对比降到 ~11:1。
 */
export const THEME_SEPIA: string = 'sepia';
/**
 * 绿（豆沙绿 `#C7EDCC`）：中文阅读器里最常见的护眼绿
 * （源自流传极广的"电脑护眼色" RGB 199/237/204）。
 */
export const THEME_GREEN: string = 'green';

export interface Palette {
  /** 页面背景 */
  bg: string;
  /** 正文 / 主强调（官方：深色 #FFFFFF 86%） */
  text: string;
  /** 次级文字（官方：60%） */
  text2: string;
  /**
   * 三级文字（数码、页码、章节号）。
   * 官方给的是 40%，但**在本应用里不作数**：40% 白在纯黑底只有 3.66:1，低于 WCAG AA 4.5:1，
   * 而它承担的是页码/章节号这类**功能性**信息（test/theme.test.ts 断言 ≥4.5:1）。
   * 故取「能过 AA 的最低档」：深色 50%（5.28:1）、浅色 56%（≈4.94:1）。
   * 纯装饰性的灰仍可用 text2 之外的自定义值，不再压这个 token。
   */
  text3: string;
  /** 描边 */
  line: string;
  /** 极淡分隔线 */
  lineSoft: string;
  /**
   * **强调色**（原名 `red`，2026-10-10 随原生化改名并换色）。
   * 取官方系统高亮色：**深色 #317AF7 / 浅色 #0A59F7**（官方《色彩-视觉风格》）。
   * 用于当前章序号、进度、主行动等"要看重"的位置。
   */
  accent: string;
  /** 卡片底（官方深色卡片 #303030；浅色用官方浅色灰 #F1F3F5） */
  card: string;
  /** 书封灰底 */
  cover: string;
  /**
   * 浮层底（阅读页上下细栏、目录面板）。
   * 比 bg 略透（8%）：底下正文已被 scrim 压暗，透出来的是"纵深"而不是干扰文字。
   * 不上 blur —— backdrop 模糊吃 GPU，撞家族铁律 1（极致快）。
   */
  overlay: string;
}

const DARK: Palette = {
  bg: '#000000',
  text: '#DBFFFFFF',
  text2: '#99FFFFFF',
  text3: '#80FFFFFF',
  line: '#24FFFFFF',
  lineSoft: '#12FFFFFF',
  accent: '#317AF7',
  card: '#303030',
  cover: '#1A1A1A',
  overlay: '#EB000000'
};

const LIGHT: Palette = {
  bg: '#FFFFFF',
  text: '#E6000000',
  text2: '#99000000',
  // 浅底上不能照搬官方 40%（只有 3.98:1）；56% 是能过 AA 的最低档（≈4.94:1）
  text3: '#8F000000',
  line: '#24000000',
  lineSoft: '#12000000',
  // 官方浅色系统高亮 #0A59F7（纯白上 5.56:1）
  accent: '#0A59F7',
  card: '#F1F3F5',
  cover: '#EBEBEB',
  overlay: '#EBFFFFFF'
};

/**
 * 纸（sepia）。所有对比度都按 WCAG 相对亮度算过（见 test/theme.test.ts 有断言兜底）：
 *   正文 10.9:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1（小字宁可更深）
 * 半透明色是**深褐**的百分比（不是黑）—— 在米黄底上混出来的灰才不发脏。
 * 强调色用官方浅色高亮 #0A59F7（纸底 ≈4.88:1，过 AA 的 4:1 底线）。
 */
const SEPIA: Palette = {
  bg: '#F4EFE4',
  text: '#3C3226',
  text2: '#B33C3226',
  text3: '#BF3C3226',
  line: '#243C3226',
  lineSoft: '#123C3226',
  accent: '#0A59F7',
  card: '#083C3226',
  cover: '#E4DCCB',
  overlay: '#EBF4EFE4'
};

/** 绿（豆沙绿）。正文 10.5:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1；强调色 #0A59F7（绿底 ≈4.34:1） */
const GREEN: Palette = {
  bg: '#C7EDCC',
  text: '#22331F',
  text2: '#B322331F',
  text3: '#BF22331F',
  line: '#2422331F',
  lineSoft: '#1222331F',
  accent: '#0A59F7',
  card: '#0822331F',
  cover: '#AFD9B4',
  overlay: '#EBC7EDCC'
};

export function paletteOf(theme: ThemeName): Palette {
  if (theme === THEME_LIGHT) {
    return LIGHT;
  }
  if (theme === THEME_SEPIA) {
    return SEPIA;
  }
  if (theme === THEME_GREEN) {
    return GREEN;
  }
  return DARK;
}

/** 未知值一律回落深色（老数据 / 脏值不会渲染出 undefined 色板） */
export function normalizeTheme(value: string): ThemeName {
  if (value === THEME_LIGHT || value === THEME_SEPIA || value === THEME_GREEN) {
    return value;
  }
  return THEME_DARK;
}

/**
 * 是否"浅色系" —— 决定系统状态栏文字颜色与系统 colorMode。
 *
 * 刻意写成 **"非 dark 即浅色"** 而不是逐个列举：以后再加护眼色不用回来改这里，
 * 也不会出现"新主题忘了登记 → 状态栏白字白底"这种事故（SystemBar.ets 头部记的那个 bug）。
 */
export function isLightTheme(theme: ThemeName): boolean {
  return theme !== THEME_DARK;
}

/**
 * 主题的显示名（抽屉芯片用）。
 *
 * **放在这里而不是散在 UI 代码里**：名字和色板是一套，改名字不该去翻页面文件；
 * 也避免"抽屉里叫旧纸、别处写成纸色"这种漂移。
 *
 * 深色 子夜 ／ 浅色 晴昼 ／ 纸 旧纸 ／ 绿 新苔（党哥 2026-09-20 选）
 */
export function themeLabel(theme: ThemeName): string {
  if (theme === THEME_SEPIA) {
    return '旧纸';
  }
  if (theme === THEME_GREEN) {
    return '新苔';
  }
  if (theme === THEME_LIGHT) {
    return '晴昼';
  }
  return '子夜';
}
