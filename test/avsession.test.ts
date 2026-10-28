/**
 * 媒体会话（AVSession）纯逻辑单测
 *
 * 守的是**系统媒体控制按下去之后应用怎么反应**——
 * 这段如果写错，症状是「锁屏按播放从头读」「按暂停没反应」「没在读时按停止把引擎关了」，
 * 而这些在模拟器上根本看不到（模拟器没有锁屏媒体中心），只能靠测试兜住。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MediaCommand,
  normalizeSpeed,
  respondToCommand,
  snapSpeed,
  SpeakAction,
  SpeakPhase,
  SpeakView
} from '../entry/src/main/ets/engine/tts/AvSessionState.ets';

/** 构造一个朗读状态快照 */
function view(active: boolean, paused: boolean, preparing: boolean = false): SpeakView {
  return { active: active, paused: paused, preparing: preparing };
}

test('没有朗读会话时按播放 → 起播', () => {
  assert.equal(respondToCommand(view(false, false), MediaCommand.PLAY), SpeakAction.START);
});

test('暂停中按播放 → 从暂停点续播（不是从头）', () => {
  assert.equal(respondToCommand(view(true, true), MediaCommand.PLAY), SpeakAction.RESUME);
});

test('正在播时按播放 → 什么都不做（不能重复起播）', () => {
  assert.equal(respondToCommand(view(true, false), MediaCommand.PLAY), SpeakAction.NONE);
});

test('正在播时按暂停 → 暂停', () => {
  assert.equal(respondToCommand(view(true, false), MediaCommand.PAUSE), SpeakAction.PAUSE);
});

test('暂停中再按暂停 → 什么都不做', () => {
  assert.equal(respondToCommand(view(true, true), MediaCommand.PAUSE), SpeakAction.NONE);
});

test('没在朗读时按暂停 → 什么都不做', () => {
  assert.equal(respondToCommand(view(false, false), MediaCommand.PAUSE), SpeakAction.NONE);
});

test('在朗读时按停止 → 停止', () => {
  assert.equal(respondToCommand(view(true, false), MediaCommand.STOP), SpeakAction.STOP);
  assert.equal(respondToCommand(view(true, true), MediaCommand.STOP), SpeakAction.STOP);
});

test('没在朗读时按停止 → 什么都不做（别把引擎关了）', () => {
  assert.equal(respondToCommand(view(false, false), MediaCommand.STOP), SpeakAction.NONE);
});

test('准备中（首段还没开播）按播放 → 什么都不做（已经在准备里了）', () => {
  assert.equal(respondToCommand(view(true, false, true), MediaCommand.PLAY), SpeakAction.NONE);
});

test('朗读状态枚举三态互不重叠', () => {
  assert.notEqual(SpeakPhase.IDLE, SpeakPhase.PLAYING);
  assert.notEqual(SpeakPhase.PLAYING, SpeakPhase.PAUSED);
  assert.notEqual(SpeakPhase.IDLE, SpeakPhase.PAUSED);
});

test('倍速归一化：只认 0.5~2.0，其余回 1.0', () => {
  assert.equal(normalizeSpeed(1.0), 1.0);
  assert.equal(normalizeSpeed(0.5), 0.5);
  assert.equal(normalizeSpeed(2.0), 2.0);
  assert.equal(normalizeSpeed(0.4), 1.0);
  assert.equal(normalizeSpeed(2.5), 1.0);
  assert.equal(normalizeSpeed(NaN), 1.0);
  assert.equal(normalizeSpeed(Infinity), 1.0);
});

test('倍速吸附到最近档位', () => {
  const speeds: number[] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  assert.equal(snapSpeed(1.1, speeds), 1.0);
  assert.equal(snapSpeed(1.2, speeds), 1.25);
  assert.equal(snapSpeed(0.6, speeds), 0.5);
  assert.equal(snapSpeed(99, speeds), 1.0);
  assert.equal(snapSpeed(1.5, []), 1.5);
});
