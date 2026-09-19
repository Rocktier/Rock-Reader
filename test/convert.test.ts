/**
 * 简繁转换单测
 * 护栏重点：① 已收录字要转对 ② 未收录字/有歧义字不许乱转
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  convertByMode,
  toSimplified,
  toTraditional
} from '../entry/src/main/ets/engine/text/ChineseConvert.ets';

test('简 → 繁：常用词', () => {
  assert.equal(toTraditional('时间'), '時間');
  assert.equal(toTraditional('我们'), '我們');
  assert.equal(toTraditional('读书'), '讀書');
  assert.equal(toTraditional('这个'), '這個');
});

test('繁 → 简：常用词', () => {
  assert.equal(toSimplified('時間'), '时间');
  assert.equal(toSimplified('我們'), '我们');
  assert.equal(toSimplified('閱讀'), '阅读');
});

test('未收录的字原样返回（的/是/了/在 这类）', () => {
  assert.equal(toTraditional('的'), '的');
  assert.equal(toTraditional('是'), '是');
  assert.equal(toSimplified('的'), '的');
});

test('有歧义的字不收录 → 不许错转（皇后不能被转成皇後）', () => {
  assert.equal(toTraditional('皇后'), '皇后', '「后」在表里应缺席，否则会变「皇後」');
  assert.equal(toTraditional('干净'), '干净', '「干」不收录，避免「乾淨/幹活」歧义');
  assert.equal(toTraditional('里面'), '裡面');
});

test('往返一致性：简→繁→简 回到原文', () => {
  const src: string = '他打开电脑，开始阅读这本小说的时间线。';
  assert.equal(toSimplified(toTraditional(src)), src);
});

test('convertByMode：off 原样，未知模式也原样', () => {
  assert.equal(convertByMode('时间', 'off'), '时间');
  assert.equal(convertByMode('时间', 'unknown'), '时间');
  assert.equal(convertByMode('时间', 's2t'), '時間');
  assert.equal(convertByMode('時間', 't2s'), '时间');
});

test('空串与纯非中文不受影响', () => {
  assert.equal(toTraditional(''), '');
  assert.equal(toTraditional('abc 123 !@#'), 'abc 123 !@#');
});
