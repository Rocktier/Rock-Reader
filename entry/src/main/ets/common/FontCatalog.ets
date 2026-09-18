/**
 * 可下载字体目录（**内置字体 = 0，全部按需下载**）
 *
 * 党哥 2026-09-18 决定：**避免增加软件体积** → 字体走下载。
 * 由此带来的三条硬约束（改动本文件时务必保住）：
 *
 *  1. **只列开源可再分发的字体**（OFL），且**不修改字体文件**（原样托管），
 *     这样无需按 OFL 的 Reserved Font Name 规则改名，也不必处理衍生作品的授权。
 *  2. **下载后必须校验 SHA256** 才能注册 —— 字体文件来自网络，这是唯一的完整性防线；
 *     校验失败就删掉重下，绝不能拿一个半截文件去注册（会渲染出错乱字形）。
 *  3. **下载失败 / 无网络时静默**：不弹错、不拦路，字体区只是少一项，阅读不受任何影响。
 *
 * 托管：本仓库自己的 Release 资产（`fonts-v1`）—— 不依赖上游链接的稳定性，
 * 且将来换成更小的子集包时**文件名与 URL 不变**。
 */
export interface FontEntry {
  /** 稳定 id（存偏好用） */
  id: string;
  /** 界面上显示的名字 */
  displayName: string;
  /** 注册进系统的字体族名（渲染 + 测量共用同一个名字） */
  familyName: string;
  /** 沙箱内的文件名 */
  fileName: string;
  /** 体积（字节）：下载前要明示给用户 */
  sizeBytes: number;
  /** SHA256：下载完必须比对 */
  sha256: string;
  /** 一句话描述（界面副标题） */
  desc: string;
  /** 授权声明 */
  license: string;
}

const RELEASE_BASE: string = 'https://github.com/Rocktier/Rock-Reader/releases/download/fonts-v1/';

/** 目录：加一款字体 = 加一条记录（其余逻辑不用改） */
export const FONT_CATALOG: FontEntry[] = [
  {
    id: 'lxgw-wenkai-lite',
    displayName: '霞鹜文楷 Lite',
    familyName: 'LXGW WenKai Lite',
    fileName: 'LXGWWenKaiLite-Regular.ttf',
    sizeBytes: 13926340,
    sha256: 'e560b1cda5167a1c8a6dc784b079732601bd47e6c11b602f5a4cedb36cd8ba20',
    desc: '楷体风格 · 中文长文阅读口碑最好之一 · 已含 GB2312 全部汉字',
    license: 'SIL OFL 1.1'
  },
  {
    id: 'noto-serif-sc',
    displayName: '思源宋体 SC',
    familyName: 'Noto Serif SC',
    fileName: 'NotoSerifSC-VF.ttf',
    sizeBytes: 25125512,
    sha256: '050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9',
    desc: '衬线（宋体）· 最经典的中文正文字体 · 可变字重',
    license: 'SIL OFL 1.1'
  }
];

export function fontUrlOf(entry: FontEntry): string {
  return RELEASE_BASE + entry.fileName;
}

export function sizeTextOf(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
  return Math.round(bytes / 1024) + ' KB';
}

export function findFont(id: string): FontEntry | null {
  for (let i: number = 0; i < FONT_CATALOG.length; i++) {
    if (FONT_CATALOG[i].id === id) {
      return FONT_CATALOG[i];
    }
  }
  return null;
}
