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
  red: '#E64537',
  card: '#08000000',
  cover: '#EBEBEB',
  overlay: '#EBFFFFFF'
};

export function paletteOf(theme: ThemeName): Palette {
  return theme === THEME_LIGHT ? LIGHT : DARK;
}

export function normalizeTheme(value: string): ThemeName {
  return value === THEME_LIGHT ? THEME_LIGHT : THEME_DARK;
}
