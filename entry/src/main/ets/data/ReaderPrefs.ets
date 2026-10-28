/**
 * 阅读偏好（Preferences）
 * 设计依据：docs/v1-design.md §4 —— 排版档位、主题存 Preferences（书在 relationalStore）
 *
 * 只存**档位序号**与主题名，不存任何数值 —— 数值唯一真源在 common/LayoutStyle.ets。
 * 用同步 API（getPreferencesSync / getSync / putSync）：阅读页初始化路径上不能有 await。
 */
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { clampLevel, clampWeightLevel, DEFAULT_LEVELS, LayoutLevels } from '../common/LayoutStyle';
import { normalizeTheme, THEME_DARK, ThemeName } from '../common/Theme';
import { normalizeScrollSpeed, SCROLL_SPEED_DEFAULT } from './AutoScroll';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const STORE_NAME: string = 'rockreader_prefs';
const KEY_FONT: string = 'font_level';
const KEY_LINE: string = 'line_level';
const KEY_MARGIN: string = 'margin_level';
const KEY_THEME: string = 'theme';
/** 字体族；'' = 系统默认（体积为 0：只列系统已装字体，不内置字体文件） */
const KEY_FAMILY: string = 'font_family';
const KEY_WEIGHT: string = 'weight_level';
/** TXT 正文净化（去广告）开关；默认开（国内 TXT 广告太多） */
const KEY_PURIFY: string = 'purify_on';
/** 简繁：'off' | 's2t' | 't2s' */
const KEY_CONVERT: string = 'convert_mode';
/** 朗读语速（TTS）；默认 1.0 常速，产品档位 0.5~2.0 */
const KEY_TTS_SPEED: string = 'tts_speed';
/** 朗读音色（TTS）；存 person 号。官方音色：13=聆小珊女声（内置推荐）、
 *  21=凌飞哲男声（需 downloadVoice 下载）。8=劳拉是**英文**音色，中文书不列。 */
const KEY_TTS_PERSON: string = 'tts_person';

/**
 * 每本书的排版覆盖（A1，2026-10-25 党哥拍板「仅这一本」）。
 * **一本书一个 preference key**（而不是一个 map 串）：单键读写、某本书的脏数据
 * 不会波及其他书、也不需要整表解析。值为 JSON；读端逐字段校验，脏值整体丢弃回落全局。
 */
const KEY_BOOK_PREF_PREFIX: string = 'book_pref_';
/** 每日阅读目标（分钟）；0 = 关闭。党哥默认 20 分钟（A4） */
const KEY_DAILY_GOAL: string = 'daily_goal_min';

/** 自动滚动速度档（秒/页；2026-10-28 加） */
const KEY_SCROLL_SPEED: string = 'scroll_speed';

/** 朗读语速默认值（常速） */
export const TTS_SPEED_DEFAULT: number = 1.0;
/** 朗读语速档位（产品可选；TtsEngine 侧还有 0.2~2.0 的防御性夹取） */
export const TTS_SPEED_MIN: number = 0.5;
export const TTS_SPEED_MAX: number = 2.0;

/** 音色白名单（脏值/历史值一律回默认）：聆小珊内置无需下载；凌飞哲需下载 */
export const TTS_PERSON_DEFAULT: number = 13;
export const TTS_PERSONS: number[] = [13, 21];
/** 内置音色（包在系统里，无需下载）：聆小珊 13 */
export const TTS_PERSON_BUILTIN: number = 13;
/** 已下载音色的 person 列表（preferences 存逗号串，如 "13,21"）。
 *  党口径：下载记录进 prefs —— 重开 App / 换设备恢复备份后不重复引导下载。 */
const KEY_TTS_VOICE_DL: string = 'tts_voice_dl';

export const CONVERT_OFF: string = 'off';

/* ---------------- A1：每本书独立排版（2026-10-25 党哥拍板）----------------
 * 对标 Apple Books / Kindle / 静读天下：排版偏好**记住每本书**。
 * 社科论文想小字密排、小说想大字疏行，全局一套档位永远有一边不舒服。
 * 存储：`book_pref_<bookId>` → JSON（levels/theme/fontFamily 的整体快照）。
 * 读取：有覆盖用覆盖，任何字段缺失/脏 → 回落全局。
 */

