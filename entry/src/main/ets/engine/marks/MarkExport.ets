/**
 * 标记导出：把这本书的书签与摘录组装成一段纯文本
 *
 * 为什么单独抽一层：这一层**不 import 任何 @ohos**，能在 Node 里被单测
 * （CI 没有模拟器，这是唯一能自动验证的手段）。页面只管拿字符串去分享。
 *
 * 为什么导出成"文本"而不是某种结构化文件：用户拿走摘录之后是要**贴进别的地方**的
 * —— 微信、备忘录、Obsidian、论文里。JSON/XML 一个应用场景都没有，
 * 反而会逼用户先找个软件打开它。纯文本是最大公约数。
 *
 * 本文件严禁引入 @ohos.* / ArkUI —— 它必须能在 Node 里跑。
 */
import { BookmarkRow, HighlightRow } from '../../common/Types';

/** 脏值（null / undefined / 非字符串）一律按空串，不许漏到导出文本里 */
function textOf(v: string): string {
  return (v === undefined || v === null) ? '' : v;
}

/** 补零到两位 */
function pad2(n: number): string {
  return n < 10 ? '0' + n : '' + n;
}

/**
 * 导出日期（2026-10-27）。
 *
 * **必须走本地时区**：getMonth/getDate 读的是本地时钟。
 * 用 toISOString() 会走 UTC —— 东八区 00–08 点这批用户会被写成"昨天"，
 * 这是家族踩过的坑（CI 有守门单测盯着）。
 */
export function exportDateText(d: Date): string {
  return d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
}

/**
 * 组装导出正文。
 *
 * 版式是刻意的：书名冠顶，然后「摘录」「书签」两截，每条带章序。
 * 摘录用直角引号括出原文、批注另起一行以 `>` 打头 ——
 * 贴到任何地方都不用二次整理，扫一眼能分清哪句是作者写的、哪句是自己写的。
 */
export function buildMarksExport(
  title: string,
  author: string,
  highlights: HighlightRow[],
  bookmarks: BookmarkRow[],
  now: Date
): string {
  const lines: string[] = [];
  const name: string = textOf(title);
  const who: string = textOf(author);

  lines.push('《' + name + '》');
  if (who.length > 0) {
    lines.push(who);
  }
  lines.push('导出自 Rock阅读 · ' + exportDateText(now));
  lines.push('');

  if (highlights.length > 0) {
    lines.push('── 摘录（' + highlights.length + ' 条）──');
    lines.push('');
    for (let i = 0; i < highlights.length; i++) {
      const h: HighlightRow = highlights[i];
      lines.push((i + 1) + '. 第 ' + (h.chapterIndex + 1) + ' 章');
      lines.push('「' + textOf(h.excerpt) + '」');
      if (textOf(h.note).length > 0) {
        lines.push('    > ' + textOf(h.note));
      }
      lines.push('');
    }
  }

  if (bookmarks.length > 0) {
    lines.push('── 书签（' + bookmarks.length + ' 个）──');
    lines.push('');
    for (let i = 0; i < bookmarks.length; i++) {
      const b: BookmarkRow = bookmarks[i];
      lines.push((i + 1) + '. 第 ' + (b.chapterIndex + 1) + ' 章');
      if (textOf(b.excerpt).length > 0) {
        lines.push('    ' + textOf(b.excerpt));
      }
      lines.push('');
    }
  }

  if (highlights.length === 0 && bookmarks.length === 0) {
    lines.push('（这本书还没有任何标记）');
    lines.push('');
  }

  return lines.join('\n');
}
