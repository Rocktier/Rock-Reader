/**
 * 媒体会话的**纯逻辑**（不引 @kit ⇒ 可 CI 单测）。
 *
 * 为什么单独抽：AvSession.ets 里的 SDK 类型（@kit.AVSessionKit）在
 * CI 的 OpenHarmony SDK 下根本不存在，混在一起就没法测。
 * 这层只回答「系统媒体控制按了 X，应用内该怎么办」—— 那才是有判断价值的部分。
 *
 * 家族纪律（ASR 那次踩出来的）：**按名反射/SDK 耦合的活儿必须留一层纯逻辑**，
 * 否则只能靠肉眼看对错。
 */

/** 朗读在应用内的状态（应用视角，不是系统视角） */
export enum SpeakPhase {
  /** 未在朗读 */
  IDLE = 0,
  /** 正在发声 */
  PLAYING = 1,
  /** 暂停中（引擎已暂停，位置保留） */
  PAUSED = 2
}

/** 系统媒体控制发来的指令 */
export enum MediaCommand {
  PLAY = 0,
  PAUSE = 1,
  STOP = 2
}

/** 应用内应有的反应 */
export enum SpeakAction {
  /** 什么都不做（状态已经对了） */
  NONE = 0,
  /** 起播（当前没有朗读会话） */
  START = 1,
  /** 从暂停点续播 */
  RESUME = 2,
  /** 暂停 */
  PAUSE = 3,
  /** 停止 */
  STOP = 4
}

/** 朗读会话的当前状态快照 */
export interface SpeakView {
  /** 朗读会话是否已激活 */
  active: boolean;
  /** 是否暂停中 */
  paused: boolean;
  /** 是否正在准备（首段还没开播） */
  preparing: boolean;
}

/**
 * 系统媒体控制 → 应用内反应。
 *
 * 边界都写清楚了，免得以后改出「按播放结果从头开始读」这种事故：
 *  - 没在朗读时按播放 = 起播；
 *  - 暂停中按播放 = **从暂停点续**（不是从头）；
 *  - 正在播时按播放 = 什么都不做（不能重复起播）；
 *  - 没在朗读时按暂停 / 按停止 = 什么都不做。
 */
export function respondToCommand(view: SpeakView, cmd: MediaCommand): SpeakAction {
  if (cmd === MediaCommand.STOP) {
    return view.active ? SpeakAction.STOP : SpeakAction.NONE;
  }
  if (cmd === MediaCommand.PLAY) {
    if (!view.active) {
      return SpeakAction.START;
    }
    if (view.paused) {
      return SpeakAction.RESUME;
    }
    return SpeakAction.NONE;
  }
  if (!view.active || view.paused) {
    return SpeakAction.NONE;
  }
  return SpeakAction.PAUSE;
}

/** 归一化倍速：只认 0.5~2.0 之间的有限值，其余回落到 1.0 */
export function normalizeSpeed(speed: number): number {
  if (!isFinite(speed) || speed < 0.5 || speed > 2.0) {
    return 1.0;
  }
  return speed;
}

/**
 * 倍速归到「最近的一档」—— 系统媒体中心给的是任意浮点，
 * 引擎只认我们登记过的那几档（0.5/0.75/1/1.25/1.5/1.75/2）。
 */
export function snapSpeed(speed: number, supported: number[]): number {
  const v: number = normalizeSpeed(speed);
  if (supported.length === 0) {
    return v;
  }
  let best: number = supported[0];
  let bestGap: number = Math.abs(supported[0] - v);
  for (let i = 1; i < supported.length; i++) {
    const gap: number = Math.abs(supported[i] - v);
    if (gap < bestGap) {
      best = supported[i];
      bestGap = gap;
    }
  }
  return best;
}
