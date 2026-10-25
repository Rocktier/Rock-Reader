/**
 * 服务卡片数据层（B1，2026-10-25 党哥批准）
 *
 * 对标 Apple Books 桌面卡片 / Kindle「续读」：桌面一眼看到当前在读的书与进度，
 * 点一下直达上次读到的位置。**零联网、零新权限** —— 数据全部来自本地库。
 *
 * 三条数据通路（对应卡片的三个时机）：
 *  ① onAddForm（首次加卡片，**同步**返回）→ 读 preferences 快照（sync，立即可画）
 *  ② onUpdateForm（系统请求刷新 / 改尺寸）→ 查库后 formProvider.updateForm
 *  ③ 阅读页 persistProgress（用户翻页）→ 节流后推 updateForm（限流见 pushCardUpdate）
 *
 * 为什么要有快照：onAddForm 是同步签名，而查库是异步的。没有快照，
 * 加卡片的一瞬间只能画空卡。快照 = 上一次 persistProgress 留下的副本，
 * 由本模块负责读写，Reader 无感。
 */
import { preferences, relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { formBindingData, formProvider } from '@kit.FormKit';
import { Context } from '@kit.AbilityKit';
import { chapterLeftText } from '../engine/stats/ReadStats';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';
const DB_NAME: string = 'rockreader.db';
const PREFS_NAME: string = 'rockreader_prefs';
/** 卡片内容快照（JSON）；给 onAddForm 同步首绘用 */
const KEY_CARD_SNAPSHOT: string = 'card_snapshot';
/**
 * 「本章剩余字数」提示（JSON）。为什么需要它：EPUB 的 chapters 表不存 end_char
 * （整章一次性解析，见 EpubParse），卡片没有正文在内存里算不出剩余量；
 * Reader.persistProgress 时顺手把当前章的剩余字数写进来，卡片直接取用。
 * TXT 书本身有 end_char，此提示与之取大（哪个有效用哪个）。
 */
const KEY_CARD_LEFT: string = 'card_left_hint';

/** 剩余字数提示（按书+章校验，防串卡片） */
export interface CardLeftHint {
  bookId: string;
  chapterIndex: number;
  charsLeft: number;
}

/** 推送节流：同章内百分比小变化最多 60s 推一次（翻页狂飙时不骚扰卡片管理服务） */
const PUSH_MIN_INTERVAL_MS: number = 60000;

/** 卡片要显示的内容（不含尺寸 —— 尺寸是每个卡片实例自己的事，见 WidgetCard） */
export interface CardData {
  bookId: string;
  /** 书名；无书时 '' */
  title: string;
  author: string;
  /** 当前章名 */
  chapter: string;
  /** 0~100 整数 */
  percent: number;
  /** 本章剩余字符数；0 = 无数据（卡片文案由 chapterLeftText 兜底成 ''） */
  charsLeft: number;
}

/**
 * 卡片 binding data 的显式形状（ArkTS 铁律 arkts-no-untyped-obj-literals：
 * 对象字面量必须对应声明的接口/类，不能是 Record）。卡片页 @LocalStorageProp 逐个接。
 */
export interface CardFormData {
  hasBook: boolean;
  bookId: string;
  bookTitle: string;
  author: string;
  chapter: string;
  percent: number;
  leftText: string;
  /** '2*2' | '2*4' */
  dimension: string;
}

export function emptyCardData(): CardData {
  return { bookId: '', title: '', author: '', chapter: '', percent: 0, charsLeft: 0 };
}

/**
 * 查「最近在读」：progress 表按 updated_at 倒序第一行 + 该书信息 + 当前章。
 *
 * 任何一步失败都回落空卡 —— 卡片不是关键路径，不能拖累调用方（阅读页落库
 * 也会调 pushCardUpdate，那边绝不能抛）。
 */
export async function readCardData(context: Context): Promise<CardData> {
  try {
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    const rs = await store.querySql(
      'SELECT p.book_id AS bid, p.chapter_index AS cidx, p.char_offset AS coff, p.percent AS pct, ' +
      'b.title AS title, b.author AS author FROM progress p ' +
      'JOIN books b ON b.id = p.book_id ORDER BY p.updated_at DESC LIMIT 1');
    if (!rs.goToNextRow()) {
      rs.close();
      return emptyCardData();
    }
    const d: CardData = {
      bookId: rs.getString(rs.getColumnIndex('bid')),
      title: rs.getString(rs.getColumnIndex('title')),
      author: rs.getString(rs.getColumnIndex('author')),
      chapter: '',
      percent: Math.round(rs.getDouble(rs.getColumnIndex('pct')) * 100),
      charsLeft: 0
    };
    const chapterIndex: number = rs.getLong(rs.getColumnIndex('cidx'));
    const charOffset: number = rs.getLong(rs.getColumnIndex('coff'));
    rs.close();
    if (d.bookId.length === 0) {
      return emptyCardData();
    }
    // 当前章（标题）。章查不到就用序号顶着。
    const cs = await store.querySql(
      'SELECT title, start_char, end_char FROM chapters WHERE book_id = ? AND idx = ?',
      [d.bookId, chapterIndex]);
    if (cs.goToNextRow()) {
      d.chapter = cs.getString(cs.getColumnIndex('title'));
      const endChar: number = cs.getLong(cs.getColumnIndex('end_char'));
      d.charsLeft = endChar > charOffset ? endChar - charOffset : 0;
    }
    cs.close();
    if (d.chapter.length === 0) {
      d.chapter = `第 ${chapterIndex + 1} 章`;
    }
    // 阅读页写下的「本章剩余」提示（EPUB 场景的唯一数据源；与 end_char 取大）
    const hint: CardLeftHint = loadCardLeftHint(context);
    if (hint.bookId === d.bookId && hint.chapterIndex === chapterIndex && hint.charsLeft > d.charsLeft) {
      d.charsLeft = hint.charsLeft;
    }
    if (d.author.length === 0) {
      d.author = '未知作者';
    }
    return d;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'readCardData failed: %{public}s', JSON.stringify(e));
    return emptyCardData();
  }
}

