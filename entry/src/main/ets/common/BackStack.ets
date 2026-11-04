/**
 * 系统返回键该撤掉哪一层 —— **纯逻辑，零 ArkUI 依赖**（可被 Node 单测直接跑）。
 *
 * 为什么单独抽出来：`Reader.ets` 之前**完全没有 `onBackPress`**，这是个真实缺陷 ——
 * 目录/设置抽屉开着时按返回，直接退出阅读页回书架，抽屉状态还挂在内存里。
 * 用户的心智是「返回 = 后退一步」，一步退出整本书违背它。
 * 证据就在 `Reader.ets` 里：`SETTINGS_STRIP_VP` 那段注释 2026-10-23 写着
 * 「面板铺满全屏且点上面关不掉，**只能靠系统返回**」—— 而系统返回其实是退出页面。
 *
 * 抽成纯函数的目的不是洁癖：**顺序是这个功能唯一的易错点**。
 * 以后再加浮层（朗读面板、睡眠定时、搜索浮层…）时，如果忘了往这里加一层，
 * `backstack.test.ts` 会立刻红 —— 比在 4000 行页面里肉眼找 `if` 可靠得多。
 */

/** 返回键能撤掉的层（枚举值本身**不代表优先级**，优先级只在 `topmostLayer` 里定义） */
export enum BackLayer {
  /** 摘录面板 */
  Highlight = 0,
  /** 书签备注的行内编辑态 */
  EditBookmark = 1,
  /** 设置抽屉 */
  Settings = 2,
  /** 目录抽屉（目录 / 书签摘录 / 搜索三个页签共用一个抽屉） */
  Toc = 3,
  /** 中央菜单（点正文中间唤出） */
  Menu = 4,
  /** 没有可撤的层 —— 交回系统，走默认行为（退出阅读页） */
  Exit = 5
}

/** 当前有哪些层在场 */
export interface BackState {
  hasHighlight: boolean;
  editingBookmark: boolean;
  hasSettings: boolean;
  hasToc: boolean;
  hasMenu: boolean;
}

/**
 * 按「用户眼里最靠上」取第一层，不是按渲染顺序、也不是按枚举值大小。
 *
 * 排序理由：
 *   ① 摘录面板 —— 里面有正在写的注，撤错最肉疼
 *   ② 书签备注行内编辑 —— 同理，且只退出编辑态、**保留抽屉**（一次退一层）
 *   ③④⑤ 设置 / 目录 / 菜单 —— 三者本就互斥（`openToc` / `openSettings` 互相置 false），
 *         谁在前都碰不到"同时开着"的情况
 *
 * ⚠️ 抽屉与菜单虽然互斥，这里仍逐层判断而不是"有一个就关全部的"：
 *    将来若放开互斥（比如菜单上再叠一层生词本），逐层判断不需要改。
 */
export function topmostLayer(s: BackState): BackLayer {
  if (s.hasHighlight) {
    return BackLayer.Highlight;
  }
  if (s.editingBookmark) {
    return BackLayer.EditBookmark;
  }
  if (s.hasSettings) {
    return BackLayer.Settings;
  }
  if (s.hasToc) {
    return BackLayer.Toc;
  }
  if (s.hasMenu) {
    return BackLayer.Menu;
  }
  return BackLayer.Exit;
}
