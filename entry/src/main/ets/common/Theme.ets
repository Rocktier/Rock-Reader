/**
 * 主题与色板（家族 Nothing OS 风格）
 * 设计依据：docs/v1-design.md §8 色板表
 *
 * 为什么色板写在 TS 里、而不是 color.json：
 *   主题由用户在应用内选择（昼/夜），**与系统深浅色解耦**，必须能在运行时切换；
 *   资源限定符（resources/dark/）只能跟随系统，做不到"用户自己挑"。
 *   因此 window 背景等系统级颜色仍用资源（见 color.json），页面内容一律读这里的 Palette。
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
  /** 正文 / 主强调 */
  text: string;
  /** 次级文字 */
  text2: string;
  /**
   * 三级文字（数码、页码、章节号）。
   * 2026-09-19 设计审查：原 0.32 在黑底上只有约 2.7:1，**低于 WCAG AA 4.5:1**；
   * 它承担的是页码/章节号这类**功能性**信息，故提亮到现在这档（深色 ≈4.5:1，浅色 ≈4.5:1）。
   * 纯装饰性的灰仍可用 text2 之外的自定义值，不再压这个 token。
   */
  text3: string;
  /** 描边 */
  line: string;
  /** 极淡分隔线 */
  lineSoft: string;
  /** 家族红（红点） */
  red: string;
  /** 卡片底 */
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
  text: '#FFFFFF',
  text2: '#8CFFFFFF',
  text3: '#75FFFFFF',
  line: '#24FFFFFF',
  lineSoft: '#12FFFFFF',
  red: '#FF4A3D',
  card: '#08FFFFFF',
  cover: '#1A1A1A',
  overlay: '#EB000000'
};

const LIGHT: Palette = {
  bg: '#FFFFFF',
  text: '#000000',
  text2: '#8C000000',
  text3: '#89000000',
  line: '#24000000',
  lineSoft: '#12000000',
  // 浅底上的红必须比深底那支更深，否则红点 / 当前章序号这类小字糊在白底里。
  // 原 #E64537 在纯白上只有 3.98:1（红点承载的是功能性小字，不该低于 AA）→ 加深到 4.67:1
  red: '#D63A2C',
  card: '#08000000',
  cover: '#EBEBEB',
  overlay: '#EBFFFFFF'
};

/**
 * 纸（sepia）。所有对比度都按 WCAG 相对亮度算过（见 test/theme.test.ts 有断言兜底）：
 *   正文 10.9:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1（小字宁可更深）
 * 半透明色是**深褐**的百分比（不是黑）—— 在米黄底上混出来的灰才不发脏。
 */
const SEPIA: Palette = {
  bg: '#F4EFE4',
  text: '#3C3226',
  text2: '#B33C3226',
  text3: '#BF3C3226',
  line: '#243C3226',
  lineSoft: '#123C3226',
  // 浅底上的红要**加深**，否则红点 / 当前章序号这类小字糊在背景里。
  // 比浅色主题的 #E64537 再深一档：纸底 ≈5.5:1、绿底 ≈4.9:1
  red: '#B03226',
  card: '#083C3226',
  cover: '#E4DCCB',
  overlay: '#EBF4EFE4'
};

/** 绿（豆沙绿）。正文 10.5:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1 */
const GREEN: Palette = {
  bg: '#C7EDCC',
  text: '#22331F',
  text2: '#B322331F',
  text3: '#BF22331F',
  line: '#2422331F',
  lineSoft: '#1222331F',
  red: '#C4382B',
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