/** 某本书的排版覆盖快照 */
export interface BookOverride {
  levels: LayoutLevels;
  theme: ThemeName;
  fontFamily: string;
}

/** 每日阅读目标档位（分钟）；0 = 关。党哥 2026-10-25 定默认 20 */
export const DAILY_GOAL_STEPS: number[] = [0, 10, 20, 30, 60];
export const DAILY_GOAL_DEFAULT: number = 20;

/**
 * 用户已确认阅读的**隐私政策版本**（0 = 从未确认）。
 * 2026-09-26 审核驳回第 1 条：首次启动必须提示用户阅读隐私政策。
 * 存**版本号**而不是布尔值 —— 将来政策有实质变更时把 PRIVACY_VERSION 加一，
 * 老用户会重新看到弹窗（布尔值做不到这点）。
 */
const KEY_PRIVACY_AGREED: string = 'privacy_agreed_version';

export class ReaderPrefs {
  private store: preferences.Preferences | null = null;
  private levels: LayoutLevels = {
    fontSizeLevel: DEFAULT_LEVELS.fontSizeLevel,
    lineHeightLevel: DEFAULT_LEVELS.lineHeightLevel,
    marginLevel: DEFAULT_LEVELS.marginLevel,
    fontWeightLevel: DEFAULT_LEVELS.fontWeightLevel
  };
  private theme: ThemeName = THEME_DARK;
  private fontFamily: string = '';
  private purifyOn: boolean = true;
  private convertMode: string = CONVERT_OFF;
  private ttsSpeed: number = TTS_SPEED_DEFAULT;
  private ttsPerson: number = TTS_PERSON_DEFAULT;
  /** 已下载音色（内置款永远就绪；reload 时从 store 重读） */
  private voiceReady: number[] = [TTS_PERSON_BUILTIN];
  /** 自动滚动速度档（秒/页） */
  private scrollSpeed: number = SCROLL_SPEED_DEFAULT;

  /** 幂等：重复调用直接返回 */
  open(ctx: Context): void {
    if (this.store !== null) {
      return;
    }
    try {
      const store: preferences.Preferences = preferences.getPreferencesSync(ctx, { name: STORE_NAME });
      this.store = store;
      this.levels = this.readLevels(store);
      this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
      this.fontFamily = this.readText(store, KEY_FAMILY, '');
      this.purifyOn = this.readBool(store, KEY_PURIFY, true);
      this.convertMode = this.readText(store, KEY_CONVERT, CONVERT_OFF);
      this.ttsSpeed = this.readTtsSpeed(store);
      this.ttsPerson = this.readTtsPerson(store);
      this.scrollSpeed = normalizeScrollSpeed(this.readInt(store, KEY_SCROLL_SPEED, SCROLL_SPEED_DEFAULT));
    } catch (e) {
      // 读不到就用默认档位（3/3/3 + 深色）—— 绝不因为偏好读取失败而读不了书
      hilog.error(DOMAIN, TAG, 'prefs open failed: %{public}s', JSON.stringify(e));
    }
  }

  private readLevels(store: preferences.Preferences): LayoutLevels {
    return {
      fontSizeLevel: this.readLevel(store, KEY_FONT),
      lineHeightLevel: this.readLevel(store, KEY_LINE),
      marginLevel: this.readLevel(store, KEY_MARGIN),
      fontWeightLevel: this.readWeight(store, KEY_WEIGHT)
    };
  }

  private readWeight(store: preferences.Preferences, key: string): number {
    const raw: preferences.ValueType = store.getSync(key, DEFAULT_LEVELS.fontWeightLevel);
    if (typeof raw === 'number') {
      return clampWeightLevel(raw);
    }
    return DEFAULT_LEVELS.fontWeightLevel;
  }