/** 卡片内容 → binding data（dimension 可缺省；卡片页用 @LocalStorageProp 逐个接） */
export function cardFormData(d: CardData, dimension: string = '2*2'): CardFormData {
  return {
    hasBook: d.bookId.length > 0,
    bookId: d.bookId,
    bookTitle: d.title,
    author: d.author,
    chapter: d.chapter,
    percent: d.percent,
    leftText: chapterLeftText(d.charsLeft),
    dimension: dimension
  };
}

/** 写快照（同步）：下次 onAddForm 冷启动也能立刻画出上次的内容 */
export function saveCardSnapshot(context: Context, d: CardData): void {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    store.putSync(KEY_CARD_SNAPSHOT, JSON.stringify(d));
    store.flush();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'saveCardSnapshot failed: %{public}s', JSON.stringify(e));
  }
}

/** 读快照（同步）；没有/脏值 → 空卡 */
export function loadCardSnapshot(context: Context): CardData {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    const raw: preferences.ValueType = store.getSync(KEY_CARD_SNAPSHOT, '');
    if (typeof raw !== 'string' || raw.length === 0) {
      return emptyCardData();
    }
    const parsed = JSON.parse(raw) as CardData;
    // 逐个字段兜底：快照是旧版本/脏数据时按空卡显示，不让 undefined 漏进 UI
    return {
      bookId: typeof parsed.bookId === 'string' ? parsed.bookId : '',
      title: typeof parsed.title === 'string' ? parsed.title : '',
      author: typeof parsed.author === 'string' ? parsed.author : '',
      chapter: typeof parsed.chapter === 'string' ? parsed.chapter : '',
      percent: typeof parsed.percent === 'number' ? parsed.percent : 0,
      charsLeft: typeof parsed.charsLeft === 'number' ? parsed.charsLeft : 0
    };
  } catch (e) {
    return emptyCardData();
  }
}

