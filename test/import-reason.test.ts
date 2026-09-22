/**
 * 导入提示文案（engine/importer/ImportReason）—— 纯逻辑，可 CI 跑。
 *
 * 这个文件的存在意义就是守住那个"导入成功却报失败"的 bug：
 * 成功时 reason 是空串，一旦 default 返回失败文案，用户每次导入都会看到假失败。
 */
import { test } from 'node:test';
import assert from 'node:assert';
import { reasonText } from '../entry/src/main/ets/engine/importer/ImportReason.ets';

test('成功（空 reason）不弹任何提示 —— 书出现在书架本身就是反馈', () => {
  // 这是那条 bug 的守门测试：多选全部成功时 reason 就是空串
  assert.equal(reasonText(''), '', '空 reason 必须是空文案，否则"导入成功"会弹成"导入失败"');
});

test('未知 reason 不弹 —— 宁可不说，也不说错', () => {
  // 以后新增了 reason 却忘了加文案时，绝不能弹一句错的
  assert.equal(reasonText('SOMETHING_NEW'), '');
  assert.equal(reasonText('undefined'), '');
});

test('用户取消不打扰', () => {
  assert.equal(reasonText('CANCELLED'), '');
});

test('真失败必须有文案（不许静默失败）', () => {
  const reasons: string[] = ['EMPTY', 'TOO_LARGE', 'COPY_FAILED', 'PARSE_FAILED', 'NOT_SUPPORTED'];
  for (let i: number = 0; i < reasons.length; i++) {
    assert.ok(reasonText(reasons[i]).length > 0, reasons[i] + ' 必须有文案');
  }
});

test('格式不支持的文案要列清支持什么', () => {
  const t: string = reasonText('NOT_SUPPORTED');
  // 报"不支持"却不说支持什么，用户会以为自己的文件坏了（旧文案只写 TXT/EPUB，早已过时）
  const exts: string[] = ['TXT', 'EPUB', 'MOBI', 'AZW3', 'FB2'];
  for (let i: number = 0; i < exts.length; i++) {
    assert.ok(t.indexOf(exts[i]) >= 0, '文案里应提到 ' + exts[i]);
  }
});
