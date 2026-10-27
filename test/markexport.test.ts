/**
 * 标记导出单测
 *
 * 纯逻辑（不 import 任何 @ohos），能在 Node 里跑 —— CI 没有模拟器，这是唯一
 * 能自动验证的手段。
 *
 * 防回归重点：
 * 1. **日期必须本地时区**。用 toISOString() 会把东八区 00–08 点这批用户写成
 *    「昨天」，这是家族踩过、且有 CI 守门的坑。
 * 2. 脏数据（OPF 缺作者、摘录为空、字段干脆是 undefined）不许让导出崩掉 ——
 *    这条链路通向系统分享面板，崩了用户只会看到什么都发生不了。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  buildMarksExport,
  exportDateText
} from '../entry/src/main/ets/engine/marks/MarkExport.ets';
import { BookmarkRow, HighlightRow } from '../entry/src/main/ets/common/Types.ets';

function hl(id: number, chapter: number, excerpt: string, note: string): HighlightRow {
  return {
    id: id,
    bookId: 'b1',
    chapterIndex: chapter,
    startChar: 0,
    endChar: 10,
    excerpt: excerpt,
    note: note,
    createdAt: 0
  };
}

function bm(id: number, chapter: number, excerpt: string): BookmarkRow {
  return {
    id: id,
    bookId: 'b1',
    chapterIndex: chapter,
    charOffset: 0,
    excerpt: excerpt,
    createdAt: 0
  };
}

test('exportDateText：本地时区，且结果与环境时区无关', () => {
  // 关键构造：本地墙上时间 2026-10-27 00:05。
  // 东八区下它对应的 UTC 是 10-26 —— 所以这个用例同时守住「不许用 toISOString()」：
  // 误写成 UTC 就会得到 10-26，用例立刻红。
  const d: Date = new Date(2026, 9, 27, 0, 5);
  assert.equal(exportDateText(d), '2026-10-27');
});

test('exportDateText：月与日补零到两位', () => {
  assert.equal(exportDateText(new Date(2026, 0, 5)), '2026-01-05');
  assert.equal(exportDateText(new Date(2026, 11, 31)), '2026-12-31');
});

test('buildMarksExport：一条标记都没有时要明说，不给空壳', () => {
  const out: string = buildMarksExport('三体', '刘慈欣', [], [], new Date(2026, 9, 27));
  assert.ok(out.indexOf('《三体》') >= 0);
  assert.ok(out.indexOf('刘慈欣') >= 0);
  assert.ok(out.indexOf('还没有任何标记') >= 0);
});

test('buildMarksExport：章序按人的习惯从 1 起算（库里存的是 0 基）', () => {
  const out: string = buildMarksExport('三体', '', [hl(1, 0, '不要回答', '')], [], new Date(2026, 9, 27));
  assert.ok(out.indexOf('第 1 章') >= 0, 'chapterIndex=0 必须显示成第 1 章');
  assert.ok(out.indexOf('「不要回答」') >= 0);
});

test('buildMarksExport：批注以 > 打头另起一行，与原文明示区分', () => {
  const out: string = buildMarksExport('三体', '', [hl(1, 3, '原文', '我的想法')], [], new Date(2026, 9, 27));
  assert.ok(out.indexOf('「原文」') >= 0);
  assert.ok(out.indexOf('> 我的想法') >= 0);
  assert.ok(out.indexOf('第 4 章') >= 0);
});

test('buildMarksExport：摘录在前、书签在后，各自报条数', () => {
  const out: string = buildMarksExport(
    '书',
    '',
    [hl(1, 0, '一段', ''), hl(2, 1, '两段', '')],
    [bm(1, 2, '停在这里')],
    new Date(2026, 9, 27)
  );
  assert.ok(out.indexOf('摘录（2 条）') >= 0);
  assert.ok(out.indexOf('书签（1 个）') >= 0);
  assert.ok(out.indexOf('摘录') < out.indexOf('书签'), '摘录节要在书签节之前');
});

test('buildMarksExport：脏数据（undefined 书名/作者/摘录）不许抛异常', () => {
  const out: string = buildMarksExport(
    undefined as unknown as string,
    undefined as unknown as string,
    [hl(1, 0, undefined as unknown as string, undefined as unknown as string)],
    [bm(1, 0, undefined as unknown as string)],
    new Date(2026, 9, 27)
  );
  assert.equal(typeof out, 'string');
  assert.ok(out.length > 0, '再脏也要吐得出一段字，不许是空串');
});

test('buildMarksExport：作者缺失时不留空行占位', () => {
  const out: string = buildMarksExport('三体', '', [hl(1, 0, '一段', '')], [], new Date(2026, 9, 27));
  const lines: string[] = out.split('\n');
  assert.equal(lines[0], '《三体》');
  assert.ok(lines[1].indexOf('导出自') >= 0, '作者为空时第二行应直接是导出说明');
});
