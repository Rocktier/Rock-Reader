/**
 * 导入本地书：系统文件选择器 → 拷进应用沙箱 → 建章节索引 → 落库
 *
 * 借鉴来源（均为可合法使用的许可证）：
 *   - fileIo 用法（openSync / copyFile(fd, dst) / statSync）：华为官方示例
 *     `HarmonyOS_Samples/readerkit_samplecode_arkts`（Apache-2.0）
 *   - 其余为本项目自写
 * 未借鉴：`waylau/harmonyos-tutorial`（仓库无 LICENSE = 保留所有权利，只能看 API 形态）
 */
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BookDb } from '../../data/BookDb';
import { BookRecord } from '../../common/Types';
import { parseTxtSync, MAX_TXT_BYTES } from '../parser/TxtParser';

/** 单文件上限（与官方示例一致 300MB；但 TXT 解析另有 100MB 上限） */
const MAX_FILE_BYTES: number = 300 * 1024 * 1024;

const BOOKS_DIR = 'books';

export interface ImportResult {
  ok: boolean;
  /** CANCELLED / NOT_SUPPORTED / TOO_LARGE / EMPTY / COPY_FAILED / PARSE_FAILED */
  reason: string;
  book: BookRecord | null;
}

function fileExtension(name: string): string {
  const i = name.lastIndexOf('.');
  return i >= 0 ? name.substring(i + 1).toLowerCase() : '';
}

function baseName(name: string): string {
  const i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}

export class BookImporter {
  private db: BookDb;
  private ctx: Context;

  constructor(db: BookDb, ctx: Context) {
    this.db = db;
    this.ctx = ctx;
  }

  /** 弹出系统文件选择器并导入；用户取消返回 ok=false/CANCELLED */
  async pickAndImport(): Promise<ImportResult> {
    const docPicker = new picker.DocumentViewPicker(this.ctx);
    const options = new picker.DocumentSelectOptions();
    options.maxSelectNumber = 1;
    options.fileSuffixFilters = ['.txt', '.epub'];
    let uris: string[] = [];
    try {
      uris = await docPicker.select(options);
    } catch (e) {
      return { ok: false, reason: 'CANCELLED', book: null };
    }
    if (uris.length === 0) {
      return { ok: false, reason: 'CANCELLED', book: null };
    }
    return await this.importFromUri(uris[0]);
  }

  /**
   * 从 picker 返回的 uri 导入。
   * 不直接 decodeURI 猜路径：先 openSync 拿到真实路径（并由系统授予临时读权限）。
   */
  async importFromUri(uri: string): Promise<ImportResult> {
    let srcPath = '';
    let srcSize = 0;
    let srcName = '';
    try {
      const srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      try {
        srcPath = srcFile.path;
        const stat = fs.statSync(srcFile.fd);
        srcSize = stat.size;
        srcName = srcPath.substring(srcPath.lastIndexOf('/') + 1);
      } finally {
        fs.closeSync(srcFile);
      }
    } catch (e) {
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    if (srcSize <= 0) {
      return { ok: false, reason: 'EMPTY', book: null };
    }
    if (srcSize > MAX_FILE_BYTES) {
      return { ok: false, reason: 'TOO_LARGE', book: null };
    }

    const ext = fileExtension(srcName);
    if (ext !== 'txt' && ext !== 'epub') {
      return { ok: false, reason: 'NOT_SUPPORTED', book: null };
    }
    if (ext === 'txt' && srcSize > MAX_TXT_BYTES) {
      return { ok: false, reason: 'TOO_LARGE', book: null };
    }

    // 拷进沙箱：filesDir/books/<id>/<原名>
    const id = 'b_' + util.generateRandomUUID(true);
    const dir = `${this.ctx.filesDir}/${BOOKS_DIR}/${id}`;
    const dstPath = `${dir}/${srcName}`;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      await this.copy(srcPath, dstPath);
    } catch (e) {
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    const now = Date.now();
    const book: BookRecord = {
      id: id,
      title: baseName(srcName),
      author: '',
      format: ext,
      path: dstPath,
      size: srcSize,
      addedAt: now,
      lastReadAt: now
    };

    if (ext === 'txt') {
      try {
        const parsed = parseTxtSync(dstPath);
        await this.db.addChapters(id, parsed.chapters);
      } catch (e) {
        // 解析失败也要把书留下（能打开但没目录），不丢用户文件
        await this.db.addBook(book);
        return { ok: false, reason: 'PARSE_FAILED', book: book };
      }
    }
    await this.db.addBook(book);
    return { ok: true, reason: '', book: book };
  }

  private async copy(srcPath: string, dstPath: string): Promise<void> {
    const src = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    try {
      await fs.copyFile(src.fd, dstPath, 0);
    } finally {
      fs.closeSync(src);
    }
  }
}
