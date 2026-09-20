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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BookDb } from '../../data/BookDb';
import { BookRecord } from '../../common/Types';
import { parseTxtSync, MAX_TXT_BYTES, CHAPTER_DIR } from '../parser/TxtParser';
import { parseEpub, MAX_EPUB_BYTES } from '../parser/EpubParser';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

/** 单文件上限（与官方示例一致 300MB；但 TXT / EPUB 解析各有 100MB 上限） */
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

/**
 * 删除一本书在沙箱里的文件（书副本 + 预切章目录）。
 *
 * 只动这本书自己那个目录（`book.path` 的父目录）—— 用户的**原文件在沙箱外，永不触碰**。
 * 不抛错：文件删不掉不该拦住"从书架移除"这个用户意图（DB 里那行已经删了）。
 * 做成模块函数而不是类方法：它只要 `book.path`，不需要 `Context`，静态些更好调用。
 *
 * ⚠️ 此前这个清理**根本不存在**：删书只删了数据库行，沙箱里的书文件永久残留
 *    （台账却写着"删库与沙箱副本"）。加了预切章之后残留会翻倍，所以一并补上。
 */
export function removeBookFiles(book: BookRecord): void {
  const slash: number = book.path.lastIndexOf('/');
  if (slash <= 0) {
    return;
  }
  const dir: string = book.path.substring(0, slash);
  const chDir: string = `${dir}/${CHAPTER_DIR}`;
  // 顺序：章文件 → 书文件 → 已空的书目录（部分平台 rmdir 要求目录为空）
  try {
    if (fs.accessSync(chDir)) {
      const names: string[] = fs.listFileSync(chDir);
      for (let i: number = 0; i < names.length; i++) {
        fs.unlinkSync(`${chDir}/${names[i]}`);
      }
      fs.rmdirSync(chDir);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'remove chapter files failed: %{public}s', JSON.stringify(e));
  }
  try {
    if (fs.accessSync(book.path)) {
      fs.unlinkSync(book.path);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'remove book file failed: %{public}s', JSON.stringify(e));
  }
  try {
    if (fs.accessSync(dir)) {
      fs.rmdirSync(dir);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'remove book dir failed: %{public}s', JSON.stringify(e));
  }
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

  /** 文件名：优先从 uri 末段解码（uri 形如 file://docs/.../书名.epub） */
  private nameFromUri(uri: string): string {
    const slash: number = uri.lastIndexOf('/');
    if (slash < 0 || slash >= uri.length - 1) {
      return '';
    }
    let name: string = uri.substring(slash + 1);
    const query: number = name.indexOf('?');
    if (query >= 0) {
      name = name.substring(0, query);
    }
    try {
      return decodeURIComponent(name);
    } catch (e) {
      return name;
    }
  }

  /**
   * 从 picker 返回的 uri 导入。
   *
   * ⚠️ 关键实现细节（真机踩点）：**全程持有 fd**。
   * picker 授予的是"这次打开的那个 fd"的读权限，而 uri 背后的真实路径可能属于文件管理器的沙箱；
   * 「开 URI → 取 path → 关掉 → 按 path 重开」在真机上可能被拒（读不到文件）。
   * 这里开头 open 一次，拷贝与校验都在同一个 fd 上做完，最后才 close。
   */
  async importFromUri(uri: string): Promise<ImportResult> {
    let src: fs.File;
    try {
      src = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'open picked uri failed: %{public}s', JSON.stringify(e));
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    let srcName: string = this.nameFromUri(uri);
    if (fileExtension(srcName).length === 0 && src.path.length > 0) {
      // uri 里没有扩展名（少数来源）→ 退回真实路径的末段
      srcName = src.path.substring(src.path.lastIndexOf('/') + 1);
    }

    let srcSize: number = 0;
    try {
      const stat = fs.statSync(src.fd);
      srcSize = stat.size;
    } catch (e) {
      fs.closeSync(src);
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    const ext = fileExtension(srcName);
    const rejected: string = this.checkLimits(ext, srcSize);
    if (rejected.length > 0) {
      fs.closeSync(src);
      return { ok: false, reason: rejected, book: null };
    }

    const id = 'b_' + util.generateRandomUUID(true);
    const dir = `${this.ctx.filesDir}/${BOOKS_DIR}/${id}`;
    const dstPath = `${dir}/${srcName}`;

    let copied: boolean = false;
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      await fs.copyFile(src.fd, dstPath, 0);
      copied = true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'copy to sandbox failed: %{public}s', JSON.stringify(e));
    } finally {
      fs.closeSync(src);
    }
    if (!copied) {
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    // 校验拷贝完整：copyFile 成功但文件没落全（或读权限受限只拷了 0 字节）必须被识别出来，
    // 否则会出现"书架上有这本书、打开却读不出内容"的脏数据。
    try {
      const dstStat = fs.statSync(dstPath);
      if (dstStat.size !== srcSize) {
        hilog.error(DOMAIN, TAG, 'copy size mismatch: %{public}d vs %{public}d', dstStat.size, srcSize);
        return { ok: false, reason: 'COPY_FAILED', book: null };
      }
    } catch (e) {
      return { ok: false, reason: 'COPY_FAILED', book: null };
    }

    const now = Date.now();
    let book: BookRecord = {
      id: id,
      title: baseName(srcName),
      author: '',
      format: ext,
      path: dstPath,
      size: srcSize,
      addedAt: now,
      lastReadAt: now,
      groupName: '' // 新导入的书进「未分组」，由用户在书架里归组
    };

    if (ext === 'txt') {
      try {
        const parsed = parseTxtSync(dstPath);
        await this.db.addChapters(id, parsed.chapters);
      } catch (e) {
        // 解析失败也要把书留下（能打开但没目录），不丢用户文件
        hilog.error(DOMAIN, TAG, 'parse txt failed: %{public}s', JSON.stringify(e));
        await this.db.addBook(book);
        return { ok: false, reason: 'PARSE_FAILED', book: book };
      }
    } else {
      try {
        const parsed = parseEpub(dstPath);
        // 用 OPF 里的书名/作者（比文件名的可读性好得多）
        book = {
          id: id,
          title: parsed.title.length > 0 ? parsed.title : book.title,
          author: parsed.author,
          format: ext,
          path: dstPath,
          size: srcSize,
          addedAt: now,
          lastReadAt: now,
          groupName: ''
        };
        await this.db.addChapters(id, parsed.chapters);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'parse epub failed: %{public}s', JSON.stringify(e));
        await this.db.addBook(book);
        return { ok: false, reason: 'PARSE_FAILED', book: book };
      }
    }
    await this.db.addBook(book);
    return { ok: true, reason: '', book: book };
  }

  /** 空/过大/格式不支持都在这里判掉；返回 '' 表示通过 */
  private checkLimits(ext: string, size: number): string {
    if (size <= 0) {
      return 'EMPTY';
    }
    if (size > MAX_FILE_BYTES) {
      return 'TOO_LARGE';
    }
    if (ext !== 'txt' && ext !== 'epub') {
      return 'NOT_SUPPORTED';
    }
    if (ext === 'txt' && size > MAX_TXT_BYTES) {
      return 'TOO_LARGE';
    }
    if (ext === 'epub' && size > MAX_EPUB_BYTES) {
      return 'TOO_LARGE';
    }
    return '';
  }
}
