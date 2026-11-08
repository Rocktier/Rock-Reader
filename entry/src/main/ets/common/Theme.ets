/**
 * 主题与色板（**鸿蒙原生 HDS**）
 * 设计依据：docs/v1-design.md §8（2026-10-10 起基调改为鸿蒙原生，见 task_plan Phase 21）
 *
 * 为什么色板写在 TS 里、而不是 color.json：
 *   主题由用户在应用内选择（四套纸色 / 自动昼夜），必须能在运行时切换；
 *   资源限定符（resources/dark/）只能跟随系统，做不到"用户自己挑"。
 *   因此 window 背景等系统级颜色仍用资源（见 color.json），页面内容一律读这里的 Palette。
 *
 * ⚠️ 2026-11-08 P0-1 改：**不再是"与系统深浅色解耦"**。新增 THEME_SYSTEM 作为默认档，
 *   app 层 colorMode 回落 NOT_SET，系统深浅由 EntryAbility 写进 AppStorage('systemDark')，
 *   页面经 `paletteFor()` / `resolveTheme()` 解出生效主题（详见 common/Appearance.ets）。
 *   用户显式选了纸色 / 深色的，仍不受系统深浅影响。
 *
 * ⚠️ 2026-10-10 基调变更（党哥拍板）：抛弃第一版 Nothing OS 表述，一切往鸿蒙原生靠。
 *   本文件按华为官方《色彩-视觉风格》对齐：
 *     - 深色背景 #000000（官方「背景色(首页、设置页)」深色值）／深色卡片 #303030
 *     - 文本走官方 α 分级：主文本 86%、次级 60%
 *     - 强调色 = 官方系统高亮色：深色 #317AF7、浅色 #0A59F7
 *   **唯一的有意偏离**：官方三级文本是 40%，但 40% 白在纯黑底只有 3.66:1（低于 WCAG AA 4.5:1），
 *   而 text3 承担页码/章节号这类**功能性**信息（theme.test.ts 有断言兜底），
 *   故深色取 50%（5.28:1）、浅色取 56%（≈4.94:1）—— 层级感保留，AA 不破。
 */

/**
 * 自动（辰时昼 / 夜间夜）：按固定作息在「晴昼」与「子夜」之间自动切换。
 *
 * 对标 Apple Books / Kindle 都有的「自动日夜」——我们原来四套主题全手动，
 * 读者睡前切一次、早起又忘切回去。2026-10-25 党哥拍板做批次 A 时定：
 * **不做经纬度日出日落计算**（YAGNI，国内读者固定城市，粗档足够），
 * 只提供固定边界 + 后续可按需再加「自定义起止时间」。
 */
export const THEME_AUTO: string = 'auto';

/**
 * 跟随系统深浅色（2026-11-08 视觉重设计 P0-1，**新默认**）。
 *
 * 原来主题默认 THEME_DARK，把系统深浅色解耦并钉死 —— 系统白天、应用全黑，
 * 党哥 11-08 实测抱怨「点开阅读器整页黑」。现在这一档只记"用户没显式选过"，
 * 生效主题由 resolveTheme() 结合系统深浅解出 LIGHT / DARK。
 *
 * 四套纸色（晴昼 / 子夜 / 旧纸 / 新苔）与 auto 全部**保留**：
 * 它们是用户显式选择的内容层偏好，系统切深浅不该覆盖；auto 降为可选定时。
 */
export const THEME_SYSTEM: string = 'system';

/** 'system' | 'auto' | 'dark' | 'light' | 'sepia' | 'green'（不用字面量联合类型，保证 ArkTS 各版本都能编译） */
export type ThemeName = string;

export const THEME_DARK: string = 'dark';
export const THEME_LIGHT: string = 'light';
/**
 * 纸（sepia）：米黄底 + **深褐**字。
 * 来源：Kindle / Apple Books 的 sepia 主题就是这一路 —— 关键不是"换个黄底"，
 * 而是**正文不用纯黑**（纯白配纯黑是 21:1，太刺眼），用深褐把对比降到 ~11:1。
 */
export const THEME_SEPIA: string = 'sepia';
/**
 * 绿（豆沙绿 `#C7EDCC`）：中文阅读器里最常见的护眼绿
 * （源自流传极广的"电脑护眼色" RGB 199/237/204）。
 */
export const THEME_GREEN: string = 'green';

