import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  matchChapterTitle,
  splitChapters,
  utf8ByteLength
} from '../entry/src/main/ets/engine/text/ChapterSplitter.ets';

test('章标题识别：第X章 / 第X回 / 第X节 / 中文数字 / 阿拉伯数字 / 全角数字', () => {
  assert.equal(matchChapterTitle('第一章 雨夜'), '第一章 雨夜');
  assert.equal(matchChapterTitle('第12回 归途'), '第12回 归途');
  assert.equal(matchChapterTitle('第三节'), '第三节');
  assert.equal(matchChapterTitle('  第五章  \u3000砾石'), '第五章  \u3000砾石');
  assert.equal(matchChapterTitle('第一〇二章'), '第一〇二章');
  assert.equal(matchChapterTitle('第３章'), '第３章');
});

test('章标题识别：非标题行必须被拒绝（避免正文误命中）', () => {
  assert.equal(matchChapterTitle('他翻开第一百一十七页，停住。这是一行普通的正文，不应该被当成标题。'), null);
  assert.equal(matchChapterTitle('第一章' + '很长的副标题'.repeat(10)), null); // 超过 40 字上限
  assert.equal(matchChapterTitle(''), null);
});

test('切章：位置连续、无空洞、字节偏移与字符偏移一致', () => {
  const text = '第一章 雨夜\n内容一\n内容二\n第二章 砾石\n内容三\n';
  const chapters = splitChapters(text);
  assert.equal(chapters.length, 2);
  assert.equal(chapters[0].title, '第一章 雨夜');
  assert.equal(chapters[1].title, '第二章 砾石');
  assert.equal(chapters[0].startChar, 0);
  assert.equal(chapters[0].endChar, chapters[1].startChar);
  assert.equal(chapters[1].endChar, text.length);
  // 字节偏移口径与 utf8ByteLength 一致
  const firstChunk = text.substring(chapters[0].startChar, chapters[0].endChar);
  assert.equal(chapters[0].endByte - chapters[0].startByte, utf8ByteLength(firstChunk));
});

test('切章：首个标题之前的内容单独成「前言」章（不丢字）', () => {
  const text = '序言部分\n作者的话\n第一章 起点\n正文\n';
  const chapters = splitChapters(text);
  assert.equal(chapters.length, 2);
  assert.equal(chapters[0].title, '前言');
  assert.equal(chapters[0].startChar, 0);
  assert.equal(chapters[0].endChar, chapters[1].startChar); // 首尾相接，无空洞
  assert.equal(chapters[1].title, '第一章 起点');
  assert.equal(chapters[1].endChar, text.length);
});

test('兜底切章：完全没有标题时按字数硬切且不丢字', () => {
  const text = 'a'.repeat(7000);
  const chapters = splitChapters(text, 3000);
  assert.equal(chapters.length, 3);
  assert.equal(chapters[chapters.length - 1].endChar, text.length);
  assert.equal(chapters[0].startChar, 0);
});
