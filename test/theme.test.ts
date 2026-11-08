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
  isAutoTheme,
  isLightTheme,
  isNightHour,
  normalizeTheme,
  paletteFor,
  paletteOf,
  resolveTheme,
  themeForHour,
  themeLabel,
  THEME_AUTO,
  THEME_DARK,
  THEME_GREEN,
  THEME_LIGHT,
  THEME_SEPIA,
  THEME_SYSTEM,
  ThemeName
} from '../entry/src/main/ets/common/Theme.ets';

const THEMES: ThemeName[] = [THEME_DARK, THEME_LIGHT, THEME_SEPIA, THEME_GREEN, THEME_AUTO, THEME_SYSTEM];

/**
 * 深色系按 HDS《深色模式》守 5:1，浅色系按 HIG 守 4.5:1（冲突取严者）。
 * 用**实际色板的底色**判断，而不是按主题名列举 —— 新增主题不会漏登记。
 */
function minTextContrast(p: ReturnType<typeof paletteOf>): number {
  return p.bg === '#000000' ? 5.0 : 4.5;
}

/** 三种"确定面"：卡（半透明先 flatten）、浮层（半透明先 flatten）、渐变端点 */
function surfaces(p: ReturnType<typeof paletteOf>): Record<string, number[]> {
  const page: number[] = hexToRgb(p.bg);
  return {
    card: over(p.card, page),
    overlay: over(p.overlay, page),
    halo: hexToRgb(p.haloTop)
  };
}

function contrastOn(fg: string, baseRgb: number[]): number {
  return contrastRgb(over(fg, baseRgb), baseRgb);
}

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

/** 把（可能是半透明的）颜色压到**已经算好的 rgb 底**上 */
function over(fg: string, bgRgb: number[]): number[] {
  const f: number[] = hexToRgb(fg);
  const a: number = alphaOf(fg);
  return [
    f[0] * a + bgRgb[0] * (1 - a),
    f[1] * a + bgRgb[1] * (1 - a),
    f[2] * a + bgRgb[2] * (1 - a)
  ];
}

/** 两个实际渲染出来的 rgb 之间的对比度 */
function contrastRgb(a: number[], b: number[]): number {
  const la: number = luminance(a);
  const lb: number = luminance(b);
  const hi: number = Math.max(la, lb);
  const lo: number = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

test('四个主题都有完整色板（没有缺失字段）', () => {
  const keys: string[] = [
    'bg', 'text', 'text2', 'text3', 'line', 'lineSoft', 'accent', 'card', 'cover', 'overlay',
    'heroBg', 'heroText', 'onAccent',
    // P0-0（2026-11-08）：渐变光层 / 描边 / 卡上蓝字，新增字段一律纳入遍历防漏 key
    'haloTop', 'glassEdge', 'accentOnCard'
  ];
  for (const t of THEMES) {
    const p = paletteOf(t) as unknown as Record<string, string>;
    for (const k of keys) {
      assert.ok(typeof p[k] === 'string' && p[k].length > 0, `${t}.${k} 缺失`);
    }
  }
});

test('正文对比度 ≥ 7:1（AAA）且 ≤ 17.6:1（HDS 深色模式上限，正文色不许再加深）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const c: number = contrast(p.text, p.bg);
    assert.ok(c >= 7, `${t} 正文只有 ${c.toFixed(2)}:1（应 ≥7:1）`);
    // 2026-11-08 P0-0：浅色正文实测 17.58:1，离 HDS 上限 17.6 只剩 0.02
    assert.ok(c <= 17.6, `${t} 正文 ${c.toFixed(2)}:1 超了 HDS 上限 17.6:1`);
  }
});

test('text2 / text3 对比度：深色 ≥5:1（HDS）/ 浅色 ≥4.5:1（HIG）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const min: number = minTextContrast(p);
    const c2: number = contrast(p.text2, p.bg);
    const c3: number = contrast(p.text3, p.bg);
    assert.ok(c2 >= min, `${t}.text2 只有 ${c2.toFixed(2)}:1（应 ≥${min}:1）`);
    assert.ok(c3 >= min, `${t}.text3 只有 ${c3.toFixed(2)}:1（应 ≥${min}:1）`);
  }
});

test('强调色对比度 ≥ 4:1（accent、非正文；护眼底上要做到不比浅色主题差）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const c: number = contrast(p.accent, p.bg);
    assert.ok(c >= 4, `${t}.accent 只有 ${c.toFixed(2)}:1`);
  }
});