export interface Palette {
  /** 页面背景 */
  bg: string;
  /** 正文 / 主强调（官方：深色 #FFFFFF 86%） */
  text: string;
  /** 次级文字（官方：60%） */
  text2: string;
  /**
   * 三级文字（数码、页码、章节号）。
   * 官方给的是 40%，但**在本应用里不作数**：40% 白在纯黑底只有 3.66:1，低于 WCAG AA 4.5:1，
   * 而它承担的是页码/章节号这类**功能性**信息（test/theme.test.ts 断言 ≥4.5:1）。
   * 故取「能过 AA 的最低档」：深色 50%（5.28:1）、浅色 56%（≈4.94:1）。
   * 纯装饰性的灰仍可用 text2 之外的自定义值，不再压这个 token。
   */
  text3: string;
  /** 描边 */
  line: string;
  /** 极淡分隔线 */
  lineSoft: string;
  /**
   * **强调色**（原名 `red`，2026-10-10 随原生化改名并换色）。
   * 取官方系统高亮色：**深色 #317AF7 / 浅色 #0A59F7**（官方《色彩-视觉风格》）。
   * 用于当前章序号、进度、主行动等"要看重"的位置。
   */
  accent: string;
  /** 卡片底（官方深色卡片 #303030；浅色用官方浅色灰 #F1F3F5） */
  card: string;
  /** 书封灰底 */
  cover: string;
  /**
   * 浮层底（阅读页上下细栏、目录面板）。
   * 比 bg 略透（8%）：底下正文已被 scrim 压暗，透出来的是"纵深"而不是干扰文字。
   * 不上 blur —— backdrop 模糊吃 GPU，撞家族铁律 1（极致快）。
   */
  overlay: string;
  /**
   * **重点色块底**（书架「继续阅读」卡这类首屏唯一焦点）。
   *
   * ⚠️ 不能图省事写成 `text` 反色：深色主题的 `text` 是 86% 白，反白后就变成
   *   一整块白卡压在纯黑页面上 —— 夜间刺眼，且与「阅读界面不该有亮块」冲突。
   *   所以深色主题取 `card`（#303030，比黑底抬一档），浅色/护眼才真的"墨底"。
   *   四套主题各给一套值，页面里零 `if (isDark)`。对比度由 theme.test.ts 守。
   */
  heroBg: string;
  /** 重点色块上的文字/图形色（与 heroBg 成对使用，≥4.5:1） */
  heroText: string;
  /**
   * **强调色底上的文字**（实心主按钮：确定 / 移除 / 同意）。
   *
   * 为什么不继续用 `palette.bg`（2026-11-06 审计发现）：那是**页面底色**，
   * 拿它当字色等于"字色跟着主题漂移" —— 晴昼/子夜碰巧接近纯白纯黑还过得去，
   * 但护眼主题的底是**豆沙绿/米黄**，绿字压在蓝底上只有 **4.34:1**（低于 AA）。
   * 语义一旦写错，换主题就出事，且单看图看不出来。
   *
   * 取值依据：accent 在深色是亮蓝 `#317AF7` ⇒ 黑字 5.26:1；
   * 浅色系三套 accent 都是深蓝 `#0A59F7` ⇒ 白字 5.47:1。四套均 ≥5:1，由单测守。
   */
  onAccent: string;
  /**
   * 渐变光层起点（165° 同色相明度渐变的亮端）。**只铺空白底层，不承载文字**。
   * 2026-11-08 P0-3 新增，与 all2md 0cb3b61 同一套结构语言。
   */
  haloTop: string;
  /** 卡片 / 浮层 1px 描边色。卡与底色差只有 1.06–1.19:1 ⇒ 层次靠它，不靠色差。 */
  glassEdge: string;
  /**
   * **卡上蓝字**。深色 `accent #317AF7` 压在 `#303030` 卡上只有 3.30:1（不达标），
   * 故深色另给 `#6BA0FF`（5.09:1）；`accent` 原值保留给进度条 / 图标（3:1 够）。
   */
  accentOnCard: string;
}

const DARK: Palette = {
  bg: '#000000',
  text: '#DBFFFFFF',
  text2: '#99FFFFFF',
  // 2026-11-08：50% → 56%。50% 白压在 #303030 卡上是 5.02:1，只比 HDS 深色
  // 5:1 多 0.02；提到 56% 后 5.30:1，留余量。改的是 token，不是调用点。
  text3: '#8FFFFFFF',
  line: '#24FFFFFF',
  lineSoft: '#12FFFFFF',
  accent: '#317AF7',
  card: '#303030',
  cover: '#1A1A1A',
  overlay: '#EB000000',
  // 深色不反白：抬一档灰做"墨块"，文字仍是 86% 白（9.4:1）
  heroBg: '#303030',
  heroText: '#DBFFFFFF',
  // 亮蓝底上用黑字：5.26:1（白字只有 4.08:1，不达标）
  onAccent: '#000000',
  haloTop: '#16233A',
  glassEdge: '#4A5A70',
  accentOnCard: '#6BA0FF'
};

