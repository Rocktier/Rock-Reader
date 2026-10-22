/**
 * 字体目录（**1 款内置 + 其余按需下载**）
 *
 * 2026-09-25 起：首版"小而美"只内置 **宋体** 一款（2.91MB，HAP 增到约 3.7MB），
 * 换字体不必联网 → 可彻底去掉 INTERNET 权限。其余字体仍按需下载，
 * **后续版本会继续增加字体**（楷体就是第一个候选）。
 *
 * 党哥 2026-09-18 定的三条：① 用开源字体 ② 国内下载要快 ③ 尽量官方源。
 * 由此定下的做法（改本文件时务必保住）：
 *
 *  1. **只列 SIL OFL 等开源授权的字体**（商业字库如方正/汉仪必须买授权，个人开发者别碰）；
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
  // 楷体（霞鹜文楷 Lite 子集）**继续不收录**（2026-10-22 评审 P0-3 复核后的工程决策）：
  //
  // 评审曾把「下载管线完整、入口整段隐藏」记为断头路。复核结论：**保留隐藏**，
  // 但这次是有据的决策而不是遗忘 ——
  //   ① 托管源已验证存在（fonts-v1 tag，RockReaderKai.ttf 文件头 TTF magic 正确），
  //     技术上只差 module.json5 加回 INTERNET 权限即可用；
  //   ② 但加权限 = 一次上架叙事级变更：隐私政策要加回"何时联网"一节（756.html），
  //     AGC 隐私标签口径变化、商店文案同步 —— 四个门面文件联动；
  //   ③ 门面文件必须与真实版本同发（家族纪律：一份法律文件一个底稿），
  //     在代码大扫除里顺手加权限 = 代码与门面再度脱节（P1-5 批评的病根）。
  //
  // **触发条件**（下一个功能版本收录楷体时，按序做）：
  //   1. module.json5 加回 ohos.permission.INTERNET；
  //   2. 取消下方注释（SHA256 不变，托管文件已验证）；
  //   3. 756.html 隐私政策加回联网下载说明 + 应用内 Privacy.ets 同步（双写纪律）；
  //   4. AGC 隐私标签/商店文案同步；下载 UI 自动出现（Settings.ets hasDownloadable()），
  //     下载 UI 的既有义务不变：明示联网+体积、进度可见、失败可重试说人话、
  //     下载记录落盘（ReaderPrefs），失败不静默。
  // {
  //   id: 'rockreader-kai',
  //   displayName: '楷体 RockReader Kai',
  //   familyName: 'RockReader Kai',
  //   fileName: 'RockReaderKai.ttf',
  //   sizeBytes: 3427912,
  //   sha256: '701bc84dcf0df09c5716108edeac61c11109ddbad81769777d29de3735e5ecc7',
  //   desc: '基于霞鹜文楷 Lite 的 GB2312 子集 · 中文长文阅读口碑最好之一',
  //   license: 'SIL OFL 1.1',
  //   builtin: false
  // },
  {
    id: 'rockreader-song',
    displayName: '宋体 RockReader Song',
    familyName: 'RockReader Song',
    fileName: 'RockReaderSong.ttf',
    sizeBytes: 3051864,
    sha256: '03afa46899bbc3bff6329e5680b85acd0f270f02b75c31997c843f3702eceafb',
    desc: '基于 Noto Serif SC（思源宋体同源）的 GB2312 子集 · 最经典的中文正文字体',
    license: 'SIL OFL 1.1',
    // 内置（党哥 2026-09-25 定）：
    // ① 宋体是中文长文阅读最正统的选择，与微信读书等主流阅读 App 的默认观感一致；
    // ② 与系统默认（黑体类）差异明显 —— 用户切过去一眼能看出区别，内置才有意义；
    // ③ 比楷体小 0.36MB（2.91 vs 3.27），首版"小而美"优先
    builtin: true
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
