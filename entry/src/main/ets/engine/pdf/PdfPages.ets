/**
 * PDF 的纯逻辑：页码 ↔ 进度 ↔ 用户输入。
 *
 * 为什么单独一层：PDF 是**固定版式**，没有"章内字符偏移"这个概念，和 TXT/EPUB 那条
 * 字符流管线根本不同源。凡是要做换算的地方（进书架进度条、续读定位、跳页输入、
 * 底部页码文案）都收在这里，**零 @kit 依赖 ⇒ node 可测**。
 *
 * ── 为什么 PDF 能零 schema 改动接进现有库（2026-11-05 实测 SDK 后定） ──
 * `ReadingProgress` 有三个字段：chapterIndex / charOffset / percent。
 * PDF 就借这个坐标系：
 *   chapterIndex = **页码（0 基）**
 *   charOffset   = 恒 0（PDF 没有章内偏移）
 *   percent      = 由页码算出（见 percentOfPage）
 * 于是进度表、书签表、书架进度条、`listAllProgress()` 全都不用动。
 * 代价是「章节名别往 PDF 上套」—— PDF 的目录（bookmark）是另一套东西，一期不做。
 *
 * ── 页面口径（党哥 2026-11-05：我们的 PDF 就是论文和电子书文档） ──
 * 两类都是**有文字层**的（不是扫描件），所以：
 *   · 文字搜索可用（`PdfController.searchKey`）
 *   · 文字可选中（`registerTextSelectedListener`）⇒ 二期可做摘录
 *   · 默认「适应宽度」：论文常是双栏，适应页面会小到看不清；电子书适应宽度也正好
 */

/** BookRecord.format 里 PDF 的取值（小写扩展名，与 parseKindOf 的落库口径一致） */
export const PDF_FORMAT: string = 'pdf';

/** 这个 format 是不是 PDF —— 书架点击、导入校验、阅读页的**唯一**判定入口 */
export function isPdfFormat(format: string): boolean {
  return format === PDF_FORMAT;
}

/**
 * 页码夹紧到合法区间。
 * ⚠️ 为什么必须夹：total 可能为 0（刚打开还没 load 完）或 1（单页 PDF），
 * 任何 `page / (total - 1)` 都会除零得 Infinity/NaN，再拿去算 percent 会写进库里，
 * 书架进度条就再也画不出来了（`NaN` 会污染后续所有计算）。
 */
export function clampPage(pageIndex: number, total: number): number {
  if (!Number.isInteger(total) || total <= 0) {
    return 0;
  }
  if (!Number.isInteger(pageIndex) || pageIndex < 0) {
    return 0;
  }
  return pageIndex > total - 1 ? total - 1 : pageIndex;
}

/**
 * 页码 → 书架用的进度（0~1）。
 *
 * 口径：**用 (总页数 - 1) 做分母**，让第 0 页 = 0%、最后一页 = 100%。
 * 若用 `(page + 1) / total`，一打开就是 1/total —— 300 页的书没问题，
 * 但 3 页的论文一打开就显示 33%，书架看着像"读过了"。
 *
 * total <= 1 时返回 1：单页 PDF 只要打开过，就是"这一整本书都看过了"。
 */
export function percentOfPage(pageIndex: number, total: number): number {
  if (!Number.isInteger(total) || total <= 0) {
    return 0;
  }
  if (total === 1) {
    return 1;
  }
  const p: number = clampPage(pageIndex, total);
  return p / (total - 1);
}

/**
 * 从库里存的进度反推"从第几页开始读"。
 *
 * 两个来源都认，因为用户可能：
 *   a) 之前在别的设备/版本上读过（chapterIndex 是页码，精确）—— 优先；
 *   b) 只有 percent 可信（比如版本升级改了记录方式）—— 反推。
 * ⚠️ 反推时用 `Math.round` 而不是 `floor`：读到 66% 时用户期望的是"回到那一页附近"，
 * floor 会永远偏向前一页，连续几次续读就像在往回退。
 */
export function startPageOf(chapterIndex: number, percent: number, total: number): number {
  if (!Number.isInteger(total) || total <= 0) {
    return 0;
  }
  if (Number.isInteger(chapterIndex) && chapterIndex >= 0 && chapterIndex < total) {
    return chapterIndex;
  }
  if (typeof percent !== 'number' || !Number.isFinite(percent) || percent <= 0) {
    return 0;
  }
  const p: number = Math.round(percent * (total - 1));
  return clampPage(p, total);
}

