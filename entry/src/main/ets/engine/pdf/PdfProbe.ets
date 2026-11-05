/**
 * 用系统 PDFKit 探一次文件：能不能打开、几页、有没有书名。
 *
 * **这个文件碰 @kit ⇒ 不能进 node 单测**（模拟器也没有 PDFKit，只有真机有）。
 * 因此这里只放"薄壳"：所有判断规则都在 `PdfPages.ets`（纯逻辑、已有单测）。
 *
 * ── 为什么导入时要单独探一次，而不是等打开阅读页再说 ──
 * 1. 加密的 PDF 能拷进沙箱、能出现在书架上，但**永远打不开**。
 *    用户点进去看到一片空白才知道"这本不行"，体验上等于我们的应用坏了。
 *    必须在导入那一刻就说清"这本有密码"。
 * 2. 坏文件（下到一半的 PDF、改了扩展名的 doc）同理。
 * 3. 探一次很便宜：`loadDocument` 是同步的，只解析文件头与交叉引用表，不做渲染。
 *
 * ⚠️ 探完必须 `releaseDocument()`。文档原话：重复 loadDocument 不支持，
 * 后续调用前必须先 release。不释放的话，阅读页再用 PdfController 打开同一路径会冲突。
 */
import { pdfService } from '@kit.PDFKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { pdfFailReason, pickPdfTitle } from './PdfPages';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** PDF 能力的 syscap（all2md 的 PdfExtract 用的是同一个） */
const PDF_SYSCAP: string = 'SystemCapability.OfficeService.PDFService.Core';

/**
 * 这台设备有没有 PDF 能力。
 *
 * ⚠️ 不能写 `pdfService !== undefined` —— ArkTS 禁止把命名空间当对象用
 * （`arkts-no-ns-as-obj`，编译期就拦）。只能问 syscap。
 *
 * ❗ 本地 x86 模拟器上这里返回 **false**（all2md 实测），所以模拟器里
 * 导入 PDF 会被拒成 `PDF_UNSUPPORTED`，而不是误报"文件损坏"——
 * 这个区分很重要：前者是"换个设备就能读"，后者会让人去重新下载文件。
 */
export function pdfSupported(): boolean {
  try {
    return canIUse(PDF_SYSCAP);
  } catch (e) {
    return false;
  }
}

/** 探测结果（ok=false 时 reason 非空，见 PdfPages.pdfFailReason） */
export interface PdfInfo {
  ok: boolean;
  /** '' | PDF_ENCRYPTED | PDF_BROKEN */
  reason: string;
  /** 总页数（ok=false 时为 0） */
  pageCount: number;
  /** 元数据里的书名（已按规则过滤，可能为空串） */
  metaTitle: string;
  author: string;
}

function emptyInfo(reason: string): PdfInfo {
  const info: PdfInfo = { ok: false, reason: reason, pageCount: 0, metaTitle: '', author: '' };
  return info;
}

/**
 * 探一本 PDF。**不抛异常**：任何异常都折成 `PDF_BROKEN`，让导入流程永远能继续。
 */
export function probePdf(path: string): PdfInfo {
  // 设备没有 PDF 能力 ⇒ 不要 new PdfDocument（会抛），直接给准话
  if (!pdfSupported()) {
    hilog.warn(DOMAIN, TAG, 'pdf unsupported on this device, syscap absent');
    return emptyInfo('PDF_UNSUPPORTED');
  }
  const doc: pdfService.PdfDocument = new pdfService.PdfDocument();
  let loaded: boolean = false;
  try {
    // 不给密码：加密文档会直接返回 PARSE_ERROR_PASSWORD（枚举值 3）
    const r: pdfService.ParseResult = doc.loadDocument(path);
    const reason: string = pdfFailReason(r as number);
    if (reason.length > 0) {
      hilog.warn(DOMAIN, TAG, 'pdf probe failed: path=%{public}s result=%{public}d', path, r as number);
      return emptyInfo(reason);
    }
    loaded = true;

    const count: number = doc.getPageCount();
    if (!Number.isInteger(count) || count <= 0) {
      // 解析成功但 0 页 —— 结构损坏的 PDF 会这样。当坏文件处理，别让书架多一本点不开的书。
      return emptyInfo('PDF_BROKEN');
    }

    // 元数据可能抛（部分 PDF 的 info 字典编码不合规），抛了也不影响能读 —— 只是没书名
    let title: string = '';
    let author: string = '';
    try {
      const meta: pdfService.Metadata = doc.getMetadata();
      title = meta === null || meta === undefined ? '' : meta.title;
      author = meta === null || meta === undefined ? '' : meta.author;
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'pdf metadata unreadable, fallback to filename');
    }

    const info: PdfInfo = {
      ok: true,
      reason: '',
      pageCount: count,
      metaTitle: typeof title === 'string' ? title : '',
      author: typeof author === 'string' ? author : ''
    };
    return info;
  } catch (e) {
    // loadDocument 在某些损坏文件上会直接抛（不是返回错误码）
    hilog.error(DOMAIN, TAG, 'pdf probe threw: %{public}s', JSON.stringify(e));
    return emptyInfo('PDF_BROKEN');
  } finally {
    if (loaded) {
      try {
        doc.releaseDocument();
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'pdf releaseDocument failed (ignored)');
      }
    }
  }
}

/** 书名：元数据可用就用元数据，否则文件名（规则在纯逻辑层，已单测） */
export function pdfBookTitle(info: PdfInfo, fileNameTitle: string): string {
  return pickPdfTitle(info.metaTitle, fileNameTitle);
}
