/**
 * 字体目录（**全部内置，零联网**）
 *
 * 2026-11-12：删掉三个远端下载源与下载入口，
 * 以及"加回 INTERNET 权限即可复活楷体"的那段注释 —— 应用现在**没有任何联网代码**，
 * 与隐私政策「完全不出互联网」一致。
 *
 * 保留下来的工程决定（改本文件时务必保住）：
 *  1. 只列 SIL OFL 等开源授权字体（商业字库如方正/汉仪必须买授权，个人开发者别碰）；
 *  2. 做成 GB2312 子集（6763 字），日常书与绝大多数人名够用，极罕见字回退系统字体；
 *  3. 按 OFL 的 Reserved Font Name 规则改名，归属写在字体文件内部 copyright 字段里；
 *  4. 字体一律内置进 HAP，首次启动从 rawfile 复制到沙箱 —— 换字体不联网、断网可用。
 *
 * ⚠️ 若将来要恢复「按需下载」，不是取消注释就完事：需同时联动
 *    module.json5 权限、隐私政策四处副本、博客 756.html、AGC 隐私标签与商店文案。
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
  /** 体积（字节）：内置字体也要算进包体，别悄悄变大 */
  sizeBytes: number;
  /** 字体文件自身的 SHA256（内置件的完整性档案，不参与下载校验） */
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

/** 加一款字体 = 加一条记录；目前只有内置的宋体一款 */
export const FONT_CATALOG: FontEntry[] = [
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

export function sizeTextOf(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
  }
  return Math.round(bytes / 1024) + ' KB';
}
