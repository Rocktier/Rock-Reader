/**
 * 书架副标题 + TXT/MD 署名探测（纯逻辑，零设备 API → CI 可单测）
 *
 * 背景（P0-5 2026-10-29）：
 *  - EPUB/MOBI 导入时已把作者写进 BookRecord.author，但书架卡片**一个字都不显示**；
 *  - TXT/MD 解析器压根没有 author 字段，书架上 author 恒为空。
 *
 * 方针（克制、可测、不误导）：
 *  1. 卡片副标题：有作者用作者；没作者用格式大写（TXT/MD/EPUB…）兜底 —— 永远不留空白。
 *     绝不猜"佚名"之类：那等于替用户编造信息，格式才是诚实可知的事实。
 *  2. TXT/MD 的作者只在能从**文件名**里以约定俗成的分隔可靠切出来时才认领
 *     （中文电子书文件名常见「书名-作者.txt」「《书名》作者.md」）。
 *     正文里"作者："这种要解析全文、且极易把正文台词误当作者 —— YAGNI，本版不做。
 *     认领不出来就继续留空，交给第 1 条的格式兜底。
 */

export interface ShelfSubtitle {
  /** 展示文案 */
  text: string;
  /** true = 是作者；false = 回退成了格式标签 */
  isAuthor: boolean;
}

/** 卡片副标题：作者优先，缺则用格式大写兜底（永不空白、永不编造）。 */
export function shelfSubtitle(author: string, format: string): ShelfSubtitle {
  const a: string = author === null || author === undefined ? '' : author.trim();
  if (a.length > 0) {
    return { text: a, isAuthor: true };
  }
  const f: string = format === null || format === undefined ? '' : format.trim().toUpperCase();
  return { text: f.length > 0 ? f : '本地书籍', isAuthor: false };
}

/**
 * 从文件名切出作者（只认两种高置信分隔，宁缺毋滥）：
 *  - 连字符：`书名-作者` / `书名 - 作者` / `书名_作者`（取最后一段）
 *  - 书名号：《书名》作者 / 《书名》 作者
 *
 * 规则收紧以避免误伤：
 *  - 分隔后的作者段必须 1~16 字符；中文人名多 ≤8 字，外国译名（含间隔号）也少有 >16；
 *    过长说明是副标题/描述，不认领（宁缺毋滥）；
 *  - 书名号必须成对出现；
 *  - 扩展名先剥掉；
 *  - 结果去掉首尾空白与包裹的书名号残留。
 * 返回 '' 表示"没把握"，由调用方走格式兜底。
 */
export function authorFromFileName(fileName: string): string {
  if (fileName === null || fileName === undefined) {
    return '';
  }
  let base: string = fileName.trim();
  const dot: number = base.lastIndexOf('.');
  if (dot > 0) {
    base = base.substring(0, dot);
  }
  if (base.length === 0) {
    return '';
  }

  // ① 《书名》作者 —— 书名号后紧跟的部分
  //    《 和 》 各占 1 个 UTF-16 单元，close+1 才是作者起点（+2 会吞掉作者首字）。
  const close: number = base.indexOf('》');
  const open: number = base.indexOf('《');
  if (open >= 0 && close > open) {
    let tail: string = base.substring(close + 1).trim();
    // 兼容「《书名》- 作者」混合写法：先剥掉贴在书名号后的分隔符
    tail = tail.replace(/^[\-—–_\s]+/, '').trim();
    if (plausibleAuthor(tail)) {
      return tail;
    }
  }

  // ② 书名 - 作者（连字符/下划线分隔，取最后一段）
  //    用正则找最后一个分隔符，避免"上-中-下"这类多段全被当作者
  const m: RegExpMatchArray | null = base.match(/[\-—–_]\s*([^\-—–_]+)\s*$/);
  if (m !== null && m.length >= 2) {
    const tail: string = (m[1] as string).trim();
    if (plausibleAuthor(tail)) {
      return tail;
    }
  }

  return '';
}

/** 作者段是否可信：1~24 字符，且不含明显是副标题的特征 */
function plausibleAuthor(s: string): boolean {
  if (s.length < 1 || s.length > 16) {
    return false;
  }
  // 括号里带"修订/全x册/选集/第x版"这类多半是版本描述，不是作者；
  // 但「余华（著）」「鲁迅 译」是署名，不能误杀 —— 只排版本词，不排著/译/校/编。
  if (/[（(【\[]/.test(s) && /(修订|版|册|卷|集|全集|选集|完结)/.test(s)) {
    return false;
  }
  return true;
}
