/**
 * 自动滚动（滚屏）纯逻辑层。
 *
 * 为什么单独抽一层：翻页节奏、跨章推进、到底判定都是**可判定的规则**，
 * 塞进 Reader.ets 就只能靠肉眼看对错。抽出来即可单测（家族纪律：逻辑先行）。
 *
 * 设计口径（2026-10-28，党哥拍板做「静读天下招牌的自动滚动」）：
 *  - 速度以「每页停留秒数」计，不用「每秒行数」。
 *    本应用是**分页**渲染（每页正好一屏），按行滚动没有对应物；
 *    而「几秒翻一页」用户能直接换算成「一章大概读多久」，通勤场景够用。
 *  - 手动翻页 / 横滑 = **立刻暂停**（不停止）：用户随时能接管，
 *    但保留当前速度档，重新点「继续」即从当前页接着滚。
 *  - 跨章由阅读页已有的 turnPage 负责（它本来就会带过章尾），
 *    这里只负责回答「这一拍该翻还是该停」。
 */

/** 速度档（秒/页）：从慢到快，点一下循环切到下一档 */
export const SCROLL_SPEEDS: number[] = [8, 6, 4, 3, 2];

/** 默认档（4 秒/页 ≈ 每分钟 15 页，中等偏慢，通勤不赶） */
export const SCROLL_SPEED_DEFAULT: number = 4;

/** 自动滚动状态 */
export enum ScrollState {
  /** 未启用（浮条不出现） */
  OFF = 0,
  /** 正在滚 */
  RUNNING = 1,
  /** 已暂停（速度档保留，浮条仍在） */
  PAUSED = 2
}

/** 一拍之后该干什么 */
export enum ScrollAction {
  /** 推进一页（页内推进或跨章） */
  TURN = 0,
  /** 全书到底，收工 */
  STOP = 1
}

/** 到全书末尾时的提示文案 */
export const SCROLL_END_HINT: string = '已到全书末尾';

/** 速度档文案（浮条上显示） */
export function scrollSpeedText(sec: number): string {
  return `${sec}秒/页`;
}

/** 该速度在档位表里的下标；不在表里（脏值）返回 -1 */
export function scrollSpeedIndex(sec: number): number {
  for (let i = 0; i < SCROLL_SPEEDS.length; i++) {
    if (SCROLL_SPEEDS[i] === sec) {
      return i;
    }
  }
  return -1;
}

/** 下一档（循环）。脏值当作「最慢档的下一点」处理，不会崩 */
export function nextScrollSpeed(cur: number): number {
  const i: number = scrollSpeedIndex(cur);
  if (i < 0) {
    return SCROLL_SPEEDS[SCROLL_SPEEDS.length - 1];
  }
  return SCROLL_SPEEDS[(i + 1) % SCROLL_SPEEDS.length];
}

/** 归一化到合法档位（脏值 / 越界 → 默认档） */
export function normalizeScrollSpeed(sec: number): number {
  return scrollSpeedIndex(sec) >= 0 ? sec : SCROLL_SPEED_DEFAULT;
}

/** 状态切换 */
export enum ScrollToggle {
  /** 开始跑（从 OFF） */
  START = 0,
  /** 从暂停继续 */
  RESUME = 1,
  /** 彻底停 */
  STOP = 2
}

/**
 * 菜单里的「滚屏」按钮：一个按钮覆盖三种状态，
 * 按下会发生什么必须能被判定（不然 UI 层只能靠 if 猜，容易按下和预期相反）。
 *  - OFF → START（开跑）
 *  - PAUSED → RESUME（继续）  ← 关键：不是 STOP
 *  - RUNNING → STOP（停）
 */
export function scrollToggleOf(state: ScrollState): ScrollToggle {
  if (state === ScrollState.PAUSED) {
    return ScrollToggle.RESUME;
  }
  if (state === ScrollState.RUNNING) {
    return ScrollToggle.STOP;
  }
  return ScrollToggle.START;
}

/**
 * 浮层（菜单 / 目录 / 设置 / 摘录卡）遮着正文时，这一拍**不翻页**。
 *
 * 为什么不在「开浮层」时去暂停滚动、关浮层时再恢复：
 * 那套做法要在每一处 showMenu/showToc/showSettings 的赋值点同步状态，
 * 漏一处就是「菜单关不掉还接着在背后滚」的幽灵 bug（2026-10-28 实测踩过）。
 * 改成**到点才判断**：浮层开着就不翻页，浮层一关，下一拍自然继续。
 */
export function scrollTickAllowed(menuOpen: boolean, tocOpen: boolean,
  settingsOpen: boolean, highlightOpen: boolean): boolean {
  return !(menuOpen || tocOpen || settingsOpen || highlightOpen);
}

/** 运行 ↔ 暂停 切换。OFF 切过去 = 直接开跑 */
export function toggleScrollState(cur: ScrollState): ScrollState {
  if (cur === ScrollState.RUNNING) {
    return ScrollState.PAUSED;
  }
  return ScrollState.RUNNING;
}

/**
 * 一拍之后该干什么。
 * - 页内还有剩 → 翻页
 * - 本页是本章最后一页、但还有下一章 → 跨章翻（交给阅读页的 turnPage）
 * - 全书最后一页 → 停
 */
export function scrollAction(pageIndex: number, pageCount: number,
  chapterIndex: number, chapterCount: number): ScrollAction {
  if (pageCount <= 0 || chapterCount <= 0) {
    return ScrollAction.STOP;
  }
  if (pageIndex < pageCount - 1) {
    return ScrollAction.TURN;
  }
  if (chapterIndex < chapterCount - 1) {
    return ScrollAction.TURN;
  }
  return ScrollAction.STOP;
}

/**
 * 剩余页数（粗估）：各章页数不同，用**当前章的页数**当平均值。
 * 返回 -1 = 算不出来（还没有页）。
 */
export function remainingPages(pageIndex: number, pageCount: number,
  chapterIndex: number, chapterCount: number): number {
  if (pageCount <= 0 || chapterCount <= 0) {
    return -1;
  }
  const inChapter: number = Math.max(0, pageCount - 1 - pageIndex);
  const chaptersLeft: number = Math.max(0, chapterCount - 1 - chapterIndex);
  return inChapter + chaptersLeft * pageCount;
}

/** 剩余时间文案：'约 12 分钟' / '不足 1 分钟' / ''（算不出时） */
export function remainingText(remaining: number, secPerPage: number): string {
  if (remaining < 0 || secPerPage <= 0) {
    return '';
  }
  const minutes: number = Math.ceil(remaining * secPerPage / 60);
  // 向上取整后为 0 = 已经到底（没有剩余页）。
  // ⚠️ **不要写成 minutes <= 1**：剩 1 页（几秒）向上取整也是 1 分钟，
  //    那时该说「约 1 分钟」而不是「不足 1 分钟」—— 说反了用户会以为马上读完。
  if (minutes <= 0) {
    return '不足 1 分钟';
  }
  return `约 ${minutes} 分钟`;
}