const LIGHT: Palette = {
  bg: '#FFFFFF',
  text: '#E6000000',
  text2: '#99000000',
  // 浅底上不能照搬官方 40%（只有 3.98:1）；56% 是能过 AA 的最低档（≈4.94:1）
  text3: '#8F000000',
  line: '#24000000',
  lineSoft: '#12000000',
  // 官方浅色系统高亮 #0A59F7（纯白上 5.56:1）
  accent: '#0A59F7',
  card: '#F1F3F5',
  cover: '#EBEBEB',
  overlay: '#EBFFFFFF',
  // 晴昼：真正的墨块（90% 黑压在白纸上），纸白字 ≈18:1
  heroBg: '#E6000000',
  heroText: '#FFFFFF',
  // 深蓝底上白字 5.47:1
  onAccent: '#FFFFFF',
  haloTop: '#DCE8FA',
  // ⚠️ 不用 all2md 的纯白描边：本仓浅色页面底就是 #FFFFFF、卡是 #F1F3F5，
  //    白描边在白底上等于没有。用能看见的浅灰（卡差 1.11:1 ⇒ 边界全靠描边）。
  glassEdge: '#D6DEE6',
  accentOnCard: '#0A59F7'
};

/**
 * 纸（sepia）。所有对比度都按 WCAG 相对亮度算过（见 test/theme.test.ts 有断言兜底）：
 *   正文 10.9:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1（小字宁可更深）
 * 半透明色是**深褐**的百分比（不是黑）—— 在米黄底上混出来的灰才不发脏。
 * 强调色用官方浅色高亮 #0A59F7（纸底 ≈4.88:1，过 AA 的 4:1 底线）。
 */
const SEPIA: Palette = {
  bg: '#F4EFE4',
  text: '#3C3226',
  text2: '#B33C3226',
  text3: '#BF3C3226',
  line: '#243C3226',
  lineSoft: '#123C3226',
  accent: '#0A59F7',
  card: '#083C3226',
  cover: '#E4DCCB',
  overlay: '#EBF4EFE4',
  // 旧纸：深褐墨块 + 纸底字（10.9:1）
  heroBg: '#3C3226',
  heroText: '#F4EFE4',
  // 白字 5.47:1（纸色字只有 4.84:1，虽过线但没余量）
  onAccent: '#FFFFFF',
  // 暖色系独立，不跟阅读蓝统一：渐变起点是比纸底略深的米色
  haloTop: '#E8DDC4',
  glassEdge: '#D8CCB4',
  accentOnCard: '#0A59F7'
};

/** 绿（豆沙绿）。正文 10.5:1 ／ text2 ≈4.6:1 ／ text3 ≈5.3:1；强调色 #0A59F7（绿底 ≈4.34:1） */
const GREEN: Palette = {
  bg: '#C7EDCC',
  text: '#22331F',
  text2: '#B322331F',
  text3: '#BF22331F',
  line: '#2422331F',
  lineSoft: '#1222331F',
  accent: '#0A59F7',
  card: '#0822331F',
  cover: '#AFD9B4',
  overlay: '#EBC7EDCC',
  // 新苔：深绿墨块 + 豆沙绿字（10.5:1）
  heroBg: '#22331F',
  heroText: '#C7EDCC',
  // ⚠️ 这里原来用 palette.bg（豆沙绿）当字色，蓝底上只有 4.34:1 —— 改白字 5.47:1
  onAccent: '#FFFFFF',
  haloTop: '#B0E0B8',
  glassEdge: '#A8CFAE',
  accentOnCard: '#0A59F7'
};

export function paletteOf(theme: ThemeName): Palette {
  if (theme === THEME_LIGHT) {
    return LIGHT;
  }
  if (theme === THEME_SEPIA) {
    return SEPIA;
  }
  if (theme === THEME_GREEN) {
    return GREEN;
  }
  return DARK;
}

