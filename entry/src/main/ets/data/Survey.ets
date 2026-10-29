/**
 * 字数普查（survey）节奏与取消的**纯逻辑层**
 *
 * 为什么要单独抽一层：普查是 O(整本) 的重活，跑在主线程上。
 * 它的两个属性直接决定「用户点开一本书时卡不卡」：
 *   ① **分帧粒度**：每隔几章让出一帧。粒度越粗，一次冻结越久。
 *   ② **可取消**：离开阅读页必须能停，否则下一轮开书还在抢 UI 线程。
 * 这两条是纯规则，可以单测；塞进 Reader.ets 就只能靠肉眼看。
 *
 * 设计口径（2026-10-29，AGC「应用内点击操作完成快」整改）：
 *  - **每章让一帧**（原为每 8 章）。EPUB 每章一次 zip 解压 + XHTML 解析，
 *    8 章连读会把主线程焊死几百毫秒，AGC 测的「手指离手 → 转场结束」整段被推后。
 *  - **可取消**：aboutToDisappear 置位取消标志，普查循环每章查一次、见位即退。
 */

/** 普查的分帧粒度：每隔多少章让出一帧 */
export const SURVEY_YIELD_EVERY: number = 1;

/** 普查的取消标志（可重置、可查询） */
export class SurveyCancel {
  private cancelled: boolean = false;

  /** 置位取消（离开阅读页时调用） */
  cancel(): void {
    this.cancelled = true;
  }

  /** 清零（新一轮普查开始前调用） */
  reset(): void {
    this.cancelled = false;
  }

  /** 是否已被取消 */
  isCancelled(): boolean {
    return this.cancelled;
  }
}

/**
 * 这一章处理完之后，**该不该让出一帧**？
 *
 * @param chapterIndex 本章下标（0 起）
 * @returns true = 让出一帧（把主线程还给渲染管线）
 */
export function surveyShouldYield(chapterIndex: number): boolean {
  if (chapterIndex < 0) {
    return false;
  }
  return (chapterIndex % SURVEY_YIELD_EVERY) === (SURVEY_YIELD_EVERY - 1);
}

/**
 * 普查循环该不该继续跑下一章。
 *
 * @param cancelled 是否已被取消
 * @returns true = 继续；false = 立刻退出
 */
export function surveyShouldContinue(cancelled: boolean): boolean {
  return !cancelled;
}
