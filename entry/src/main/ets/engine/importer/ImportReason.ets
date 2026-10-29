/**
 * 导入结果 → 给用户看的一句话（返回空串 = 不用打扰用户）。
 *
 * 抽成**不碰 fileIo / UI 的纯逻辑**，是为了能进 CI 单测 —— 这里踩过一个很隐蔽的坑：
 *
 *   `default` 原来返回「导入失败」，而**多选全部成功**时 reason 恰好是空串，
 *   于是"成功"走进了 default → **书都进书架了，界面却弹一句"导入失败"**。
 *   用户 2026-09-23 报的就是这个（"明明已经导入成功了，却显示导入失败"）。
 *
 * 结论：**未知 reason 一律不弹** —— 多说一句错话，比什么都不说更糟。
 * 另外，**成功不需要任何提示**：书出现在书架上本身就是最好的反馈。
 */

/** 空串表示"不需要提示" */
export function reasonText(reason: string): string {
  switch (reason) {
    case 'CANCELLED':
      // 用户自己取消的，不要打扰
      return '';
    case 'NOT_SUPPORTED':
      // 文案跟着实际支持的格式走（P1-9 诚实度整改，2026-10-22）：
      // 早先写成「TXT/EPUB/HTML/MD/FB2/MOBI/AZW3 可以」，但 MOBI/AZW3 实际只支持
      // PalmDOC/无压缩 —— HUFF/CDIC 压缩（新版 MOBI 很常见）解析时直接抛异常，
      // 用户拿着解不开的 MOBI 来，文案却说 MOBI 可以，等于把人往坑里带。
      // 「部分支持」不进宣传清单：能吃进去是惊喜，吃不进去不欠解释。
      return '这个格式不支持（TXT/EPUB/HTML/MD/FB2 可以）';
    case 'TOO_LARGE':
      return '文件太大';
    case 'EMPTY':
      return '文件是空的';
    case 'COPY_FAILED':
      return '读取文件失败';
    case 'PARSE_FAILED':
      // 只指 book 非空的场景（书已入库但章节目录没解出来），文案与事实一致
      return '已导入，但目录解析失败';
    case 'PARSE_CRASHED':
      // 解析过程抛了异常、书**没有**进书架（book: null）。旧的 catch 兜底共用
      // PARSE_FAILED，用户会看到「已导入」却找不到书 —— 说的和事实相反。
      return '这本书读取失败（文件可能损坏或格式较新）';
    case 'MOBI_TOO_NEW':
      // MobiParser 抛 MOBI_UNSUPPORTED_COMPRESSION（HUFF/CDIC，新版 MOBI 常见）：
      // 说清是"格式较新"而不是"文件坏了"，也不承诺 MOBI 整体支持（见 NOT_SUPPORTED）
      return '这本 MOBI 用了较新的压缩方式，暂时打不开（旧版 MOBI 可以）';
    case 'MOBI_ENCODING':
      // MobiParser 抛 MOBI_UNSUPPORTED_ENCODING（未知 code page，或设备 TextDecoder
      // 没有对应的多字节解码表）：明确说"读不出文字"，而不是含糊的"目录解析失败"
      return '这本 MOBI 的正文编码读不出来（可尝试转成 UTF-8 的 TXT/EPUB）';
    default:
      // ⚠️ 成功时 reason 就是空串，会落到这里。这里必须是"不弹"：
      // 返回任何失败文案，都会造成"导入成功却报失败"。
      return '';
  }
}