/**
 * 未知值一律回落**跟随系统**（2026-11-08 改）。
 *
 * 老数据兜底：已经显式选过 dark / light / sepia / green / auto 的用户原样保留，
 * 只有"从没选过"和"脏值"才落到跟随系统 —— 不做偏好迁移。
 */
export function normalizeTheme(value: string): ThemeName {
  if (value === THEME_AUTO || value === THEME_LIGHT || value === THEME_SEPIA ||
    value === THEME_GREEN || value === THEME_DARK || value === THEME_SYSTEM) {
    return value;
  }
  return THEME_SYSTEM;
}

/**
 * 页面统一取色板入口（P0-1）：先把「用户意图」解析成**生效主题**，再取色板。
 *
 * ⚠️ 不要直接 `paletteOf(this.theme)` —— system / auto 是意图不是生效主题，
 *    直接取会恒回落 DARK，白天又是全黑。所有页面走这里。
 */
export function paletteFor(theme: ThemeName, hour: number, systemDark: boolean): Palette {
  return paletteOf(resolveTheme(theme, hour, systemDark));
}

/* ---------------- 自动昼夜（A2，2026-10-25）----------------
 * 全部是**纯函数**：小时数进、主题名出。UI 只在翻页/回前台时调一次，
 * 跨昼夜的切换因此完全可单测（本工程横屏断点纪律同款：能纯则纯）。
 */

/** 入夜时刻（小时，18.5 = 18:30） */
export const AUTO_NIGHT_START: number = 18.5;
/** 天亮时刻（小时，6.5 = 6:30） */
export const AUTO_NIGHT_END: number = 6.5;

/** 该小时是否算夜间：18:30 起 ～ 次日 6:30 前 */
export function isNightHour(hour: number): boolean {
  return hour >= AUTO_NIGHT_START || hour < AUTO_NIGHT_END;
}

/** 自动档在该小时应生效的主题（夜间子夜 / 昼间晴昼） */
export function themeForHour(hour: number): ThemeName {
  return isNightHour(hour) ? THEME_DARK : THEME_LIGHT;
}

/**
 * 把用户选择解析成**生效主题**：system 按系统深浅、auto 按小时算，其余原样返回。
 * 色板、系统状态栏、抽屉选中态一律用它的返回值，不要直接用用户选择值。
 *
 * 2026-11-08 P0-1 加第三参 `systemDark`：由 EntryAbility 写进 AppStorage，
 * 页面用 @StorageProp 读，系统切深浅时 @Watch 重算 —— **不调运行时 setColorMode**
 * （那会重建 UIContent、丢页面栈，私记 2026-10-16 实测）。
 */
export function resolveTheme(theme: ThemeName, hour: number, systemDark: boolean = false): ThemeName {
  if (theme === THEME_SYSTEM) {
    return systemDark ? THEME_DARK : THEME_LIGHT;
  }
  return theme === THEME_AUTO ? themeForHour(hour) : theme;
}

/** 是否自动档（抽屉里要给「当前生效」的提示） */
export function isAutoTheme(theme: ThemeName): boolean {
  return theme === THEME_AUTO;
}

/**
 * 是否"浅色系" —— 决定系统状态栏文字颜色与系统 colorMode。
 *
 * 刻意写成 **"非 dark 即浅色"** 而不是逐个列举：以后再加护眼色不用回来改这里，
 * 也不会出现"新主题忘了登记 → 状态栏白字白底"这种事故（SystemBar.ets 头部记的那个 bug）。
 */
export function isLightTheme(theme: ThemeName): boolean {
  return theme !== THEME_DARK;
}

/**
 * 主题的显示名（抽屉芯片用）。
 *
 * **放在这里而不是散在 UI 代码里**：名字和色板是一套，改名字不该去翻页面文件；
 * 也避免"抽屉里叫旧纸、别处写成纸色"这种漂移。
 *
 * 深色 子夜 ／ 浅色 晴昼 ／ 纸 旧纸 ／ 绿 新苔 ／ 自动 自动（党哥 2026-09-20 选；自动 2026-10-25 加）
 */
export function themeLabel(theme: ThemeName): string {
  if (theme === THEME_SYSTEM) {
    return '跟随系统';
  }
  if (theme === THEME_SEPIA) {
    return '旧纸';
  }
  if (theme === THEME_GREEN) {
    return '新苔';
  }
  if (theme === THEME_AUTO) {
    return '自动';
  }
  if (theme === THEME_LIGHT) {
    return '晴昼';
  }
  return '子夜';
}
