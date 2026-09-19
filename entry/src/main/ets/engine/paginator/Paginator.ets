/**
 * 排版器契约（**纯逻辑，可 CI 单测** —— 本文件不 import 任何 @ohos / @kit）
 *
 * 为什么做成接口：真实实现要调 @ohos.graphics.text（设备才有），
 * 而 CI 里没有设备；接口隔离后，CI 可以注入"按固定字数切页"的假实现，
 * 把「导入 → 进度 → 翻页 → 落库」整条链路测穿（docs/v1-design.md §3 / §9）。
 */
import { PageRange, PageTable } from './PageTableBuilder';

export interface LayoutBox {
  /** 字号（px，必须与渲染字体一致） */
  fontSizePx: number;
  /** 行高（px，必须与渲染 lineHeight 一致） */
  lineHeightPx: number;
  /** 正文可用宽度（px，已扣掉左右边距） */
  widthPx: number;
  /** 正文可用高度（px，已扣掉页眉页脚） */
  heightPx: number;
  /** 字体族；'' = 系统默认 */
  fontFamily: string;
  /** 该字体在沙箱里的文件路径（**下载字体**才有）；'' = 系统字体，无需加载 */
  fontPath: string;
  /**
   * 字重数值（400/500/700，来自 LayoutStyle 档位表）
   * ⚠️ 必须传给测量端：加粗会改变字宽与断行，若测量不加权而渲染加权，
   * 两边断行不一致 → 页面溢出（末行被裁）。已进 layoutKey。
   */
  fontWeight: number;
  /** 缓存键，见 common/LayoutStyle.layoutKey */
  signature: string;
}

export interface Paginator {
  /** 把整章文本切成页表；失败必须抛错（由调用方降级），不得返回半成品 */
  paginate(content: string, box: LayoutBox): PageTable;
}

/**
 * 页表 LRU 缓存（内存）。
 * 设计依据：docs/v1-design.md §5 —— 签名命中时**翻页纯索引切换，零计算**，这是"快"的根。
 * ponytail: 不落库（BookDb 里没有 pagetables 表）—— 一章排版只要毫秒级，
 *   落库反而要处理签名失效与 IO；等真机上量到卡顿再升级。
 */
export class PageCache {
  private tables: Map<string, PageTable> = new Map<string, PageTable>();
  private order: string[] = [];
  private max: number;

  constructor(max: number = 4) {
    this.max = max < 1 ? 1 : max;
  }

  get(key: string): PageTable | null {
    const hit: PageTable | undefined = this.tables.get(key);
    return hit === undefined ? null : hit;
  }

  put(key: string, table: PageTable): void {
    if (!this.tables.has(key)) {
      this.order.push(key);
      while (this.order.length > this.max) {
        const oldest: string | undefined = this.order.shift();
        if (oldest !== undefined) {
          this.tables.delete(oldest);
        }
      }
    }
    this.tables.set(key, table);
  }

  clear(): void {
    this.tables.clear();
    this.order = [];
  }
}

/**
 * 假实现：按**固定字数**切页。仅供 CI 单测使用（真机上不用）。
 * 与真实实现的差别只有"行怎么断"，页表结构与翻页逻辑完全一致。
 */
export class FakePaginator implements Paginator {
  private charsPerPage: number;

  constructor(charsPerPage: number = 500) {
    this.charsPerPage = charsPerPage < 1 ? 1 : charsPerPage;
  }

  paginate(content: string, box: LayoutBox): PageTable {
    const pages: PageRange[] = [];
    let start: number = 0;
    while (start < content.length) {
      const end: number = Math.min(start + this.charsPerPage, content.length);
      const range: PageRange = { start: start, end: end };
      pages.push(range);
      start = end;
    }
    if (pages.length === 0) {
      const empty: PageRange = { start: 0, end: 0 };
      pages.push(empty);
    }
    return {
      signature: box.signature,
      pages: pages,
      totalChars: content.length,
      linesPerPage: 0
    };
  }
}
