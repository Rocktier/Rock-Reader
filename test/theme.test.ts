/**
 * 主题色板（纯逻辑，可 CI 单测）
 *
 * 守的是**可读性底线**，不是"好不好看"：
 *   护眼主题用的是**半透明**色板（`#AA` + RGB），人工看截图觉得"差不多"，
 *   算出来可能只有 3:1 —— 所以对比度必须由测试断言兜住，不能靠眼睛。
 * 阈值依据 WCAG 2.1：正文 ≥7:1（AAA，久读）、次级/三级文字 ≥4.5:1（AA，功能性信息）。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  isLightTheme,
  normalizeTheme,
  paletteOf,
  themeLabel,
  THEME_DARK,
  THEME_GREEN,
  THEME_LIGHT,
  THEME_SEPIA,
  ThemeName
} from '../entry/src/main/ets/common/Theme.ets';

const THEMES: ThemeName[] = [THEME_DARK, THEME_LIGHT, THEME_SEPIA, THEME_GREEN];

/** '#RRGGBB' 或 '#AARRGGBB' → [r,g,b]（半透明时丢掉 alpha 部分） */
function hexToRgb(hex: string): number[] {
  const h: string = hex.length === 9 ? hex.substring(3) : hex.substring(1);
  return [
    parseInt(h.substring(0, 2), 16),
    parseInt(h.substring(2, 4), 16),
    parseInt(h.substring(4, 6), 16)
  ];
}

function alphaOf(hex: string): number {
  return hex.length === 9 ? parseInt(hex.substring(1, 3), 16) / 255 : 1;
}

/** 半透明前景按 alpha 混到背景上 —— 这才是 ArkUI 真正渲染出来的颜色 */
function flatten(fg: string, bg: string): number[] {
  const f: number[] = hexToRgb(fg);
  const b: number[] = hexToRgb(bg);
  const a: number = alphaOf(fg);
  return [
    f[0] * a + b[0] * (1 - a),
    f[1] * a + b[1] * (1 - a),
    f[2] * a + b[2] * (1 - a)
  ];
}

function channel(v: number): number {
  const s: number = v / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

function luminance(rgb: number[]): number {
  return 0.2126 * channel(rgb[0]) + 0.7152 * channel(rgb[1]) + 0.0722 * channel(rgb[2]);
}

/** WCAG 相对亮度对比度（1 ~ 21） */
function contrast(fg: string, bg: string): number {
  const a: number = luminance(flatten(fg, bg));
  const b: number = luminance(hexToRgb(bg));
  const hi: number = Math.max(a, b);
  const lo: number = Math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

test('四个主题都有完整色板（没有缺失字段）', () => {
  const keys: string[] = ['bg', 'text', 'text2', 'text3', 'line', 'lineSoft', 'red', 'card', 'cover', 'overlay'];
  for (const t of THEMES) {
    const p = paletteOf(t) as unknown as Record<string, string>;
    for (const k of keys) {
      assert.ok(typeof p[k] === 'string' && p[k].length > 0, `${t}.${k} 缺失`);
    }
  }
});

test('正文对比度 ≥ 7:1（AAA —— 正文要久读，护眼主题更该如此）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const c: number = contrast(p.text, p.bg);
    assert.ok(c >= 7, `${t} 正文只有 ${c.toFixed(2)}:1（应 ≥7:1）`);
  }
});

test('text2 / text3 对比度 ≥ 4.5:1（AA —— 页码、章节号是功能性信息）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const c2: number = contrast(p.text2, p.bg);
    const c3: number = contrast(p.text3, p.bg);
    assert.ok(c2 >= 4.5, `${t}.text2 只有 ${c2.toFixed(2)}:1`);
    assert.ok(c3 >= 4.5, `${t}.text3 只有 ${c3.toFixed(2)}:1`);
  }
});

test('红点对比度 ≥ 4:1（强调色、非正文；护眼底上要做到不比浅色主题差）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const c: number = contrast(p.red, p.bg);
    assert.ok(c >= 4, `${t}.red 只有 ${c.toFixed(2)}:1`);
  }
});

test('normalizeTheme：认识四个主题，未知值一律回落深色', () => {
  assert.equal(normalizeTheme(THEME_SEPIA), THEME_SEPIA);
  assert.equal(normalizeTheme(THEME_GREEN), THEME_GREEN);
  assert.equal(normalizeTheme(THEME_LIGHT), THEME_LIGHT);
  assert.equal(normalizeTheme(THEME_DARK), THEME_DARK);
  assert.equal(normalizeTheme('不存在的主题'), THEME_DARK);
  assert.equal(normalizeTheme(''), THEME_DARK);
});

test('isLightTheme：只有深色算深色系（以后新增护眼色自动归浅色，不会漏登记）', () => {
  assert.equal(isLightTheme(THEME_DARK), false);
  assert.equal(isLightTheme(THEME_LIGHT), true);
  assert.equal(isLightTheme(THEME_SEPIA), true);
  assert.equal(isLightTheme(THEME_GREEN), true);
  assert.equal(isLightTheme('将来新增的护眼色'), true);
});

test('themeLabel：四个主题都有名字且互不相同（防"抽屉一个叫法、别处另一个"）', () => {
  const labels: string[] = THEMES.map((t: ThemeName) => themeLabel(t));
  for (const l of labels) {
    assert.ok(l.length > 0, '主题名不该为空');
  }
  assert.equal(new Set(labels).size, labels.length,
    `主题名必须互不相同，实际：${labels.join(' / ')}`);
});