  private readBool(store: preferences.Preferences, key: string, fallback: boolean): boolean {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'boolean') {
      return raw;
    }
    return fallback;
  }

  /** 通用整数读取（无 clamp —— 用于版本号这类不需要夹取的值） */
  private readInt(store: preferences.Preferences, key: string, fallback: number): number {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'number') {
      return raw;
    }
    return fallback;
  }

  private readLevel(store: preferences.Preferences, key: string): number {
    const raw: preferences.ValueType = store.getSync(key, DEFAULT_LEVELS.fontSizeLevel);
    if (typeof raw === 'number') {
      return clampLevel(raw);
    }
    return 3;
  }

  private readText(store: preferences.Preferences, key: string, fallback: string): string {
    const raw: preferences.ValueType = store.getSync(key, fallback);
    if (typeof raw === 'string') {
      return raw;
    }
    return fallback;
  }

  /** 朗读语速读取（夹取到产品档位范围，防历史脏值/手改 store） */
  private readTtsSpeed(store: preferences.Preferences): number {
    const raw: preferences.ValueType = store.getSync(KEY_TTS_SPEED, TTS_SPEED_DEFAULT);
    if (typeof raw === 'number' && isFinite(raw)) {
      return clampTtsSpeed(raw);
    }
    return TTS_SPEED_DEFAULT;
  }

  /** 音色读取（白名单校验：只认 13/21，其余回默认 13） */
  private readTtsPerson(store: preferences.Preferences): number {
    const raw: preferences.ValueType = store.getSync(KEY_TTS_PERSON, TTS_PERSON_DEFAULT);
    if (typeof raw === 'number' && isFinite(raw)) {
      return clampTtsPerson(raw);
    }
    return TTS_PERSON_DEFAULT;
  }

  /** 已下载音色读取（逗号串 → number[]；脏值丢弃，内置款永远包含） */
  private readVoiceReady(store: preferences.Preferences): number[] {
    const out: number[] = [TTS_PERSON_BUILTIN];
    const raw: preferences.ValueType = store.getSync(KEY_TTS_VOICE_DL, '');
    if (typeof raw === 'string' && raw.length > 0) {
      const parts: string[] = raw.split(',');
      for (let i: number = 0; i < parts.length; i++) {
        const n: number = Number(parts[i].trim());
        if (Number.isFinite(n) && out.indexOf(n) < 0) {
          out.push(n);
        }
      }
    }
    return out;
  }

  /**
   * 重新从 store 读一遍。
   * 必要性：设置页与阅读页各持一个 ReaderPrefs 实例，设置页改了档位后，
   * 阅读页 onPageShow 里必须重读，否则会拿着旧档位排版（切了档位不生效）。
   */
  reload(): void {
    if (this.store === null) {
      return;
    }
    const store: preferences.Preferences = this.store;
    this.levels = this.readLevels(store);
    this.theme = normalizeTheme(this.readText(store, KEY_THEME, THEME_DARK));
    this.fontFamily = this.readText(store, KEY_FAMILY, '');
    this.purifyOn = this.readBool(store, KEY_PURIFY, true);
    this.convertMode = this.readText(store, KEY_CONVERT, CONVERT_OFF);
    this.ttsSpeed = this.readTtsSpeed(store);
    this.ttsPerson = this.readTtsPerson(store);
    this.voiceReady = this.readVoiceReady(store);
  }

  /** 该音色是否已就绪（内置 = 永远 true；其余看下载记录） */
  isVoiceReady(person: number): boolean {
    return this.voiceReady.indexOf(person) >= 0;
  }

  /**
   * 记录音色下载成功（失败不记录 —— 失败态由 UI 当场反馈「可重试」，
   * 不落脏状态；党口径「失败可重试、不重复下载已有资源」由 ok=true 分支保证）。
   */
  markVoiceDownloaded(person: number, ok: boolean): void {
    if (!ok || this.voiceReady.indexOf(person) >= 0) {
      return;
    }
    this.voiceReady.push(person);
    this.put(KEY_TTS_VOICE_DL, this.voiceReady.join(','));
    this.flush();
  }

  getLevels(): LayoutLevels {
    return this.levels;
  }

  getTheme(): ThemeName {
    return this.theme;
  }

  /** 已确认阅读的隐私政策版本（0 = 从未确认 → 首次启动要弹提示） */
  getPrivacyAgreedVersion(): number {
    if (this.store === null) {
      return 0;
    }
    return this.readInt(this.store, KEY_PRIVACY_AGREED, 0);
  }

  /** 记录"已阅读第 v 版隐私政策" */
  setPrivacyAgreedVersion(v: number): void {
    this.put(KEY_PRIVACY_AGREED, v);
    this.flush();
    // 临时诊断：写后立即回读，确认内存缓存里确实写进去了
    const readback: number = this.getPrivacyAgreedVersion();
    hilog.info(DOMAIN, TAG,
      'privacy set: v=%{public}d readback=%{public}d storeNull=%{public}s',
      v, readback, String(this.store === null));
  }

  /** '' = 系统默认字体 */
  getFontFamily(): string {
    return this.fontFamily;
  }

  saveFontFamily(family: string): void {
    this.fontFamily = family;
    this.put(KEY_FAMILY, family);
    this.flush();
  }

  saveLevels(levels: LayoutLevels): void {
    this.levels = levels;
    this.put(KEY_FONT, clampLevel(levels.fontSizeLevel));
    this.put(KEY_LINE, clampLevel(levels.lineHeightLevel));
    this.put(KEY_MARGIN, clampLevel(levels.marginLevel));
    this.put(KEY_WEIGHT, clampWeightLevel(levels.fontWeightLevel));
    this.flush();
  }

  saveTheme(theme: ThemeName): void {
    this.theme = normalizeTheme(theme);
    this.put(KEY_THEME, this.theme);
    this.flush();
  }

  /* ---------------- A1：每本书覆盖 ---------------- */

  private bookPrefKey(bookId: string): string {
    return KEY_BOOK_PREF_PREFIX + bookId;
  }

  /**
   * 读某本书的排版覆盖；没有 / 脏 / 缺字段 → null（调用方回落全局）。
   * 逐字段 clamp：手改过 store、老版本字段不全，都不该把排版搞崩。
   */
  getBookOverride(bookId: string): BookOverride | null {
    if (this.store === null || bookId.length === 0) {
      return null;
    }
    const raw: preferences.ValueType = this.store.getSync(this.bookPrefKey(bookId), '');
    if (typeof raw !== 'string' || raw.length === 0) {
      return null;
    }
    try {
      const o = JSON.parse(raw) as BookOverride;
      const lv = o.levels;
      if (typeof lv !== 'object' || lv === null) {
        return null;
      }
      return {
        levels: {
          fontSizeLevel: safeLevel(lv.fontSizeLevel),
          lineHeightLevel: safeLevel(lv.lineHeightLevel),
          marginLevel: safeLevel(lv.marginLevel),
          fontWeightLevel: safeWeight(lv.fontWeightLevel)
        },
        theme: normalizeTheme(String(o.theme)),
        fontFamily: typeof o.fontFamily === 'string' ? o.fontFamily : ''
      };
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'book override parse failed: %{public}s', bookId);
      return null;
    }
  }

  /** 写入/更新某本书的覆盖（整包快照，调用方传当前生效值） */
  saveBookOverride(bookId: string, o: BookOverride): void {
    if (bookId.length === 0) {
      return;
    }
    this.put(this.bookPrefKey(bookId), JSON.stringify(o));
    this.flush();
  }

  /** 删掉覆盖，该书回到全局排版 */
  clearBookOverride(bookId: string): void {
    if (this.store === null || bookId.length === 0) {
      return;
    }
    this.put(this.bookPrefKey(bookId), '');
    this.flush();
  }

  hasBookOverride(bookId: string): boolean {
    return this.getBookOverride(bookId) !== null;
  }

  /** 该书生效的档位（覆盖优先，全局兜底） */
  effectiveLevels(bookId: string): LayoutLevels {
    const o: BookOverride | null = this.getBookOverride(bookId);
    return o === null ? this.levels : o.levels;
  }

  /** 该书生效的主题选择（可能是 'auto'；auto 的按小时解析在 UI 层 syncTheme） */
  effectiveTheme(bookId: string): ThemeName {
    const o: BookOverride | null = this.getBookOverride(bookId);
    return o === null ? this.theme : o.theme;
  }

  /** 该书生效的字体族 */
  effectiveFamily(bookId: string): string {
    const o: BookOverride | null = this.getBookOverride(bookId);
    return o === null ? this.fontFamily : o.fontFamily;
  }

  /* ---------------- A4：每日阅读目标 ---------------- */

  /** 每日目标（分钟）；0 = 关。档位外/脏值回落默认 20 */
  getDailyGoalMin(): number {
    if (this.store === null) {
      return DAILY_GOAL_DEFAULT;
    }
    const raw: preferences.ValueType = this.store.getSync(KEY_DAILY_GOAL, DAILY_GOAL_DEFAULT);
    if (typeof raw === 'number' && DAILY_GOAL_STEPS.indexOf(raw) >= 0) {
      return raw;
    }
    return DAILY_GOAL_DEFAULT;
  }

  setDailyGoalMin(v: number): void {
    const goal: number = DAILY_GOAL_STEPS.indexOf(v) >= 0 ? v : DAILY_GOAL_DEFAULT;
    this.put(KEY_DAILY_GOAL, goal);
    this.flush();
  }

  /** 循环切下一个档位（Stats 页点击用：关→10→20→30→60→关，与朗读定时同交互） */
  nextDailyGoal(): number {
    const cur: number = this.getDailyGoalMin();
    const at: number = DAILY_GOAL_STEPS.indexOf(cur);
    const next: number = DAILY_GOAL_STEPS[(at + 1) % DAILY_GOAL_STEPS.length];
    this.setDailyGoalMin(next);
    return next;
  }

  /** TXT 去广告（默认开） */
  isPurifyOn(): boolean {
    return this.purifyOn;
  }

  setPurify(on: boolean): void {
    this.purifyOn = on;
    this.put(KEY_PURIFY, on);
    this.flush();
  }

  /** 'off' | 's2t' | 't2s' */
  getConvertMode(): string {
    return this.convertMode;
  }

  setConvertMode(mode: string): void {
    this.convertMode = mode;
    this.put(KEY_CONVERT, mode);
    this.flush();
  }

  /** 朗读语速（产品档位 0.5~2.0，默认 1.0） */
  getTtsSpeed(): number {
    return this.ttsSpeed;
  }

  setTtsSpeed(v: number): void {
    this.ttsSpeed = clampTtsSpeed(v);
    this.put(KEY_TTS_SPEED, this.ttsSpeed);
    this.flush();
  }

  /** 朗读音色 person（13/21；白名单外一律按默认处理） */
  getTtsPerson(): number {
    return this.ttsPerson;
  }

  setTtsPerson(v: number): void {
    this.ttsPerson = clampTtsPerson(v);
    this.put(KEY_TTS_PERSON, this.ttsPerson);
    this.flush();
  }

  /** 自动滚动速度档（秒/页；脏值已归一化） */
  getScrollSpeed(): number {
    return this.scrollSpeed;
  }

  setScrollSpeed(v: number): void {
    this.scrollSpeed = normalizeScrollSpeed(v);
    this.put(KEY_SCROLL_SPEED, this.scrollSpeed);
    this.flush();
  }

  private put(key: string, value: preferences.ValueType): void {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(key, value);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'prefs put failed: %{public}s', JSON.stringify(e));
    }
  }

  /** 落盘；失败只记日志（偏好丢了不该影响读书） */
  private flush(): void {
    if (this.store === null) {
      return;
    }
    this.store.flush().catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'prefs flush failed: %{public}s', e.message);
    });
  }
}