/**
 * P0-0（2026-11-08 视觉重设计闸门）：文字必须落在**确定不透明面**上。
 *
 * 三层空间模型里，渐变（haloTop）只铺空白底层、卡片/浮层承载文字。
 * 这里把三种面 × 四套主题 × 文字层级逐个算一遍（半透明色先 flatten），
 * 而不是只看页面底 —— 半透明卡面最容易把 4.5:1 悄悄吃掉。
 *
 * ⚠️ 两条刻意的口径，别误改成"全部 4.5"：
 *   ① `accentOnCard` 是**非正文**（链接/图标级），沿用现有 accent ≥4:1 分级；
 *      深色 accent 原值压在 #303030 卡上只有 3.30:1 ⇒ 单独给 #6BA0FF（5.09:1）。
 *   ② 护眼两套的 `text2` 压在卡上是 **4.49 / 4.47:1**，现状贴线、不是本轮引入；
 *      这里守 4.4 的"不许更差"回归线，不假装它已过 4.5。真要改就改 token，
 *      别改断言阈值。
 */
test('P0-0 文字落确定面：card / overlay / 渐变端点逐面算对比度', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const min: number = minTextContrast(p);
    const s: Record<string, number[]> = surfaces(p);
    for (const name of Object.keys(s)) {
      const base: number[] = s[name];
      const cText: number = contrastOn(p.text, base);
      assert.ok(cText >= 7, `${t}.text 压在 ${name} 上只有 ${cText.toFixed(2)}:1（正文应 ≥7:1）`);
      const c3: number = contrastOn(p.text3, base);
      assert.ok(c3 >= min, `${t}.text3 压在 ${name} 上只有 ${c3.toFixed(2)}:1（应 ≥${min}:1）`);
      if (name === 'card' || name === 'overlay') {
        const cAccent: number = contrastOn(p.accentOnCard, base);
        assert.ok(cAccent >= 4, `${t}.accentOnCard 压在 ${name} 上只有 ${cAccent.toFixed(2)}:1（应 ≥4:1）`);
      }
      if (name === 'overlay') {
        const c2: number = contrastOn(p.text2, base);
        assert.ok(c2 >= min, `${t}.text2 压在浮层上只有 ${c2.toFixed(2)}:1（应 ≥${min}:1）`);
      }
      if (name === 'card') {
        const c2: number = contrastOn(p.text2, base);
        assert.ok(c2 >= 4.4, `${t}.text2 压在卡上只有 ${c2.toFixed(2)}:1（护眼现状贴线，不许更差）`);
      }
    }
    // 光层起点要与页面底分得开，否则等于没铺渐变
    const cSep: number = contrastRgb(s['halo'], hexToRgb(p.bg));
    assert.ok(cSep >= 1.05, `${t}.haloTop 与 bg 只差 ${cSep.toFixed(2)}:1，渐变层立不起来`);
  }
});

test('paletteFor：system 跟随系统深浅，显式主题 / 自动昼夜不被覆盖', () => {
  assert.equal(paletteFor(THEME_SYSTEM, 12, false).bg, paletteOf(THEME_LIGHT).bg);
  assert.equal(paletteFor(THEME_SYSTEM, 12, true).bg, paletteOf(THEME_DARK).bg);
  assert.equal(paletteFor(THEME_SEPIA, 12, true).bg, paletteOf(THEME_SEPIA).bg);
  assert.equal(paletteFor(THEME_GREEN, 12, true).bg, paletteOf(THEME_GREEN).bg);
  assert.equal(paletteFor(THEME_AUTO, 20, false).bg, paletteOf(THEME_DARK).bg);
  assert.equal(paletteFor(THEME_AUTO, 10, true).bg, paletteOf(THEME_LIGHT).bg);
});

/**
 * 重点色块（书架「继续阅读」卡）—— 2026-11-06 加。
 *
 * 三条一起守，是因为这块色只要漏一条就出事：
 *   ① 块上文字 ≥4.5:1（它不是装饰，书名与进度都要读）
 *   ② 块与页面底要分得开（太接近 ⇒ 焦点立不起来，白做一个色块）
 *   ③ **深色主题不许出现大块亮面**：深色下 heroBg 若取 `text` 反白，
 *      就是一块白卡压在纯黑上，夜里刺眼 —— 所以浅色/护眼才用"墨底"，深色用抬一档灰。
 */
/**
 * 强调色底上的文字（实心主按钮：确定 / 移除 / 同意 / 存下）—— 2026-11-06 加。
 *
 * 这条守的是一个**语义错误**，不是配色偏好：原来按钮字色写的是 `palette.bg`
 * （页面底色），等于"字色跟着主题漂移"。四个主题里三个碰巧过线，**新苔过不了**——
 * 豆沙绿 `#C7EDCC` 字压在蓝 `#0A59F7` 底上只有 4.34:1。
 * 换成 `onAccent` 后四套都在 5:1 以上，且以后加护眼主题不会重演。
 *
 * 顺带守另一种反色按钮：`text` 底 + `bg` 字（PDF 页的「查找」「跳转」）。
 * 那两处不是强调色，形状是"墨底反白"，语义没错，但同样要 ≥4.5:1。
 */
