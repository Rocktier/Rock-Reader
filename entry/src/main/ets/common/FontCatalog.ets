/**
 * 可下载字体目录（**内置字体 = 0，全部按需下载**）
 *
 * 党哥 2026-09-18 定的三条：① 用开源字体 ② 国内下载要快 ③ 尽量官方源。
 * 由此定下的做法（改本文件时务必保住）：
 *
 *  1. **只列 SIL OFL 等开源授权的字体**；
 *  2. **做成 GB2312 子集（6763 字）**——原字体 13.3MB / 24MB 在国内网络下一次下载太慢，
 *     子集后 **楷 3.27MB / 宋 2.91MB**，日常书与绝大多数人名都够用，
 *     极罕见的字回退系统字体（只影响那一两个字的字型，不影响阅读）；
 *  3. **按 OFL 的 Reserved Font Name 规则改名**（子集属"修改"，不得沿用原名），
 *     归属声明写在字体文件内部的 copyright 字段里（可审计，见 fonts 分支的 NOTICE.md）；
 *  4. **多源下载 + 每个源都校验 SHA256** —— 首选 jsDelivr CDN（国内可达的官方 CDN），
 *     GitHub Release 与 raw 兜底。任一源被替换/损坏都会被拒绝启用。
 */
export interface FontEntry {
  /** 稳定 id（存偏好用） */
  id: string;
  /** 界面上显示的名字 */
  displayName: string;
  /** 注册进系统的字体族名（渲染 + 测量共用同一个名字） */
  familyName: string;
  /** 沙箱内的文件名（与托管分支里的文件名一致） */
  fileName: string;
  /** 体积（字节）：下载前要明示给用户 */
  sizeBytes: number;
  /** SHA256：下载完必须比对（**与从哪个源下载无关**） */
  sha256: string;
  /** 一句话描述（界面副标题） */
  desc: string;
  /** 授权声明 */
  license: string;
  /**
   * 是否**内置在安装包里**（rawfile）：
   * true  = 首次启动从包内复制到沙箱，**不联网**即可用（代价是 HAP 变大）；
   * false = 按需下载（不占包体，但要联网一次）。
   * 党哥 2026-09-25 定：楷体内置（换字体也不必联网 → 可彻底去掉 INTERNET 权限）。
   */
  builtin: boolean;
}

const JSDelivrBase: string = 'https://cdn.jsdelivr.net/gh/Rocktier/Rock-Reader@fonts-v1/fonts/';
const ReleaseBase: string = 'https://github.com/Rocktier/Rock-Reader/releases/download/fonts-v1/';
const RawBase: string = 'https://raw.githubusercontent.com/Rocktier/Rock-Reader/fonts-v1/fonts/';

/** 下载源顺序：CDN（国内可达）→ Release 附件 → raw。加一款字体 = 加一条记录。 */
export const FONT_CATALOG: FontEntry[] = [
  {
    id: 'rockreader-kai',
    displayName: '楷体 RockReader Kai',
    familyName: 'RockReader Kai',
    fileName: 'RockReaderKai.ttf',
    sizeBytes: 3427912,
    sha256: '701bc84dcf0df09c5716108edeac61c11109ddbad81769777d29de3735e5ecc7',
    desc: '基于霞鹜文楷 Lite 的 GB2312 子集 · 中文长文阅读口碑最好之一',
    license: 'SIL OFL 1.1',
    // 内置：换字体也不需要联网（HAP +2.02MB，实测 zip 后）
    builtin: true
  },
  {
    id: 'rockreader-song',
    displayName: '宋体 RockReader Song',
    familyName: 'RockReader Song',
    fileName: 'RockReaderSong.ttf',
    sizeBytes: 3051864,
    sha256: '03afa46899bbc3bff6329e5680b85acd0f270f02b75c31997c843f3702eceafb',
    desc: '基于 Noto Serif SC（思源宋体同源）的 GB2312 子集 · 最经典的中文正文字体',
    license: 'SIL OFL 1.1',
    builtin: false
  }
];

/** 按顺序尝试的下载源；调用方逐个试，任一成功即止 */
export function fontUrlsOf(entry: FontEntry): string[] {
  return [
    JSDelivrBase + entry.fileName,
    ReleaseBase + entry.fileName,
    RawBase + entry.fileName
  ];
}

export function sizeTextOf(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
  return Math.round(bytes / 1024) + ' KB';
}
