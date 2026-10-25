/**
 * 阅读统计（纯逻辑，零联网、零设备 API → 可在 Node 里单测）
 *
 * 数据来源：每次进入某章到离开/切章之间记一条 ReadSession。
 * 时间基准一律用**本地时区**的"当天 0 点"（阅读习惯按自然日算，不按 UTC）。
 *
 * 设计取舍：
 * - 跨日会话（比如熬夜读到凌晨）按区间**裁剪**到每一天，不把整天算给开始那天。
 * - 脏数据（endAt < startAt、NaN）一律记 0 秒，不许把负数灌进统计。
 */
export interface ReadSession {
  bookId: string;
  chapterIndex: number;
  startAt: number;
  endAt: number;
}

/** 一次会话短于该值就不记账（翻目录、误触进去马上退出不该污染统计） */
export const MIN_SESSION_MS: number = 3000;

/** 单次会话时长（毫秒）；脏数据记 0 */
export function sessionMs(s: ReadSession): number {
  const span: number = s.endAt - s.startAt;
  if (Number.isNaN(span) || span <= 0) {
    return 0;
  }
  return span;
}

/** 某时间戳所在自然日的 0 点（本地时区） */
export function startOfDay(ts: number): number {
  const d: Date = new Date(ts);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/** 次日 0 点 */
export function startOfNextDay(ts: number): number {
  const d: Date = new Date(startOfDay(ts));
  d.setDate(d.getDate() + 1);
  return d.getTime();
}

/** 全部时长 */
export function totalMs(sessions: ReadSession[]): number {
  let sum: number = 0;
  for (let i = 0; i < sessions.length; i++) {
    sum += sessionMs(sessions[i]);
  }
  return sum;
}

/** 落在 [from, to) 内的时长；跨区间按交集裁剪 */
export function msInRange(sessions: ReadSession[], from: number, to: number): number {
  if (to <= from) {
    return 0;
  }
  let sum: number = 0;
  for (let i = 0; i < sessions.length; i++) {
    const s: ReadSession = sessions[i];
    if (sessionMs(s) <= 0) {
      continue;
    }
    const lo: number = Math.max(s.startAt, from);
    const hi: number = Math.min(s.endAt, to);
    if (hi > lo) {
      sum += hi - lo;
    }
  }
  return sum;
}

/** 某一天（含跨日裁剪）的阅读时长 */
export function msOfDay(sessions: ReadSession[], ts: number): number {
  return msInRange(sessions, startOfDay(ts), startOfNextDay(ts));
}

/**
 * 连续阅读天数。
 * - 今天读过 → 从今天往前数
 * - 今天没读但昨天读过 → 从昨天往前数（不中断，符合直觉：今天还没开始读）
 * - 都没有 → 0
 */
export function streakDays(sessions: ReadSession[], now: number): number {
  const days: number[] = [];
  for (let i = 0; i < sessions.length; i++) {
    if (sessionMs(sessions[i]) > 0) {
      const d: number = startOfDay(sessions[i].startAt);
      if (days.indexOf(d) < 0) {
        days.push(d);
      }
      // 跨日会话的结束日也算读过
      const d2: number = startOfDay(sessions[i].endAt);
      if (days.indexOf(d2) < 0) {
        days.push(d2);
      }
    }
  }
  if (days.length === 0) {
    return 0;
  }
  const today: number = startOfDay(now);
  let cursor: number = today;
  if (days.indexOf(cursor) < 0) {
    const yesterday: Date = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    cursor = yesterday.getTime();
    if (days.indexOf(cursor) < 0) {
      return 0;
    }
  }
  let count: number = 0;
  while (days.indexOf(cursor) >= 0) {
    count++;
    const prev: Date = new Date(cursor);
    prev.setDate(prev.getDate() - 1);
    cursor = prev.getTime();
  }
  return count;
}

/** 近 days 天的每日时长：下标 0 = 最早一天，末位 = 今天 */
export function dailyMs(sessions: ReadSession[], now: number, days: number): number[] {
  const out: number[] = [];
  if (days <= 0) {
    return out;
  }
  const today: number = startOfDay(now);
  for (let i = days - 1; i >= 0; i--) {
    const d: Date = new Date(today);
    d.setDate(d.getDate() - i);
    out.push(msOfDay(sessions, d.getTime()));
  }
  return out;
}

/** 时长文案：'2 小时 5 分' / '36 分' / '48 秒' / '—' */
export function durationText(ms: number): string {
  if (Number.isNaN(ms) || ms <= 0) {
    return '—';
  }
  const totalSec: number = Math.floor(ms / 1000);
  if (totalSec < 60) {
    return totalSec + ' 秒';
  }
  const totalMin: number = Math.floor(totalSec / 60);
  if (totalMin < 60) {
    return totalMin + ' 分';
  }
  const hours: number = Math.floor(totalMin / 60);
  const mins: number = totalMin % 60;
  return mins === 0 ? hours + ' 小时' : hours + ' 小时 ' + mins + ' 分';
}

/** 按书汇总（降序），用于"读得最多的书" */
export interface BookTotal {
  bookId: string;
  ms: number;
}

/* ---------------- A3：本章剩余时间（2026-10-25）---------------- */

/** 中文阅读估算速度（字/分钟）。固定值 + UI 标注「约」—— 不引个人历史（YAGNI）。 */
export const EST_WPM: number = 350;

/** 本章剩余文案：'本章还剩约 12 分钟' / '本章还剩不到 1 分钟' / ''（已到章末）。
 *  「不到 1 分钟」只用于**严格不足一分钟**（charsLeft < EST_WPM）—— 单测逼出来的
 *  口径：350 字 = 1.003 分钟，说"不到"是错的，该说"约 1 分钟"。 */
export function chapterLeftText(charsLeft: number): string {
  if (!Number.isFinite(charsLeft) || charsLeft <= 0) {
    return '';
  }
  if (charsLeft < EST_WPM) {
    return '本章还剩不到 1 分钟';
  }
  const mins: number = Math.round(charsLeft / EST_WPM);
  return `本章还剩约 ${mins} 分钟`;
}

export function byBook(sessions: ReadSession[]): BookTotal[] {
  const ids: string[] = [];
  const sums: number[] = [];
  for (let i = 0; i < sessions.length; i++) {
    const s: ReadSession = sessions[i];
    const ms: number = sessionMs(s);
    const at: number = ids.indexOf(s.bookId);
    if (at < 0) {
      ids.push(s.bookId);
      sums.push(ms);
    } else {
      sums[at] = sums[at] + ms;
    }
  }
  const out: BookTotal[] = [];
  for (let i = 0; i < ids.length; i++) {
    const item: BookTotal = { bookId: ids[i], ms: sums[i] };
    out.push(item);
  }
  out.sort((a: BookTotal, b: BookTotal) => b.ms - a.ms);
  return out;
}

/** 0~1 夹取；脏值（NaN / 负数 / 大于 1）一律收敛，不许漏进除法 */
function clamp01(v: number): number {
  if (Number.isNaN(v) || v < 0) {
    return 0;
  }
  return v > 1 ? 1 : v;
}

/** 第 i 章已确认字数；越界或脏值（负数/NaN）按「没量过」处理 */
function countAt(counts: number[], i: number): number {
  if (i < 0 || i >= counts.length) {
    return 0;
  }
  const c: number = counts[i];
  return (typeof c === 'number' && c > 0) ? c : 0;
}

/**
 * 全书进度：按**真实字数**算，而不是「第几章 ÷ 总章数」。
 *
 * 为什么不能按章数：那等于假设每章一样长。实测《暗恋·橘生淮南》100 章 39.3 万字，
 * 读到「第7章」2/3 时按章算是 8.67%，按字数真实只有 4.66% —— 虚高近一倍，
 * 因为前面夹着「版权信息」「序章」这类几百字的短章，前段失真最厉害。
 *
 * 难点：EPUB 导入阶段刻意**不读正文**（否则导入 = 解压上百个 HTML），所以导入时
 * 根本拿不到每章字数，chapters.start_char/end_char 对 EPUB 恒为 0。
 *
 * 解法：**读到哪、算到哪**。每展开一章就把它真实字数回填 chapters.char_count
 * （整章全文已在内存，白量）；没读过的章用「已确认章的平均字数」外推。
 * 于是第一眼就有合理估值，越读越准，读过一遍后完全精确。
 *
 * @param counts 各章已确认字数（下标 = 章序，未量过 = 0）；长度可以短于 total
 * @param total 总章数
 * @param chapterIndex 当前章序（越界会被夹取，防止调用方传递野值算出 NaN）
 * @param pagePercent 当前章读到几成（0~1）
 */
export function bookPercentOf(counts: number[], total: number, chapterIndex: number,
  pagePercent: number): number {
  if (total <= 0) {
    return 0;
  }
  let idx: number = chapterIndex;
  if (idx < 0) {
    idx = 0;
  }
  if (idx >= total) {
    idx = total - 1;
  }
  let knownTotal: number = 0;
  let knownCount: number = 0;
  for (let i = 0; i < total; i++) {
    const c: number = countAt(counts, i);
    if (c > 0) {
      knownTotal = knownTotal + c;
      knownCount = knownCount + 1;
    }
  }
  if (knownCount === 0) {
    // 一章都没量过（刚导入还没展开任何章）→ 退回按章口径，总比算出 0 / NaN 强
    return (idx + clamp01(pagePercent)) / total;
  }
  const avg: number = knownTotal / knownCount;
  // 已读 = 前面所有整章（未知按均值外推）+ 当前章的进度份额
  let read: number = 0;
  for (let i = 0; i < idx; i++) {
    const c: number = countAt(counts, i);
    read = read + (c > 0 ? c : avg);
  }
  const here: number = countAt(counts, idx);
  read = read + (here > 0 ? here : avg) * clamp01(pagePercent);
  const totalChars: number = knownTotal + (total - knownCount) * avg;
  // 外推可能让「当前读到」略超总量（当前章特别长而外推偏小），收敛到 100% 内
  return totalChars > 0 ? Math.min(read / totalChars, 1) : 0;
}
