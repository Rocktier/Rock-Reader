/**
 * MOBI / AZW3 的**导入**处理（IO 部分；纯逻辑在 `../text/Mobi`）
 *
 * 流程：读文件 → 解析 PDB 记录表 → 解析 record 0（压缩/编码/元数据）→
 *       逐条正文记录：裁尾部附加数据 → PalmDOC 解压 → 拼成 HTML →
 *       转成类 Markdown 纯文本 → 切章 → **预切章落盘**。
 *
 * 落盘后与 TXT 完全同构，所以**阅读端复用 `TxtSource`，阅读页零改动**。
 *
 * ## 本版的边界（都写成明确的错误，而不是静默出空白）
 *
 * - **HUFF/CDIC(17480) 未实现** —— 需要霍夫曼表解码，实测两本样本都是 PalmDOC，
 *   等真遇到再补（compression 不认识时抛 `MOBI_UNSUPPORTED_COMPRESSION`）
 * - **有 DRM 的书读不了**（encryption != 0 时抛 `MOBI_DRM`）—— 这是法律与技术双重限制
 * - 目录：老 MOBI 没有 TOC 文件，靠 `<mbp:pagebreak/>` 分章；KF8 靠 `<h1>`。
 *   KF8 的 NCX(INDX) 本版不解析。
 */
import { readAllBytes, writeChapterFiles } from './TxtParser';
import { ChapterMeta } from '../text/ChapterSplitter';
import { htmlToMarkdownish, splitMarkdownChapters } from '../text/Markup';
import {
  COMPRESSION_PALMDOC,
  decompressPalmDoc,
  isSupportedCompression,
  MobiMeta,
  parsePdb,
  parseRecord0,
  stripTrailing,
  utf8Of
} from '../text/Mobi';
import { ChapterRow } from '../../common/Types';

export interface MobiResult {
  title: string;
  author: string;
  charCount: number;
  chapters: ChapterRow[];
}

/** PDB 头前 32 字节是数据库名（通常是书名），EXTH 没书名时用它兜底 */
function pdbName(bytes: Uint8Array): string {
  let end: number = 0;
  while (end < 32 && end < bytes.length && bytes[end] !== 0) {
    end += 1;
  }
  return utf8Of(bytes.subarray(0, end)).trim();
}

export function parseMobiSync(path: string): MobiResult {
  const bytes: Uint8Array = readAllBytes(path);
  const entries = parsePdb(bytes);
  if (entries.length < 2) {
    throw new Error('MOBI_BAD_PDB');
  }

  const head = entries[0];
  const rec0: Uint8Array = bytes.subarray(head.offset, head.offset + head.size);
  const meta: MobiMeta = parseRecord0(rec0);

  // 有 DRM 的读不了 —— 明确抛错，别让用户在书架里点出一本空白书
  if (meta.encryption !== 0) {
    throw new Error('MOBI_DRM');
  }
  if (!isSupportedCompression(meta.compression)) {
    // 17480 = HUFF/CDIC，本版未实现
    throw new Error('MOBI_UNSUPPORTED_COMPRESSION');
  }

  // 解压后总长有声明（textLength），多申请一点余量当输出缓冲
  const cap: number = meta.textLength > 0 ? meta.textLength + 8192 : 65536;
  const out: Uint8Array = new Uint8Array(cap);
  let wp: number = 0;

  const limit: number = Math.min(entries.length, meta.firstContent + meta.recordCount);
  for (let r: number = meta.firstContent; r < limit; r++) {
    const e = entries[r];
    if (e.offset + e.size > bytes.length) {
      break;
    }
    let chunk: Uint8Array = bytes.subarray(e.offset, e.offset + e.size);
    // **必须先裁尾部附加数据**（实测样本 extraDataFlags=0x3），否则解压会错位 → 文末乱码
    chunk = stripTrailing(chunk, meta.extraFlags);
    if (meta.compression === COMPRESSION_PALMDOC) {
      chunk = decompressPalmDoc(chunk);
    }
    for (let i: number = 0; i < chunk.length && wp < out.length; i++) {
      out[wp] = chunk[i];
      wp += 1;
    }
  }

  // 按声明长度截断：多出来的是重叠/填充残留（实测 MOBI 多 515 字节、AZW3 多 713 字节）
  const want: number = meta.textLength > 0 ? Math.min(wp, meta.textLength) : wp;
  const html: string = utf8Of(out.subarray(0, want));

  const text: string = htmlToMarkdownish(html);
  const metas: ChapterMeta[] = splitMarkdownChapters(text);
  const rows: ChapterRow[] = [];
  for (let i: number = 0; i < metas.length; i++) {
    rows.push({
      bookId: '',
      index: metas[i].index,
      title: metas[i].title,
      startChar: metas[i].startChar,
      endChar: metas[i].endChar,
      startByte: 0,
      endByte: 0,
      href: ''
    });
  }

  writeChapterFiles(path, text, rows);

  let title: string = meta.title;
  if (title.length === 0) {
    title = pdbName(bytes);
  }
  return { title: title, author: meta.author, charCount: text.length, chapters: rows };
}