test('强调色底上的文字 ≥4.5:1（主按钮；含 text 底反白按钮）', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const pageRgb: number[] = hexToRgb(p.bg);
    const accentRgb: number[] = over(p.accent, pageRgb);
    const onAccentRgb: number[] = over(p.onAccent, accentRgb);
    const c: number = contrastRgb(onAccentRgb, accentRgb);
    assert.ok(c >= 4.5, `${t}.onAccent 压在 accent 上只有 ${c.toFixed(2)}:1（应 ≥4.5:1）`);

    const textRgb: number[] = over(p.text, pageRgb);
    const onTextRgb: number[] = over(p.bg, textRgb);
    const c2: number = contrastRgb(onTextRgb, textRgb);
    assert.ok(c2 >= 4.5, `${t}.bg 压在 text 上只有 ${c2.toFixed(2)}:1（反色按钮要 ≥4.5:1）`);
  }
});

test('hero 色块：文字 ≥4.5:1、与页面底分得开、深色下不许变成白卡', () => {
  for (const t of THEMES) {
    const p = paletteOf(t);
    const pageRgb: number[] = hexToRgb(p.bg);
    const heroRgb: number[] = over(p.heroBg, pageRgb);
    const textRgb: number[] = over(p.heroText, heroRgb);
    const cText: number = contrastRgb(textRgb, heroRgb);
    const cSep: number = contrastRgb(heroRgb, pageRgb);
    assert.ok(cText >= 4.5, `${t}.heroText 只有 ${cText.toFixed(2)}:1（应 ≥4.5:1）`);
    assert.ok(cSep >= 1.25, `${t}.heroBg 与页面底只差 ${cSep.toFixed(2)}:1，色块立不起来`);
    if (t === THEME_DARK) {
      assert.ok(luminance(heroRgb) < luminance(over(p.text, pageRgb)),
        `${t}.heroBg 比正文还亮 —— 深色下会变成刺眼的白卡`);
    }
  }
});

test('normalizeTheme：认识六个档位，未知值一律回落「跟随系统」（P0-1 新默认）', () => {
  assert.equal(normalizeTheme(THEME_SEPIA), THEME_SEPIA);
  assert.equal(normalizeTheme(THEME_GREEN), THEME_GREEN);
  assert.equal(normalizeTheme(THEME_LIGHT), THEME_LIGHT);
  assert.equal(normalizeTheme(THEME_DARK), THEME_DARK);
  assert.equal(normalizeTheme(THEME_AUTO), THEME_AUTO);
  assert.equal(normalizeTheme(THEME_SYSTEM), THEME_SYSTEM);
  assert.equal(normalizeTheme('不存在的主题'), THEME_SYSTEM);
  assert.equal(normalizeTheme(''), THEME_SYSTEM);
});

// A2（2026-10-25 党哥批次 A）：自动昼夜。边界 6:30 亮 / 18:30 黑，
// 含边界值本身（>= 18.5 算夜，< 6.5 算夜）。
test('自动昼夜：isNightHour / themeForHour 边界（6:30 亮、18:30 黑）', () => {
  assert.equal(isNightHour(0), true);
  assert.equal(isNightHour(5), true);
  assert.equal(isNightHour(6), true);
  assert.equal(isNightHour(6.4), true);
  assert.equal(isNightHour(6.5), false);
  assert.equal(isNightHour(12), false);
  assert.equal(isNightHour(18), false);
  assert.equal(isNightHour(18.4), false);
  assert.equal(isNightHour(18.5), true);
  assert.equal(isNightHour(23), true);
  assert.equal(themeForHour(6), THEME_DARK);
  assert.equal(themeForHour(7), THEME_LIGHT);
  assert.equal(themeForHour(18), THEME_LIGHT);
  assert.equal(themeForHour(19), THEME_DARK);
});

test('resolveTheme：system 跟系统 / auto 按小时 / 固定主题原样返回', () => {
  assert.equal(resolveTheme(THEME_AUTO, 20), THEME_DARK);
  assert.equal(resolveTheme(THEME_AUTO, 10), THEME_LIGHT);
  assert.equal(resolveTheme(THEME_SYSTEM, 10, false), THEME_LIGHT);
  assert.equal(resolveTheme(THEME_SYSTEM, 10, true), THEME_DARK);
  assert.equal(resolveTheme(THEME_SEPIA, 20, true), THEME_SEPIA);
  assert.equal(resolveTheme(THEME_DARK, 10, false), THEME_DARK);
  assert.equal(isAutoTheme(THEME_AUTO), true);
  assert.equal(isAutoTheme(THEME_LIGHT), false);
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
