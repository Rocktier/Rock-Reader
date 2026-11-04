import { test } from 'node:test';
import assert from 'node:assert/strict';

import { BackLayer, BackState, topmostLayer } from '../entry/src/main/ets/common/BackStack';

// ── 返回键的撤层顺序 ────────────────────────────────────────────────
//
// 背景（2026-11-04）：`Reader.ets` 此前**完全没有 onBackPress** ——
// 目录/设置抽屉开着时按系统返回，会直接退出阅读页回书架。
// 缺陷在源码里留了证据：`SETTINGS_STRIP_VP` 那段 2026-10-23 的注释写着
// 「面板铺满全屏且点上面关不掉，只能靠系统返回」，而系统返回其实是退出页面。
//
// 这组用例锁死的是**顺序**，不是"能不能关"：顺序是本功能唯一的易错点，
// 以后加浮层（朗读面板、睡眠定时、搜索浮层）时若漏了，这里会红。

/** 一个都没开时的基线状态 */
const EMPTY: BackState = {
  hasHighlight: false,
  editingBookmark: false,
  hasSettings: false,
  hasToc: false,
  hasMenu: false
};

/** 只把指定的几层打开 */
function withLayers(...layers: BackLayer[]): BackState {
  return {
    hasHighlight: layers.indexOf(BackLayer.Highlight) >= 0,
    editingBookmark: layers.indexOf(BackLayer.EditBookmark) >= 0,
    hasSettings: layers.indexOf(BackLayer.Settings) >= 0,
    hasToc: layers.indexOf(BackLayer.Toc) >= 0,
    hasMenu: layers.indexOf(BackLayer.Menu) >= 0
  };
}

test('topmostLayer: 什么都没有 ⇒ 交回系统（返回 = 退出阅读页）', () => {
  assert.equal(topmostLayer(EMPTY), BackLayer.Exit);
});

test('topmostLayer: 只有中央菜单 ⇒ 关菜单，不退出', () => {
  assert.equal(topmostLayer(withLayers(BackLayer.Menu)), BackLayer.Menu);
});

test('topmostLayer: 只有目录抽屉 ⇒ 关抽屉', () => {
  assert.equal(topmostLayer(withLayers(BackLayer.Toc)), BackLayer.Toc);
});

test('topmostLayer: 只有设置抽屉 ⇒ 关抽屉', () => {
  assert.equal(topmostLayer(withLayers(BackLayer.Settings)), BackLayer.Settings);
});

test('topmostLayer: 摘录面板优先于所有抽屉 —— 里面可能有正在写的注', () => {
  // 划词是在菜单/抽屉开着时发起的，所以面板与其它层**确实会同时在场**
  const s = withLayers(BackLayer.Highlight, BackLayer.Toc, BackLayer.Menu);
  assert.equal(topmostLayer(s), BackLayer.Highlight);
});

test('topmostLayer: 摘录面板 + 设置抽屉 ⇒ 先关面板', () => {
  assert.equal(topmostLayer(withLayers(BackLayer.Highlight, BackLayer.Settings)), BackLayer.Highlight);
});

test('topmostLayer: 书签备注编辑优先于所在抽屉 —— 先退编辑态，抽屉留着', () => {
  // 备注是在「书签摘录」页签里行内编辑的，两者必然同时在场。
  // 一次退一层：先退出编辑态，再按一次才收抽屉。
  const s = withLayers(BackLayer.EditBookmark, BackLayer.Toc);
  assert.equal(topmostLayer(s), BackLayer.EditBookmark);
});

test('topmostLayer: 摘录面板优先于书签备注编辑', () => {
  const s = withLayers(BackLayer.Highlight, BackLayer.EditBookmark, BackLayer.Toc);
  assert.equal(topmostLayer(s), BackLayer.Highlight);
});

test('topmostLayer: 每按一次只退一层，连按能退到 Exit', () => {
  // 模拟"连按返回"：每次撤掉顶上一层后重算，直到 Exit
  let s = withLayers(BackLayer.Highlight, BackLayer.EditBookmark, BackLayer.Settings);
  const seen: BackLayer[] = [];
  for (let i = 0; i < 6; i++) {
    const layer = topmostLayer(s);
    seen.push(layer);
    if (layer === BackLayer.Exit) {
      break;
    }
    const next = { ...s };
    if (layer === BackLayer.Highlight) { next.hasHighlight = false; }
    if (layer === BackLayer.EditBookmark) { next.editingBookmark = false; }
    if (layer === BackLayer.Settings) { next.hasSettings = false; }
    if (layer === BackLayer.Toc) { next.hasToc = false; }
    if (layer === BackLayer.Menu) { next.hasMenu = false; }
    s = next;
  }
  assert.deepEqual(seen, [
    BackLayer.Highlight,
    BackLayer.EditBookmark,
    BackLayer.Settings,
    BackLayer.Exit
  ]);
});

test('topmostLayer: 三层互斥的抽屉不会互相顶掉（设置 + 目录同时在场时也逐层退）', () => {
  // openToc / openSettings 本身互斥，但万一将来放开，这里的行为必须是
  // "一次退一层"而不是"一次全关"
  const s = withLayers(BackLayer.Settings, BackLayer.Toc);
  assert.equal(topmostLayer(s), BackLayer.Settings);
  const after: BackState = { ...s, hasSettings: false };
  assert.equal(topmostLayer(after), BackLayer.Toc);
});
