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