/** 档位安全读取（A1 用）：非有限值回落默认档，不会把 NaN 灌进排版 */
function safeLevel(v: Object): number {
  const n: number = Number(v);
  return Number.isFinite(n) ? clampLevel(n) : DEFAULT_LEVELS.fontSizeLevel;
}

/** 字重安全读取（同上） */
function safeWeight(v: Object): number {
  const n: number = Number(v);
  return Number.isFinite(n) ? clampWeightLevel(n) : DEFAULT_LEVELS.fontWeightLevel;
}

/** 朗读语速夹取（NaN 与非有限值回默认，防脏值把 TTS 搞崩） */
function clampTtsSpeed(v: number): number {
  if (!isFinite(v)) {
    return TTS_SPEED_DEFAULT;
  }
  if (v < TTS_SPEED_MIN) {
    return TTS_SPEED_MIN;
  }
  if (v > TTS_SPEED_MAX) {
    return TTS_SPEED_MAX;
  }
  return v;
}

/** 音色白名单夹取（非 13/21 → 默认 13；凌飞哲下载失败由 TtsEngine 建引擎时报，不在这层） */
function clampTtsPerson(v: number): number {
  for (const p of TTS_PERSONS) {
    if (v === p) {
      return v;
    }
  }
  return TTS_PERSON_DEFAULT;
}
