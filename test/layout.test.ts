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
  clampLevel,
  clampWeightLevel,
  fontSizeFpOf,
  fontWeightOf,
  layoutKey,
  lineHeightRatioOf,
  marginVpOf
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
