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
      // 文案跟着实际支持的格式走：早先只支持 TXT/EPUB 时写死了这句话，
      // 后来加了 HTML/MD/FB2/MOBI/AZW3 —— 报不支持却不说清支持什么，用户会以为文件坏了
      return '这个格式不支持（TXT/EPUB/HTML/MD/FB2/MOBI/AZW3 可以）';
    case 'TOO_LARGE':
      return '文件太大';
    case 'EMPTY':
      return '文件是空的';
    case 'COPY_FAILED':
      return '读取文件失败';
    case 'PARSE_FAILED':
      return '已导入，但目录解析失败';
    default:
      // ⚠️ 成功时 reason 就是空串，会落到这里。这里必须是"不弹"：
      // 返回任何失败文案，都会造成"导入成功却报失败"。
      return '';
  }
}
