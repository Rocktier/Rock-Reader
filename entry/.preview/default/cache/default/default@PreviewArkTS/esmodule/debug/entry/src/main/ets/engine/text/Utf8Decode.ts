/**
 * 纯 TS 的 UTF-8 解码（**零依赖 → CI 可单测**）
 *
 * 为什么不直接用 util.TextDecoder：
 *   ① 它是设备/Node 各自实现，行为边界（非法序列怎么处理）不可控；
 *   ② 引擎层要保持"纯 TS"，才能进 taskpool、才能在 CI 里跑。
 * 非法序列一律输出 U+FFFD（与 WHATWG 一致），**绝不抛错** —— 阅读器不能因为一个坏字节就整章读不出来。
 *
 * ponytail: 逐字符拼接（不做 chunk + fromCharCode.apply）—— 原因：ArkTS 对 Function.apply 有限制，
 *   而字符串拼接在现代引擎里是 rope 结构，几十 KB 量级足够快。
 */
export function decodeUtf8(bytes: Uint8Array, from: number = 0): string {
    let out: string = '';
    let i: number = from;
    const total: number = bytes.length;
    while (i < total) {
        const b0: number = bytes[i];
        if (b0 < 0x80) {
            out += String.fromCharCode(b0);
            i += 1;
            continue;
        }
        let cp: number = 0;
        let need: number = 0;
        if (b0 >= 0xC2 && b0 <= 0xDF) {
            cp = b0 & 0x1F;
            need = 1;
        }
        else if (b0 >= 0xE0 && b0 <= 0xEF) {
            cp = b0 & 0x0F;
            need = 2;
        }
        else if (b0 >= 0xF0 && b0 <= 0xF4) {
            cp = b0 & 0x07;
            need = 3;
        }
        else {
            out += String.fromCharCode(0xFFFD);
            i += 1;
            continue;
        }
        if (i + need >= total) {
            out += String.fromCharCode(0xFFFD);
            break;
        }
        let ok: boolean = true;
        for (let k: number = 1; k <= need; k++) {
            const bk: number = bytes[i + k];
            if ((bk & 0xC0) !== 0x80) {
                ok = false;
                break;
            }
            cp = (cp << 6) | (bk & 0x3F);
        }
        if (!ok) {
            out += String.fromCharCode(0xFFFD);
            i += 1;
            continue;
        }
        i += need + 1;
        if (cp > 0xFFFF) {
            const v: number = cp - 0x10000;
            out += String.fromCharCode(0xD800 + (v >> 10));
            out += String.fromCharCode(0xDC00 + (v & 0x3FF));
        }
        else {
            out += String.fromCharCode(cp);
        }
    }
    return out;
}
/** 剥掉 UTF-8 BOM（EPUB 的 XML 文件常带） */
export function bomLengthOf(bytes: Uint8Array): number {
    if (bytes.length >= 3 && bytes[0] === 0xEF && bytes[1] === 0xBB && bytes[2] === 0xBF) {
        return 3;
    }
    return 0;
}
