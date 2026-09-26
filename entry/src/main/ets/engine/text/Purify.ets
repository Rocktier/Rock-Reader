/**
 * TXT 正文净化（去广告）
 *
 * 背景：国内网文 TXT 普遍夹带站点水印、公众号/QQ 群推广、网址、"本书首发xxx"等广告行。
 * 原版 Legado 的「替换净化」就是干这个的（GPL-3.0，我们只借鉴思路，代码自研）。
 *
 * 为什么是纯函数：**不 import 任何 @ohos**，可以在 Node 里用真实样本跑测试
 * （CI 无模拟器，这是唯一自动化验证手段）。
 *
 * 设计取舍：
 * - 规则分两种作用域：`line` = 命中即整行删除；`inline` = 只替换命中的那一小段。
 *   ⚠️ 这个区分是必需的：曾用 inline 规则去做整行判断，结果把「更多精彩请见 http… 谢谢」整行删了
 *   （单测 `删掉行内残留网址` 逮到的）。
 * - 只做删除与压缩，不改正文语义。
 * - 正误权衡：宁可漏删一条广告，也不许误删正文（见测试「不许误伤正文」）。
 */
export const SCOPE_LINE: string = 'line';
export const SCOPE_INLINE: string = 'inline';

export interface PurifyRule {
  name: string;
  /** 正则源码（不用 lookbehind，ArkTS/JS 通用） */
  pattern: string;
  /** 替换成什么（空串 = 删除） */
  replacement: string;
  /** line = 整行删除；inline = 行内替换 */
  scope: string;
  enabled: boolean;
}

function lineRule(name: string, pattern: string): PurifyRule {
  return { name: name, pattern: pattern, replacement: '', scope: SCOPE_LINE, enabled: true };
}

function inlineRule(name: string, pattern: string, replacement: string): PurifyRule {
  return { name: name, pattern: pattern, replacement: replacement, scope: SCOPE_INLINE, enabled: true };
}

/** 命中即整行删除（广告行几乎都占满一行） */
const LINE_RULES: PurifyRule[] = [
  lineRule('网址行', '^[\\s　]*https?://\\S*[\\s　]*$'),
  lineRule('www 域名行', '^[\\s　]*[wｗ]{3}\\.[^\\s　]+[\\s　]*$'),
  lineRule('站点水印【…】',
    '^[\\s　]*[【\\[][^】\\]]{0,40}(小说网|文学网|看书网|书城|笔趣|起点|纵横|免费|下载|更新|首发|整理|手打)[^】\\]]{0,40}[】\\]][\\s　]*$'),
  // 2026-09-26 审查报告 B4 收紧：旧规则把裸词（微信/抖音/快手/微博）放进行首集合，
  // 「微信还没有回过来。」「微博上有人认出他。」「快手炒了一盘菜。」这类正常句子整行被删。
  // 收紧原则：关键词必须是**复合词**（带"号/公众号"后缀，广告才会这么写），
  // 且后面只允许 ≤30 字符的联系方式直到行尾 —— 叙事句几乎不可能长这样。
  lineRule('公众号/群推广行',
    '^[\\s　]*[（(]?[\\s　]*(微信公众号|公众微信号|微信号|QQ群|QQ号|企鹅群|抖音号|快手号|小红书号|微博号|头条号)[:：，,]?[^\\n]{0,30}[\\s　]*$'),
  lineRule('本书首发/来自行', '^[\\s　]*[（(]?本书(首发|来自|由|收集)[^\\n]{0,60}[\\s　]*$'),
  lineRule('纯分隔符行', '^[\\s　]*[-—=*·、。]{6,}[\\s　]*$'),
  // 同 B4：「安装了软件，他才坐下来。」被旧规则误删 —— 用 [^了] 排除叙事过去式
  lineRule('APP 下载引导行',
    '^[\\s　]*[（(]?(下载|安装|搜索|戳|点击)[^了\\n]{0,12}(APP|App|app|客户端)[^\\n]{0,25}[\\s　]*$')
];

/** 行内残留清理（只删命中片段，绝不整行删） */
const INLINE_RULES: PurifyRule[] = [
  inlineRule('行内网址', 'https?://[^\\s　，。；！？）】]+', ''),
  inlineRule('行内 www', '[wｗ]{3}\\.[^\\s　，。；！？）】]+', ''),
  inlineRule('行尾空格', '[ \\t　]+$', '')
];

export function defaultPurifyRules(): PurifyRule[] {
  const out: PurifyRule[] = [];
  for (let i = 0; i < LINE_RULES.length; i++) {
    out.push(LINE_RULES[i]);
  }
  for (let i = 0; i < INLINE_RULES.length; i++) {
    out.push(INLINE_RULES[i]);
  }
  return out;
}

/** 该行是否被判定为广告行（只按 line 规则判断） */
function isAdLine(line: string, rules: PurifyRule[]): boolean {
  const trimmed: string = line.trim();
  if (trimmed.length === 0) {
    return false;
  }
  for (let i = 0; i < rules.length; i++) {
    const r: PurifyRule = rules[i];
    if (!r.enabled || r.scope !== SCOPE_LINE) {
      continue;
    }
    if (new RegExp(r.pattern).test(trimmed)) {
      return true;
    }
  }
  return false;
}

/**
 * 净化正文
 * @param text 原始章节正文
 * @param rules 规则集（传 defaultPurifyRules() 用默认规则；空数组 = 不净化）
 */
export function purifyText(text: string, rules: PurifyRule[]): string {
  if (text.length === 0 || rules.length === 0) {
    return text;
  }
  const lines: string[] = text.split('\n');
  const kept: string[] = [];
  for (let i = 0; i < lines.length; i++) {
    if (!isAdLine(lines[i], rules)) {
      kept.push(lines[i]);
    }
  }
  let out: string = kept.join('\n');
  // 行内残留清理（只作用于 inline 规则）
  for (let i = 0; i < rules.length; i++) {
    const r: PurifyRule = rules[i];
    if (!r.enabled || r.scope !== SCOPE_INLINE) {
      continue;
    }
    out = out.replace(new RegExp(r.pattern, 'gm'), r.replacement);
  }
  // 压缩连续空行：3 个以上换行 → 2 个
  out = out.replace(/\n{3,}/g, '\n\n');
  return out;
}
