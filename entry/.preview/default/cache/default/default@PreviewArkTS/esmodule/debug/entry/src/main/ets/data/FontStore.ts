import http from "@ohos:net.http";
import fs from "@ohos:file.fs";
import hash from "@ohos:file.hash";
import hilog from "@ohos:hilog";
import { FONT_CATALOG, fontUrlsOf } from "@bundle:com.rocktier.rockreader/entry/ets/common/FontCatalog";
import type { FontEntry } from "@bundle:com.rocktier.rockreader/entry/ets/common/FontCatalog";
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
    /** 是否已下载（只看本地文件，不联网） */
    isDownloaded(entry: FontEntry): boolean {
        return fs.accessSync(this.pathOf(entry));
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
    pathForFamily(family: string): string {
        if (family.length === 0) {
            return '';
        }
        for (let i: number = 0; i < FONT_CATALOG.length; i++) {
            const entry: FontEntry = FONT_CATALOG[i];
            if (entry.familyName === family && fs.accessSync(this.pathOf(entry))) {
                return this.pathOf(entry);
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
            }
            finally {
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
        }
        catch (e) {
            hilog.error(DOMAIN, TAG, 'font download failed: %{public}s', JSON.stringify(e));
            // 失败就清干净，不留 .part 占空间
            try {
                if (fs.accessSync(tmpPath)) {
                    fs.unlinkSync(tmpPath);
                }
            }
            catch (inner) {
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
        }
        finally {
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
        }
        catch (e) {
            hilog.warn(DOMAIN, TAG, 'remove font failed: %{public}s', JSON.stringify(e));
        }
    }
}
