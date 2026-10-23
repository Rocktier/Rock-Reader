/**
 * 档位表唯一真源 + 页表缓存键（纯逻辑，CI 可跑）
 * 设计依据：docs/v1-design.md §8「档位 → 实际数值」表
 *
 * 这些测试是**防回归护栏**：任何人改表里数值都会在这里被拦住，
 * 因为 spec 明写"表是唯一真源，UI 只写序号"。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  BP_LARGE_VP,
  BP_SMALL_VP,
  clampLevel,
  clampWeightLevel,
  fontSizeFpOf,
  fontWeightOf,
  FORM_MAX_VP,
  formPadOf,
  layoutKey,
  lineHeightRatioOf,
  marginVpOf,
  MAX_LINE_CHARS,
  readingMarginOf,
  shelfColsOf
} from '../entry/src/main/ets/common/LayoutStyle.ets';

test('档位表：字号 14/16/18/20/22 fp，默认档 3 = 18', () => {
  assert.deepEqual([1, 2, 3, 4, 5].map(fontSizeFpOf), [14, 16, 18, 20, 22]);
});

test('档位表：行距倍率 1.4/1.6/1.9/2.2/2.5，默认档 3 = 1.9', () => {
  assert.deepEqual([1, 2, 3, 4, 5].map(lineHeightRatioOf), [1.4, 1.6, 1.9, 2.2, 2.5]);
});

test('档位表：页边距 12/16/20/24/28 vp，默认档 3 = 20', () => {
  assert.deepEqual([1, 2, 3, 4, 5].map(marginVpOf), [12, 16, 20, 24, 28]);
});

test('档位越界与非法值都被夹到合法区间（不许出现 0 档或 99 档）', () => {
  assert.equal(clampLevel(0), 1);
  assert.equal(clampLevel(-3), 1);
  assert.equal(clampLevel(9), 5);
  assert.equal(clampLevel(2.7), 2);
  assert.equal(clampLevel(Number.NaN), 3, 'NaN 必须回落默认档，否则排版会算出 0 宽度');
});

test('layoutKey：档位、实际 px、可用宽度、字体任一变化都必须变（否则错用旧页表）', () => {
  const lv = { fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3, fontWeightLevel: 1 };
  const base = layoutKey(lv, 54, 102.6, 900, '');
  assert.equal(base, layoutKey(lv, 54, 102.6, 900, ''));

  assert.notEqual(base, layoutKey({ fontSizeLevel: 4, lineHeightLevel: 3, marginLevel: 3, fontWeightLevel: 1 }, 54, 102.6, 900, ''));
  assert.notEqual(base, layoutKey({ fontSizeLevel: 3, lineHeightLevel: 4, marginLevel: 3, fontWeightLevel: 1 }, 54, 102.6, 900, ''));
  assert.notEqual(base, layoutKey({ fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 4, fontWeightLevel: 1 }, 54, 102.6, 900, ''));
  assert.notEqual(base, layoutKey(lv, 60, 102.6, 900, ''));
  assert.notEqual(base, layoutKey(lv, 54, 120, 900, ''));
  assert.notEqual(base, layoutKey(lv, 54, 102.6, 860, ''));

  // 系统字体缩放变化 → 档位不变但 px 变：这一条正是 layoutKey 比纯档位签名强的地方
  assert.notEqual(base, layoutKey(lv, 58, 110, 900, ''));

  // 换字体会改断行 → 必须进签名
  assert.notEqual(base, layoutKey(lv, 54, 102.6, 900, 'HarmonyOS Sans'));
  assert.equal(layoutKey(lv, 54, 102.6, 900, ''), layoutKey(lv, 54, 102.6, 900, ''), '空字体 = 系统默认，同 key');
});

test('字重档位：1/2/3 = 400/500/700，越界与 NaN 都夹回合法档', () => {
  assert.deepEqual([1, 2, 3].map(fontWeightOf), [400, 500, 700]);
  assert.equal(clampWeightLevel(0), 1);
  assert.equal(clampWeightLevel(9), 3);
  assert.equal(clampWeightLevel(Number.NaN), 1, 'NaN 必须回落常规，否则字重是 undefined');
});

test('layoutKey：换字重必须变（加粗会改字宽与断行，沿用旧页表会切错页）', () => {
  const lv = { fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3, fontWeightLevel: 1 };
  const base = layoutKey(lv, 54, 102.6, 900, '');
  const bold = { fontSizeLevel: 3, lineHeightLevel: 3, marginLevel: 3, fontWeightLevel: 3 };
  assert.notEqual(base, layoutKey(bold, 54, 102.6, 900, ''));
  assert.equal(base, layoutKey(lv, 54, 102.6, 900, ''));
});

// ── P0-5 大屏适配（纯逻辑守门）────────────────────────────────────────
// 模拟器 shell 没有 wm 命令改不了分辨率，断点靠单测守 —— 改错档位这里直接红。

test('书架断点：手机 3 列 / 平板竖屏 4 列 / 平板横屏 6 列', () => {
  assert.equal(shelfColsOf(360), 3, '典型手机竖屏');
  assert.equal(shelfColsOf(419), 3, '本模拟器宽度档');
  assert.equal(shelfColsOf(BP_SMALL_VP - 1), 3, '断点前一格仍是 3 列');
  assert.equal(shelfColsOf(BP_SMALL_VP), 4, '断点值本身算大屏');
  assert.equal(shelfColsOf(800), 4, '平板竖屏');
  assert.equal(shelfColsOf(BP_LARGE_VP), 6, '断点值本身算大屏');
  assert.equal(shelfColsOf(1280), 6, '平板横屏/折叠屏展开');
});

test('阅读版心：手机竖屏不封顶（边距原样，行为与旧版一致）', () => {
  // 手机 419vp，档位边距 20 ⇒ 正文 379vp；18fp 时封顶值是 630vp，到不了
  assert.equal(readingMarginOf(419, 20, 18), 20);
  assert.equal(readingMarginOf(419, 36, 18), 36, '大边距档也不该被改');
});

test('阅读版心：平板封顶居中（行长 ≤ MAX_LINE_CHARS 个字）', () => {
  const m = readingMarginOf(1000, 20, 18);           // 18fp 时封顶 630vp
  assert.ok(m > 20, '大屏必须加边距把版心收窄');
  const contentVp = 1000 - m * 2;                    // 收窄后的正文宽度
  assert.ok(contentVp <= 18 * MAX_LINE_CHARS + 1, `行长超限：${contentVp}vp`);
  assert.ok(contentVp >= 18 * MAX_LINE_CHARS - 2, '别收得比上限还窄（浪费版面）');
});

test('阅读版心：行长恒定 35 字（字号越大版心越宽，不是固定像素宽）', () => {
  const small = readingMarginOf(1000, 20, 14);       // 小字 ⇒ 35 字占得少 ⇒ 版心窄、边距大
  const large = readingMarginOf(1000, 20, 22);       // 大字 ⇒ 35 字占得多 ⇒ 版心宽、边距小
  assert.ok(small > large, '小字号的边距必须更大（行长字数是恒定的那一个量）');
  assert.equal(1000 - 2 * small, 14 * MAX_LINE_CHARS);
  assert.equal(1000 - 2 * large, 22 * MAX_LINE_CHARS);
});

test('阅读版心：超大字号+窄屏绝不给负边距（宁可行长超限也不能裁字）', () => {
  // 40fp 时 35 字 = 1400vp，比任何屏都宽 ⇒ 必须放弃收窄
  assert.equal(readingMarginOf(419, 20, 40), 20);
  assert.ok(readingMarginOf(419, 20, 40) >= 0, '边距不能为负');
  assert.equal(readingMarginOf(1000, 20, 40), 20);
});

// ── P0-5 次级页版心（设置/关于/统计/隐私；纯逻辑守门）──────────────────

test('表单页补丁：手机竖屏与未测量一律 0（行为与旧版逐字一致）', () => {
  assert.equal(formPadOf(0), 0, '未测量：UI 层回落 100% 宽');
  assert.equal(formPadOf(360), 0);
  assert.equal(formPadOf(419), 0, '本模拟器宽度档');
  assert.equal(formPadOf(FORM_MAX_VP), 0, '正好封顶值：不用补');
  assert.equal(formPadOf(FORM_MAX_VP - 1), 0);
});

test('表单页补丁：宽屏居中（补丁后版心 = FORM_MAX_VP）', () => {
  assert.equal(formPadOf(800), 120, '平板竖屏：两侧各补 120');
  assert.equal(formPadOf(1280), 360, '平板横屏');
  const w = 1280;
  assert.equal(w - formPadOf(w) * 2, FORM_MAX_VP, '版心必须正好等于封顶值');
});

test('表单页补丁：奇数额取整不丢像素（左右对称，版心误差 ≤1vp）', () => {
  // 奇数宽：两边取整后版心与封顶值最多差 1vp，绝不允许偏 contents
  const w = 1001;
  const content = w - formPadOf(w) * 2;
  assert.ok(Math.abs(content - FORM_MAX_VP) <= 1, `版心偏差过大：${content}`);
});
