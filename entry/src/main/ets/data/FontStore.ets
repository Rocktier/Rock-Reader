/**
 * 字体下载与本地管理
 *
 * 2026-09-25 起：**1 款内置（宋体）+ 其余按需下载**。
 * 内置的那一款首次启动从包内（rawfile）复制到沙箱，之后与下载款走完全相同的路径。
 *
 * 三条硬规则（改这个文件时必须保住）：
 *  1. **先写 .part 再 rename** —— 任何中断都不会留下"看起来已下载"的半截文件；
 *  2. **下载完必须校验字节数 + SHA256** 才算成功，否则删掉重来；
 *     拿一个半截/损坏的字体去注册，会渲染出错乱字形，且极难定位；
 *  3. **失败一律静默**：无网络 / 超时 / 校验不过都只返回 false，由界面显示状态，
 *     绝不弹错打断阅读（也绝不因此让应用不可用）。
 *
 * 联网用途：仅"用户主动下载字体包"。已在家族 `findings.md` §8（网络权限申请记录）登记。
 */
import { http } from '@kit.NetworkKit';
import { fileIo as fs, hash } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FONT_CATALOG, FontEntry, fontUrlsOf } from '../common/FontCatalog';

const DOMAIN: number = 0x0000;
const TAG: string = 'RockReader';

const FONTS_DIR: string = 'fonts';

export class FontStore {
  private ctx: Context;

  constructor(ctx: Context) {
    this.ctx = ctx;
  }

  private dir(): string {
    return `${this.ctx.filesDir}/${FONTS_DIR}`;
  }

  pathOf(entry: FontEntry): string {
    return `${this.dir()}/${entry.fileName}`;
  }

  /**
   * 字体的 `file://` uri —— **只给 registerFont / loadFontSync 用**。
   *
   * 为什么必须带前缀：SDK 里两处白纸黑字 ——
   *   - `@ohos.graphics.text.d.ts`（loadFontSync）："path **must** be in the format of
   *     **file:// + Absolute path**"
   *   - `@ohos.font.d.ts`（registerFont.familySrc）：sandbox 目录 **advised to use a
   *     string with the file:// path prefix**
   * 传裸路径**不报错但静默失败**（2026-09-22 实测：字体切换后正文毫无变化，就是它）。
   * `fs.*` 系列**仍然要用 pathOf 的裸路径** —— 别把 uri 传给 fs。
   */
  uriOf(entry: FontEntry): string {
    return 'file://' + this.pathOf(entry);
  }

  /** 是否已下载（只看本地文件，不联网） */
  isDownloaded(entry: FontEntry): boolean {
    return fs.accessSync(this.pathOf(entry));
  }

