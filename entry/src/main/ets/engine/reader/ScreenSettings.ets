/**
 * 屏幕常亮 + 阅读页亮度（纯逻辑，零设备 API → CI 可单测）
 *
 * 起因（2026-11-03 对标顶级产品）：
 *   全仓 `keepScreenOn` / `setWindowBrightness` **零命中** ⇒ 阅读页没有常亮，
 *   也没有独立的亮度控制。通勤场景（地铁/睡前）这两个是刚需：
 *   屏幕自动息屏会把正在读的内容直接黑掉，而系统亮度在阳光下常常太暗。
 *
 * 与顶级产品的对位：Apple Books / Kindle / 静读天下都有「阅读时保持屏幕常亮」
 * 与「阅读页独立亮度」两项。
 *
 * ⚠️ **两个 SDK 约束（本文件存在的全部理由）**：
 *   ① `window.setWindowBrightness(brightness)` 只在**窗口前台且有焦点**时生效；
 *      **传 -1 恢复系统亮度**。⇒ 离开阅读页必须还原，否则退到书架后屏幕还压着暗 —— 大坑。
 *   ② `window.setKeepScreenOn(boolean)` 是**窗口级**的，不是组件属性。
 *      ⇒ 同样必须成对还原（进阅读页开、离阅读页关）。
 *
 * 本文件只负责「算出一个值」与「算出一个开关」，
 * 真正的 API 调用在 `pages/Reader.ets`（引 @kit.WindowKit，无法单测）。
 */

/** 亮度档位：-1 = 跟随系统；其余为窗口亮度 0.0~1.0 */
export const BRIGHTNESS_SYSTEM: number = -1;

/**
 * 亮度档位表。
 *
 * ⚠️ 为什么用**档位**而不是滑杆：家族铁律「设置页一律不许出现滑块」
 *    （`common/LayoutStyle.ets:8`）—— 排版已经是档位制，亮度跟着走，保持一致。
 * ⚠️ 每档 = 系统亮度的一个**系数**，而不是绝对亮度：
 *    绝对亮度在不同设备上差异极大（手机 500nit vs 平板 400nit），
 *    系数法能保证"更暗/更亮"是相对的，用户不会因为选了 0.6 而在亮屏手机上瞎眼。
 */
export interface BrightnessLevel {
  /** 该档的显示文案 */
  label: string;
  /**
   * 窗口亮度绝对值（0.0~1.0）；-1 表示跟随系统。
   *
   * ⚠️ 注意：窗口亮度是**绝对**值（覆盖系统亮度），不是系数 ——
   *    `setWindowBrightness` 的语义就是"把窗口亮度设成这个值"。
   *    所以这里给的是一组**保守的绝对值**：用户主动调到"最亮"时是 1.0（等同系统满亮），
   *    "跟随系统"时是 -1。
   */
  value: number;
}

/**
 * 亮度档位表（5 档 + 跟随系统）。
 *
 * ⚠️ 顺序即 UI 顺序：从跟随系统 → 最暗 → 最亮。
 */
export const BRIGHTNESS_LEVELS: BrightnessLevel[] = [
  { label: '跟随系统', value: BRIGHTNESS_SYSTEM },
  { label: '很暗', value: 0.15 },
  { label: '暗', value: 0.3 },
  { label: '正常', value: 0.5 },
  { label: '亮', value: 0.75 },
  { label: '很亮', value: 1.0 }
];

export const BRIGHTNESS_DEFAULT_INDEX: number = 0;

/**
 * 档位索引 → 窗口亮度值。
 *
 * ⚠️ **越界必须回落**而不是抛错：偏好文件可能被手改 / 旧版本残留 / 迁移丢字段。
 *    家族铁律：读端对脏数据一律 clamp，不让脏值进 UI。
 */
export function brightnessValueOf(index: number): number {
  if (!Number.isFinite(index) || index < 0 || index >= BRIGHTNESS_LEVELS.length) {
    return BRIGHTNESS_LEVELS[BRIGHTNESS_DEFAULT_INDEX].value;
  }
  return BRIGHTNESS_LEVELS[Math.floor(index)].value;
}

/** 档位索引 → 显示文案 */
export function brightnessLabelOf(index: number): string {
  if (!Number.isFinite(index) || index < 0 || index >= BRIGHTNESS_LEVELS.length) {
    return BRIGHTNESS_LEVELS[BRIGHTNESS_DEFAULT_INDEX].label;
  }
  return BRIGHTNESS_LEVELS[Math.floor(index)].label;
}

/**
 * 下一个档位（循环切换）。
 *
 * ⚠️ 循环而不是到头就停：这是"一点就切"的设计（与主题、字号档位同一交互），
 *    用户想往亮里调不必先知道现在在第几档。
 */
export function nextBrightnessIndex(index: number): number {
  if (!Number.isFinite(index) || index < 0 || index >= BRIGHTNESS_LEVELS.length) {
    return BRIGHTNESS_DEFAULT_INDEX;
  }
  return (Math.floor(index) + 1) % BRIGHTNESS_LEVELS.length;
}

/**
 * 离开阅读页时**必须还原**的窗口设置。
 *
 * ⚠️ 为什么要单独一个函数（而不是在页面里直接写 -1）：
 *    这是**两个必须成对还原的窗口级副作用**（亮度 + 常亮），
 *    散在页面各处容易漏一处（漏亮度 = 退到书架屏幕还是暗的）。
 *    收成一个函数 ⇒ 只有一个还原入口，漏不掉。
 */
export interface WindowRestore {
  /** 传给 setWindowBrightness 的值（-1 = 恢复系统亮度） */
  brightness: number;
  /** 传给 setKeepScreenOn 的值（false = 允许自动息屏） */
  keepScreenOn: boolean;
}

export function restoreWindowSettings(): WindowRestore {
  return { brightness: BRIGHTNESS_SYSTEM, keepScreenOn: false };
}

/**
 * 进阅读页时要施加的窗口设置。
 *
 * @param brightnessIndex 亮度档位索引
 * @param keepOn 用户是否开启「保持常亮」
 */
export function applyWindowSettings(brightnessIndex: number, keepOn: boolean): WindowRestore {
  return {
    brightness: brightnessValueOf(brightnessIndex),
    // ⚠️ 只有用户真的选了亮度档位才常亮；"跟随系统"档位下常亮仍然有效
    //    （这两件事是独立的：我要"屏幕别灭"，但亮度跟着系统 —— 夜里系统会自动调暗）
    keepScreenOn: keepOn
  };
}
