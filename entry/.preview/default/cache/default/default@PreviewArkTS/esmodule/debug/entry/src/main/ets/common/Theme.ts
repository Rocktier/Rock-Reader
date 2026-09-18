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
    /** 三级文字（数码、页码） */
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
}
const DARK: Palette = {
    bg: '#000000',
    text: '#FFFFFF',
    text2: '#8CFFFFFF',
    text3: '#52FFFFFF',
    line: '#24FFFFFF',
    lineSoft: '#12FFFFFF',
    red: '#FF4A3D',
    card: '#08FFFFFF',
    cover: '#1A1A1A'
};
const LIGHT: Palette = {
    bg: '#FFFFFF',
    text: '#000000',
    text2: '#8C000000',
    text3: '#52000000',
    line: '#24000000',
    lineSoft: '#12000000',
    red: '#E64537',
    card: '#08000000',
    cover: '#EBEBEB'
};
export function paletteOf(theme: ThemeName): Palette {
    return theme === THEME_LIGHT ? LIGHT : DARK;
}
export function normalizeTheme(value: string): ThemeName {
    return value === THEME_LIGHT ? THEME_LIGHT : THEME_DARK;
}