/** 写「本章剩余」提示（同步，Reader.persistProgress 里调） */
export function saveCardLeftHint(context: Context, hint: CardLeftHint): void {
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    store.putSync(KEY_CARD_LEFT, JSON.stringify(hint));
    store.flush();
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'saveCardLeftHint failed: %{public}s', JSON.stringify(e));
  }
}

/** 读「本章剩余」提示（同步）；没有/脏值 → 空提示 */
export function loadCardLeftHint(context: Context): CardLeftHint {
  const empty: CardLeftHint = { bookId: '', chapterIndex: -1, charsLeft: 0 };
  try {
    const store: preferences.Preferences = preferences.getPreferencesSync(context, { name: PREFS_NAME });
    const raw: preferences.ValueType = store.getSync(KEY_CARD_LEFT, '');
    if (typeof raw !== 'string' || raw.length === 0) {
      return empty;
    }
    const parsed = JSON.parse(raw) as CardLeftHint;
    if (typeof parsed.bookId !== 'string' || typeof parsed.chapterIndex !== 'number'
      || typeof parsed.charsLeft !== 'number') {
      return empty;
    }
    return parsed;
  } catch (e) {
    return empty;
  }
}

/* ---------------- 推送（阅读页落库后调；限流）---------------- */

let lastPushKey: string = '';
let lastPushAt: number = 0;

/**
 * 读最新数据 → 写快照 → 推给桌面上所有本应用卡片。
 *
 * 限流策略（两次过滤）：
 *  ① 内容没变（key 相同）→ 不推；
 *  ② 同章内只有百分比小变化 → 至少间隔 PUSH_MIN_INTERVAL_MS 才推一次。
 * 换书/换章立即推（key 的前两段变了）。
 *
 * 调用方（Reader.persistProgress 的 then 里）fire-and-forget，内部全兜异常。
 *
 * @param force 最后一次冲刺：跳过全部限流，必须把当前真值推到桌面。
 *   **为什么必须有 force**：限流版的执行顺序是「先写快照 → 再决定推不推」＝
 *   命中限流时快照已经是新值、桌面卡片还是旧值，两者不一致；更糟的是被吞掉的这一次
 *   可能就是用户离开阅读页的最后一次进展，之后没有新的翻页不会再有机会补推。
 *   所以 Reader 在 force 落库（退出页面 / 换章）时同步 force 推一次，保证桌面看到的
 *   永远是离开那一刻的真实进度。
 */
export async function pushCardUpdate(context: Context, force: boolean = false): Promise<void> {
  try {
    const d: CardData = await readCardData(context);
    saveCardSnapshot(context, d);
    const key: string = `${d.bookId}|${d.chapter}|${d.percent}`;
    if (!force) {
      if (key === lastPushKey) {
        return;
      }
      const now: number = Date.now();
      const prev: string[] = lastPushKey.split('|');
      const chapterChanged: boolean = prev.length !== 3 || prev[0] !== d.bookId || prev[1] !== d.chapter;
      if (!chapterChanged && now - lastPushAt < PUSH_MIN_INTERVAL_MS) {
        return;
      }
      lastPushAt = now;
    }
    lastPushKey = key;
    // RunningFormInfo（API 20+）才有 formId 与 dimension；FormInfo 没有这两个字段
    const forms = await formProvider.getPublishedRunningFormInfos();
    for (const f of forms) {
      const data: CardFormData = cardFormData(d, dimLabel(f.dimension));
      await formProvider.updateForm(f.formId, formBindingData.createFormBindingData(data));
    }
    hilog.info(DOMAIN, TAG, 'card pushed, forms=%{public}d', forms.length);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'pushCardUpdate failed: %{public}s', JSON.stringify(e));
  }
}

/** FormDimension 枚举值 → 卡片页认的字符串标签（2=2×2，3=2×4，其余按 2×2） */
export function dimLabel(dimension: number): string {
  return dimension === 3 ? '2*4' : '2*2';
}
