/**
 * TXT 正文净化（去广告）单测
 * 原则：**宁可漏删广告，也不许误删正文** —— 下面的「不许误伤正文」是核心护栏。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { defaultPurifyRules, purifyText, PurifyRule } from '../entry/src/main/ets/engine/text/Purify.ets';

const RULES: PurifyRule[] = defaultPurifyRules();

test('净化：删掉网址行', () => {
  const src: string = '正文第一行\nhttps://www.example.com/book/123\n正文第二行';
  const got: string = purifyText(src, RULES);
  assert.equal(got.includes('example.com'), false);
  assert.equal(got.includes('正文第一行'), true);
  assert.equal(got.includes('正文第二行'), true);
});

test('净化：删掉【…小说网…】水印行', () => {
  const src: string = '正文\n【笔趣阁小说网 www.biquge.com 欢迎广大书友】\n继续正文';
  const got: string = purifyText(src, RULES);
  assert.equal(got.includes('笔趣阁'), false);
  assert.equal(got.includes('继续正文'), true);
});

test('净化：删掉公众号 / QQ 群推广行', () => {
  const src: string = '正文\n微信公众号：好好看书\nQQ群：123456789 欢迎加入\n正文继续';
  const got: string = purifyText(src, RULES);
  assert.equal(got.includes('微信公众号'), false);
  assert.equal(got.includes('123456789'), false);
  assert.equal(got.includes('正文继续'), true);
});

test('净化：删掉「本书首发/来自」行', () => {
  const src: string = '正文\n（本书首发来自起点中文网，请支持正版）\n后续';
  const got: string = purifyText(src, RULES);
  assert.equal(got.includes('起点中文网'), false);
  assert.equal(got.includes('后续'), true);
});

test('净化：删掉行内残留网址（不是整行时也不能留）', () => {
  const src: string = '更多精彩请见 https://a.com/x 谢谢';
  const got: string = purifyText(src, RULES);
  assert.equal(got.includes('https://'), false);
  assert.equal(got.includes('更多精彩'), true);
});

test('净化：压缩 3 个以上连续换行为 2 个', () => {
  const src: string = '段一\n\n\n\n\n段二';
  assert.equal(purifyText(src, RULES), '段一\n\n段二');
});

test('净化：规则为空 = 不改动原文', () => {
  const src: string = '第一行\n\n\n第三行';
  assert.equal(purifyText(src, []), src);
});

test('净化：规则全部 disabled 时也不改动', () => {
  const off: PurifyRule[] = defaultPurifyRules().map((r: PurifyRule) => {
    const copy: PurifyRule = {
      name: r.name,
      pattern: r.pattern,
      replacement: r.replacement,
      scope: r.scope,
      enabled: false
    };
    return copy;
  });
  const src: string = '正文\n微信公众号：abc';
  assert.equal(purifyText(src, off), src);
});

test('净化：不许误伤正文（关键护栏）', () => {
  const body: string = [
    '第一章 山雨欲来',
    '他说："这件事没那么简单。"',
    '她点点头，心里却想着另一件事——三年前的那个夜晚。',
    '手机响了，是陌生号码。',
    '——完——'
  ].join('\n');
  const got: string = purifyText(body, RULES);
  assert.equal(got, body, '正常正文一个字都不许变');
});