  /**
   * **内置字体就位**：把包内（rawfile）的字体复制到沙箱。幂等，可放心反复调用。
   *
   * 为什么不直接拿 rawfile 路径去注册：
   *  - `registerFont` / `loadFontSync` 要的是 **file:// + 沙箱绝对路径**（裸路径静默失败，见 uriOf），
   *    rawfile 里没有能直接给它们用的路径；
   *  - 复制到沙箱后，**注册端与测量端（TextPaginator.loadFontSync）沿用现有逻辑，一行都不用改** ——
   *    内置款和下载款从此是同一条路，没有第二套代码。
   *
   * 不校验 SHA256：字体来自自己的 HAP（有签名保障），不是网络；校验反而拖慢启动。
   * 仍然先写 `.part` 再 rename —— 复制到一半被打断也不会留下"看起来已就绪"的半截文件。
   */
  syncBuiltin(): void {
    for (let i: number = 0; i < FONT_CATALOG.length; i++) {
      const entry: FontEntry = FONT_CATALOG[i];
      if (!entry.builtin) {
        continue;
      }
      const finalPath: string = this.pathOf(entry);
      if (fs.accessSync(finalPath)) {
        continue;
      }
      const tmpPath: string = finalPath + '.part';
      try {
        if (!fs.accessSync(this.dir())) {
          fs.mkdirSync(this.dir(), true);
        }
        if (fs.accessSync(tmpPath)) {
          fs.unlinkSync(tmpPath);
        }
        const bytes: Uint8Array = this.ctx.resourceManager.getRawFileContentSync('fonts/' + entry.fileName);
        const file: fs.File = fs.openSync(tmpPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
        try {
          fs.writeSync(file.fd, bytes.buffer);
        } finally {
          fs.closeSync(file);
        }
        if (fs.accessSync(finalPath)) {
          fs.unlinkSync(finalPath);
        }
        fs.renameSync(tmpPath, finalPath);
        hilog.info(DOMAIN, TAG, 'builtin font ready: %{public}s', entry.fileName);
      } catch (e) {
        // 失败静默：内置字体拿不到 ≠ 应用不可用，最多是没有这一款可选
        hilog.error(DOMAIN, TAG, 'syncBuiltin failed: %{public}s', JSON.stringify(e));
        try {
          if (fs.accessSync(tmpPath)) {
            fs.unlinkSync(tmpPath);
          }
        } catch (inner) {
          hilog.warn(DOMAIN, TAG, 'cleanup failed');
        }
      }
    }
  }

  /** 已下载的字体清单 */
  downloaded(): FontEntry[] {
    const out: FontEntry[] = [];
    for (let i: number = 0; i < FONT_CATALOG.length; i++) {
      if (this.isDownloaded(FONT_CATALOG[i])) {
        out.push(FONT_CATALOG[i]);
      }
    }
    return out;
  }

  /**
   * 字体族 → 沙箱路径；系统字体 / 未下载都返回 ''。
   * 排版测量要用这个路径把字体挂进 FontCollection（保证测量与渲染同一个文件）。
   */
  /** 按族名取字体的 `file://` uri（给**测量端 loadFontSync** 用；裸路径会静默失败，见 uriOf） */
  uriForFamily(family: string): string {
    if (family.length === 0) {
      return '';
    }
    for (let i: number = 0; i < FONT_CATALOG.length; i++) {
      const entry: FontEntry = FONT_CATALOG[i];
      if (entry.familyName === family && fs.accessSync(this.pathOf(entry))) {
        return this.uriOf(entry);
      }
    }
    return '';
  }

  /**
   * 下载并落盘（含校验）。成功返回 true。
   * **逐个尝试多个源**（CDN → Release → raw），任一成功即止；每个源都要过同一套校验。
   * 只做"下载 + 校验"，**不注册**（注册需要 UIContext，由页面在启动时统一做）。
   */
  async download(entry: FontEntry): Promise<boolean> {
    const urls: string[] = fontUrlsOf(entry);
    for (let i: number = 0; i < urls.length; i++) {
      const ok: boolean = await this.tryDownload(entry, urls[i]);
      if (ok) {
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'font source failed, try next: %{public}s', urls[i]);
    }
    return false;
  }

  private async tryDownload(entry: FontEntry, url: string): Promise<boolean> {
    const finalPath: string = this.pathOf(entry);
    const tmpPath: string = finalPath + '.part';
    try {
      if (!fs.accessSync(this.dir())) {
        fs.mkdirSync(this.dir(), true);
      }
      if (fs.accessSync(tmpPath)) {
        fs.unlinkSync(tmpPath);
      }

      const request: http.HttpRequest = http.createHttp();
      let written: boolean = false;
      try {
        const response: http.HttpResponse = await request.request(url, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 15000,
          readTimeout: 180000
        });
        if (response.responseCode !== 200) {
          hilog.error(DOMAIN, TAG, 'font download http %{public}d', response.responseCode);
          return false;
        }
        const body: Object = response.result as Object;
        if (!(body instanceof ArrayBuffer)) {
          hilog.error(DOMAIN, TAG, 'font download: unexpected body type');
          return false;
        }
        this.writeBytes(tmpPath, body);
        written = true;
      } finally {
        request.destroy();
      }
      if (!written) {
        return false;
      }

      // ① 字节数
      const stat = fs.statSync(tmpPath);
      if (stat.size !== entry.sizeBytes) {
        hilog.error(DOMAIN, TAG, 'font size mismatch %{public}d vs %{public}d', stat.size, entry.sizeBytes);
        fs.unlinkSync(tmpPath);
        return false;
      }

      // ② SHA256（字体文件来自网络，这是唯一的完整性防线）
      const actual: string = await hash.hash(tmpPath, 'sha256');
      if (actual.toLowerCase() !== entry.sha256.toLowerCase()) {
        hilog.error(DOMAIN, TAG, 'font sha256 mismatch');
        fs.unlinkSync(tmpPath);
        return false;
      }

      // ③ 校验通过才正式"上位"（rename）
      if (fs.accessSync(finalPath)) {
        fs.unlinkSync(finalPath);
      }
      fs.renameSync(tmpPath, finalPath);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'font download failed: %{public}s', JSON.stringify(e));
      // 失败就清干净，不留 .part 占空间
      try {
        if (fs.accessSync(tmpPath)) {
          fs.unlinkSync(tmpPath);
        }
      } catch (inner) {
        hilog.warn(DOMAIN, TAG, 'cleanup failed');
      }
      return false;
    }
  }

  private writeBytes(path: string, bytes: ArrayBuffer): void {
    // 注：枚举是 OpenMode.TRUNC（不是 TRUNCATE）
    const file: fs.File = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, bytes);
    } finally {
      fs.closeSync(file);
    }
  }

  /** 移除已下载字体（用户主动释放空间） */
  remove(entry: FontEntry): void {
    const path: string = this.pathOf(entry);
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'remove font failed: %{public}s', JSON.stringify(e));
    }
  }
}
