/**
 * 真实排版器：@ohos.graphics.text（ArkGraphics2D）
 *
 * 设计依据：docs/v1-design.md §6 —— **整章一次 layoutSync 拿全部行区间**，
 * 之后分页退化成"按行数切页 + substring"，翻页零计算。
 *
 * 官方 API 依据（2026-09-18 读 interface_sdk-js 的 @ohos.graphics.text.d.ts 核实，非博客）：
 *   ParagraphBuilder(paragraphStyle, fontCollection)
 *     → addText(text) → build() → Paragraph
 *   Paragraph.layoutSync(width: double)
 *   Paragraph.getLineMetrics(): Array<LineMetrics>   // LineMetrics.endIndex = 该行结束字符下标（不含）
 *   LineMetrics 字段：startIndex / endIndex / ascent / descent / height / width / left / baseline / lineNumber / topHeight
 *
 * 单位：本文件内**一切长度都是 px**（graphics.text 的原生单位）。
 *   调用方（pages/Reader.ets）负责 fp→px、vp→px 的换算。
 *
 * ⚠️ 不变量（改代码时务必守住）：测量用的 fontSizePx / widthPx 必须与渲染 Text 的
 *   字号与可用宽度**完全一致**，否则断行不一致 → 页面会溢出。
 *   lineHeight 不参与断行（只决定每页放几行），因此渲染侧的 lineHeight 用同一个 lineHeightPx。
 */
import { text } from '@kit.ArkGraphics2D';
import { Paginator, LayoutBox } from './Paginator';
import { PageTable, buildPageTable, linesPerPage } from './PageTableBuilder';

/**
 * 一次排版，拿到每行的结束字符下标（不含）。
 * 返回数组为单调不减序列；末项补齐到正文末尾，保证最后一页不漏字。
 */
export function measureLineEnds(
  content: string,
  fontSizePx: number,
  widthPx: number,
  fontFamily: string = ''
): number[] {
  const ends: number[] = [];
  if (content.length === 0 || widthPx <= 0 || fontSizePx <= 0) {
    return ends;
  }

  const collection: text.FontCollection = text.FontCollection.getGlobalInstance();
  const textStyle: text.TextStyle = { fontSize: fontSizePx };
  if (fontFamily.length > 0) {
    // 必须与渲染字体一致，否则断行不同 → 页面会溢出
    textStyle.fontFamilies = [fontFamily];
  }
  const paragraphStyle: text.ParagraphStyle = { textStyle: textStyle };

  const builder: text.ParagraphBuilder = new text.ParagraphBuilder(paragraphStyle, collection);
  builder.addText(content);
  const paragraph: text.Paragraph = builder.build();
  paragraph.layoutSync(widthPx);

  const metrics: Array<text.LineMetrics> = paragraph.getLineMetrics();
  let prev: number = 0;
  for (let i: number = 0; i < metrics.length; i++) {
    // 防御：万一 endIndex 出现回退或越界，夹紧成单调序列（宁可多切一页，不能丢字/崩）
    let end: number = Math.floor(metrics[i].endIndex);
    if (end < prev) {
      end = prev;
    }
    if (end > content.length) {
      end = content.length;
    }
    ends.push(end);
    prev = end;
  }
  if (ends.length > 0 && ends[ends.length - 1] < content.length) {
    ends[ends.length - 1] = content.length;
  }
  return ends;
}

export class TextPaginator implements Paginator {
  paginate(content: string, box: LayoutBox): PageTable {
    const ends: number[] = measureLineEnds(content, box.fontSizePx, box.widthPx, box.fontFamily);
    const perPage: number = linesPerPage(box.heightPx, box.lineHeightPx);
    const table: PageTable = buildPageTable(ends, perPage, content.length);
    table.signature = box.signature;
    return table;
  }
}