/**
 * 底部页码文案：「12 / 340」。
 * 面向用户一律 **1 基**显示 —— 内部 0 基，出界面就 +1，这个转换只在这里做，
 * 别让人手去 +1（漏一处就是"点第 12 页停在 11 页"）。
 */
export function pageLabel(pageIndex: number, total: number): string {
  if (!Number.isInteger(total) || total <= 0) {
    return '';
  }
  return (clampPage(pageIndex, total) + 1) + ' / ' + total;
}

/**
 * 跳页输入框的解析 —— 返回 **0 基页码**，无效输入返回 -1。
 *
 * 支持三种写法（都按用户直觉来，不要求用户懂"从 0 开始"）：
 *   `12`      → 第 12 页
 *   `12/340`  → 第 12 页（有些 PDF 页码就长这样，用户会直接抄进来）
 *   `65%`     → 全书 65% 处
 *
 * ⚠️ 空串、非数字、越界一律返回 -1 让调用方**什么都不做**。
 * 不"猜个最近的"——用户输错了就停在原地，比跳到莫名其妙的地方好。
 */
export function parsePageInput(text: string, total: number): number {
  if (!Number.isInteger(total) || total <= 0) {
    return -1;
  }
  const t: string = text.trim();
  if (t.length === 0) {
    return -1;
  }
  if (t.endsWith('%')) {
    const pctText: string = t.substring(0, t.length - 1).trim();
    const pct: number = Number(pctText);
    if (!Number.isFinite(pct) || pctText.length === 0 || pct < 0 || pct > 100) {
      return -1;
    }
    return clampPage(Math.round((pct / 100) * (total - 1)), total);
  }
  // `12/340` 这种：只取斜杠前的那段
  const slash: number = t.indexOf('/');
  const head: string = slash > 0 ? t.substring(0, slash).trim() : t;
  const n: number = Number(head);
  if (!Number.isFinite(n) || head.length === 0) {
    return -1;
  }
  const idx: number = Math.round(n) - 1;
  if (idx < 0 || idx > total - 1) {
    return -1;
  }
  return idx;
}

/**
 * PDF 元数据里的 title 能不能当书名用 —— 返回 '' = 不可用，调用方退回文件名。
 *
 * 为什么需要这一步（论文场景的实情）：大量论文 PDF 是用 Word 导出的，
 * metadata.title 就是 **`Microsoft Word - 论文初稿.doc`** 这种东西。
 * 直接拿来当书架标题，用户看到的是自己当年随手起的草稿名，而不是论文标题 ——
 * 比用文件名（`Attention Is All You Need.pdf`）更糟。
 *
 * 判定：去空白后为空、长度 < 2、或命中软件默认前缀，一律不用。
 */
export function pickPdfTitle(metaTitle: string, fileNameTitle: string): string {
  const t: string = metaTitle.trim();
  const fallback: string = fileNameTitle.trim();
  if (t.length < 2) {
    return fallback;
  }
  const lower: string = t.toLowerCase();
  // 这些前缀是导出软件塞的默认值，不是作者起的名字
  const junk: string[] = ['microsoft word', 'microsoft powerpoint', 'untitled', '无标题', '未命名'];
  for (let i = 0; i < junk.length; i++) {
    if (lower.startsWith(junk[i])) {
      return fallback;
    }
  }
  return t;
}

/**
 * `PdfDocument.loadDocument` 的 ParseResult → 导入拒绝原因。
 *
 * 入参是**数字**而不是 pdfService 的枚举，是为了让这层不碰 @kit（测试能跑）。
 * 枚举值来自 `@hms.officeservice.pdfservice.d.ts`：
 *   0 PARSE_SUCCESS / 1 ERROR_FILE（文件读不出）/ 2 ERROR_FORMAT（不是 PDF）
 *   3 ERROR_PASSWORD（要密码）/ 4 ERROR_HANDLER（内部错误）
 *
 * ⚠️ 加密必须单独成一个原因：用户看到"文件损坏"会以为文件坏了去重下，
 * 而加密 PDF 重下多少次都一样，得明确告诉他"这本有密码"。
 */
export function pdfFailReason(parseResult: number): string {
  if (parseResult === 0) {
    return '';
  }
  if (parseResult === 3) {
    return 'PDF_ENCRYPTED';
  }
  return 'PDF_BROKEN';
}
