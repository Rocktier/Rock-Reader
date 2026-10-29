/**
 * P0-5 书架副标题 + 文件名署名探测单测（纯逻辑）
 * 核心方针：诚实 —— 认不出的作者绝不编造，用格式兜底；文件名只在高置信分隔才认领。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { authorFromFileName, shelfSubtitle } from '../entry/src/main/ets/engine/shelf/ShelfAuthor.ets';

test('shelfSubtitle：有作者用作者，标 isAuthor', () => {
  const r = shelfSubtitle('刘慈欣', 'epub');
  assert.equal(r.text, '刘慈欣');
  assert.equal(r.isAuthor, true);
  // 作者带首尾空白要 trim
  assert.equal(shelfSubtitle('  鲁迅 ', 'txt').text, '鲁迅');
});

test('shelfSubtitle：无作者用格式大写兜底，永不空白、不编造', () => {
  const r = shelfSubtitle('', 'epub');
  assert.equal(r.text, 'EPUB');
  assert.equal(r.isAuthor, false);
  assert.equal(shelfSubtitle('', 'txt').text, 'TXT');
  assert.equal(shelfSubtitle('', 'md').text, 'MD');
  // 格式也空 → 兜到"本地书籍"，绝不返回空串
  const r2 = shelfSubtitle('', '');
  assert.ok(r2.text.length > 0);
  assert.equal(r2.isAuthor, false);
});

test('shelfSubtitle：null/undefined 也不崩', () => {
  assert.equal(shelfSubtitle(null as unknown as string, null as unknown as string).text, '本地书籍');
});

test('authorFromFileName：《书名》作者 —— 认领', () => {
  assert.equal(authorFromFileName('《三体》刘慈欣.txt'), '刘慈欣');
  assert.equal(authorFromFileName('《活着》 余华.md'), '余华');
  assert.equal(authorFromFileName('《百年孤独》加西亚·马尔克斯.epub'), '加西亚·马尔克斯');
});

test('authorFromFileName：书名-作者 —— 取最后一段', () => {
  assert.equal(authorFromFileName('三体-刘慈欣.txt'), '刘慈欣');
  assert.equal(authorFromFileName('三体 - 刘慈欣.txt'), '刘慈欣');
  assert.equal(authorFromFileName('活着_余华.txt'), '余华');
  assert.equal(authorFromFileName('书名—作者.md'), '作者');
  assert.equal(authorFromFileName('书名–作者.md'), '作者');
  // 多段分隔只取最后一段，避免"上中下"全被吞
  assert.equal(authorFromFileName('大部头-卷一-作者.txt'), '作者');
});

test('authorFromFileName：没把握时返回空（宁缺毋滥）', () => {
  assert.equal(authorFromFileName('三体.txt'), '', '没有分隔符');
  assert.equal(authorFromFileName('三体 完全版 精装典藏纪念特别长名字版.txt'), '', '过长/描述性');
  assert.equal(authorFromFileName('《三体》特别特别特别特别特别特别长的描述性后缀.txt'), '', '尾段超 24 字');
  assert.equal(authorFromFileName(''), '');
  assert.equal(authorFromFileName(null as unknown as string), '');
  // 带"修订版/全x册"之类特征的段不认领为作者
  assert.equal(authorFromFileName('书名-修订版（第三版）.txt'), '');
});
