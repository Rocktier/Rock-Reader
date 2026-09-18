/**
 * 真实字节回归：fixture 是**真实编码**的文件（UTF-8 / GB18030 各一份，内容自写，无版权问题）。
 * 目的：编码探测与切章不能只在内存字符串上正确，必须在真实字节上正确。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { detectEncoding, isValidUtf8 } from '../entry/src/main/ets/engine/text/Encoding.ets';
import { splitChapters, utf8ByteLength } from '../entry/src/main/ets/engine/text/ChapterSplitter.ets';

function bytesOf(path: string): Uint8Array {
  return new Uint8Array(readFileSync(path));
}

test('真实 UTF-8 样本：探测为 utf-8，切出「前言 + 3 章」且标题正确', () => {
  const bytes = bytesOf('test/fixtures/sample-utf8.txt');
  assert.equal(detectEncoding(bytes).encoding, 'utf-8');

  const text = new TextDecoder('utf-8').decode(bytes);
  const chapters = splitChapters(text);
  // 样本开头是书名/作者（首个章标题之前的内容）→ 按设计单独成「前言」章，不丢字
  assert.equal(chapters.length, 4);
  assert.equal(chapters[0].title, '前言');
  assert.equal(chapters[1].title, '第一章 雨夜');
  assert.equal(chapters[2].title, '第二章 砾石');
  assert.equal(chapters[3].title, '第三章 潮汐');
});

test('真实 GB18030 样本：判为非 UTF-8 → gb18030，解码后中文不乱码且切章一致', () => {
  const bytes = bytesOf('test/fixtures/sample-gbk.txt');
  assert.equal(isValidUtf8(bytes), false);
  assert.equal(detectEncoding(bytes).encoding, 'gb18030');

  const text = new TextDecoder('gb18030').decode(bytes);
  assert.ok(text.includes('第一章 雨夜'), 'GB18030 解码后应能读出中文标题');
  const chapters = splitChapters(text);
  assert.equal(chapters.length, 4);
  assert.equal(chapters[1].title, '第一章 雨夜');
});

test('设计决策守卫：GBK 文件的「UTF-8 字节偏移」大于磁盘真实字节数', () => {
  // 正因为如此，TxtParser 取章用的是**字符偏移**（readChapterTextByChars），
  // 而不是 ChapterSplitter 给出的 startByte/endByte —— 否则 GBK 书会取错段落。
  const gbk = bytesOf('test/fixtures/sample-gbk.txt');
  const text = new TextDecoder('gb18030').decode(gbk);
  assert.ok(utf8ByteLength(text) > gbk.length, 'UTF-8 重编码长度应大于 GBK 原字节数');
});
