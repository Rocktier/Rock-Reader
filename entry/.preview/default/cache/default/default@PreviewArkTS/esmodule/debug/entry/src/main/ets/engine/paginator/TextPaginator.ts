import text from "@ohos:graphics.text";
import type { Paginator, LayoutBox } from './Paginator';
import { buildPageTable, linesPerPage } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/PageTableBuilder";
import type { PageTable } from "@bundle:com.rocktier.rockreader/entry/ets/engine/paginator/PageTableBuilder";
/**
 * 一次排版，拿到每行的结束字符下标（不含）。
 * 返回数组为单调不减序列；末项补齐到正文末尾，保证最后一页不漏字。
 */
/** 已挂进 FontCollection 的字体族（进程内只挂一次，避免重复加载同一个文件） */
const loadedFamilies: string[] = [];
export function measureLineEnds(content: string, fontSizePx: number, widthPx: number, fontFamily: string = '', fontPath: string = ''): number[] {
    const ends: number[] = [];
    if (content.length === 0 || widthPx <= 0 || fontSizePx <= 0) {
        return ends;
    }
    const collection: text.FontCollection = text.FontCollection.getGlobalInstance();
    if (fontFamily.length > 0 && fontPath.length > 0 && loadedFamilies.indexOf(fontFamily) < 0) {
        // **下载字体必须显式挂进测量端**：ArkUI 的 registerFont 只作用于 UI 渲染，
        // 不保证 graphics.text 的测量集合里有这个字体；不挂的话测量用回退字体断行，
        // 渲染却用真字体 → 两边行数不同 → 页面溢出（"最后一行被裁"）。
        // 挂进全局集合（而非新建局部集合）是为了保留系统字体的缺字回退。
        collection.loadFontSync(fontFamily, fontPath);
        loadedFamilies.push(fontFamily);
    }
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
        const ends: number[] = measureLineEnds(content, box.fontSizePx, box.widthPx, box.fontFamily, box.fontPath);
        const perPage: number = linesPerPage(box.heightPx, box.lineHeightPx);
        const table: PageTable = buildPageTable(ends, perPage, content.length);
        table.signature = box.signature;
        return table;
    }
}
