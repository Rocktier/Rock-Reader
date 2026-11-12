/**
 * 内置字体的本地管理（零联网）
 *
 * 2026-11-12：删净字体下载通道（HTTP 下载调用 / CDN URL / 校验那一段）。
 * 权限早已去掉、下载 UI 也长期隐藏 —— 留着只会让静态扫描看到联网代码，
 * 与「隐私完全不出设备、不出互联网」的公开口径相撞。
 *
 * 现在只做两件事：把包内 rawfile 复制到沙箱、给出 `file://` uri 供渲染与测量共用。
 * 硬规则：先写 `.part` 再 rename —— 中断不会留下"看起来已就绪"的半截字体。
 *
 * ⚠️ 将来若要恢复下载字体：必须**四处联动**（module.json5 权限 / 本文件下载管线 /
 *    博客与应用内隐私正文 / AGC 隐私标签与商店文案），别在代码里偷跑。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FONT_CATALOG, FontEntry } from '../common/FontCatalog';

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
