import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  PDF_FORMAT, clampPage, isPdfFormat, pageLabel, parsePageInput, pdfFailReason,
  percentOfPage, pickPdfTitle, startPageOf
} from '../entry/src/main/ets/engine/pdf/PdfPages';

// ── PDF 页码 ↔ 进度 ↔ 输入 ──────────────────────────────────────────
//
// 背景（2026-11-05）：Reader 此前**一行 PDF 代码都没有** —— 全仓 grep `pdf`
// 只命中 MarkupParser 里两行注释。党哥拍板只做论文与电子书（都是文字版，不是扫描件）。
//
// 这组用例锁的是三件最容易错、又最贵的事：
//   ① 分母用错 ⇒ 3 页的论文一打开就显示"读过 33%"
//   ② 除零 ⇒ NaN 写进进度库，书架进度条从此画不出来（不可逆脏数据）
//   ③ 1 基 / 0 基混用 ⇒ 点第 12 页停在 11 页

const TOTAL: number = 340;

// ── ① 格式判定 ──────────────────────────────────────────────────────

test('isPdfFormat 只认小写 pdf（落库口径与 parseKindOf 一致）', () => {
  assert.equal(PDF_FORMAT, 'pdf');
  assert.equal(isPdfFormat('pdf'), true);
  assert.equal(isPdfFormat('PDF'), false, '落库前已 toLowerCase，这里不该为大小写兜底');
  assert.equal(isPdfFormat('epub'), false);
  assert.equal(isPdfFormat(''), false);
});

// ── ② 页码夹紧 ──────────────────────────────────────────────────────

test('clampPage 越界夹到两端', () => {
  assert.equal(clampPage(-5, TOTAL), 0);
  assert.equal(clampPage(0, TOTAL), 0);
  assert.equal(clampPage(339, TOTAL), 339);
  assert.equal(clampPage(9999, TOTAL), 339);
});

test('clampPage 面对 total=0（还没 load 完）不炸、不返回负数', () => {
  assert.equal(clampPage(0, 0), 0);
  assert.equal(clampPage(10, 0), 0);
  assert.equal(clampPage(5, -1), 0);
});

test('clampPage 面对 NaN / 小数一律归 0，不把脏值透传出去', () => {
  assert.equal(clampPage(NaN, TOTAL), 0);
  assert.equal(clampPage(3.7, TOTAL), 0, '小数不是合法页码，宁可回第 0 页');
  assert.equal(clampPage(0, NaN), 0);
});

// ── ③ 进度换算（分母必须 total-1） ──────────────────────────────────

test('⭐ 第一页是 0%、最后一页是 100%（分母用 total-1）', () => {
  assert.equal(percentOfPage(0, TOTAL), 0);
  assert.equal(percentOfPage(339, TOTAL), 1);
});

test('⭐ 3 页的论文：打开时是 0%，不是 33%', () => {
  // 若用 (page+1)/total，这里会是 1/3 —— 书架一打开就显示"读过三分之一"
  assert.equal(percentOfPage(0, 3), 0);
  assert.equal(percentOfPage(1, 3), 0.5);
  assert.equal(percentOfPage(2, 3), 1);
});

test('单页 PDF 打开即视为读完（返回 1，不是 0/0 的 NaN）', () => {
  assert.equal(percentOfPage(0, 1), 1);
});

test('percentOfPage 在 total=0 时返回 0，绝不产生 NaN/Infinity', () => {
  const v: number = percentOfPage(0, 0);
  assert.equal(v, 0);
  assert.equal(Number.isFinite(v), true);
});

test('percentOfPage 对越界页码先夹紧再算，结果仍落在 [0,1]', () => {
  assert.equal(percentOfPage(99999, TOTAL), 1);
  assert.equal(percentOfPage(-3, TOTAL), 0);
});

// ── ④ 续读定位 ──────────────────────────────────────────────────────

test('startPageOf 优先用 chapterIndex（它就是页码，精确）', () => {
  assert.equal(startPageOf(12, 0.9, TOTAL), 12, 'percent 与页码冲突时以页码为准');
});

test('startPageOf 在 chapterIndex 越界时退回 percent 反推', () => {
  assert.equal(startPageOf(9999, 0.5, 3), 1, '3 页书 50% ⇒ 第 1 页');
});

test('⭐ startPageOf 反推用 round 不用 floor（否则续读会一直往回退）', () => {
  // 66% × 2 = 1.32 ⇒ round 1、floor 也是 1；用 75% 更能看出差别：0.75×2=1.5 ⇒ round 2
  assert.equal(startPageOf(-1, 0.75, 3), 2);
  // 10 页书 66%：0.66×9 = 5.94 ⇒ round 6、floor 5
  assert.equal(startPageOf(-1, 0.66, 10), 6);
});

test('startPageOf 面对脏数据（NaN percent / 空库）一律回第 0 页', () => {
  assert.equal(startPageOf(-1, NaN, TOTAL), 0);
  assert.equal(startPageOf(-1, 0, TOTAL), 0);
  assert.equal(startPageOf(NaN, NaN, TOTAL), 0);
  assert.equal(startPageOf(5, 0.5, 0), 0);
});

// ── ⑤ 页签文案 ──────────────────────────────────────────────────────

test('pageLabel 对外 1 基显示', () => {
  assert.equal(pageLabel(0, TOTAL), '1 / 340');
  assert.equal(pageLabel(11, TOTAL), '12 / 340');
  assert.equal(pageLabel(339, TOTAL), '340 / 340');
});

test('pageLabel 在 total=0 时返回空串（宁可不显示，也不显示 "1 / 0"）', () => {
  assert.equal(pageLabel(0, 0), '');
});

// ── ⑥ 跳页输入 ──────────────────────────────────────────────────────

test('parsePageInput 纯数字按 1 基理解', () => {
  assert.equal(parsePageInput('12', TOTAL), 11);
  assert.equal(parsePageInput('1', TOTAL), 0);
  assert.equal(parsePageInput('340', TOTAL), 339);
  assert.equal(parsePageInput('  12  ', TOTAL), 11, '前后空格要能吃');
});

test('parsePageInput 认 "12/340" 这种从 PDF 页码抄来的写法', () => {
  assert.equal(parsePageInput('12/340', TOTAL), 11);
  assert.equal(parsePageInput('12 / 340', TOTAL), 11);
});

test('parsePageInput 认百分比', () => {
  assert.equal(parsePageInput('0%', TOTAL), 0);
  assert.equal(parsePageInput('100%', TOTAL), 339);
  assert.equal(parsePageInput('50%', TOTAL), 170);
});

test('⭐ parsePageInput 越界返回 -1（不"猜个最近的"，用户输错就停在原地）', () => {
  assert.equal(parsePageInput('0', TOTAL), -1, '第 0 页不存在，1 基最小是 1');
  assert.equal(parsePageInput('341', TOTAL), -1);
  assert.equal(parsePageInput('-5', TOTAL), -1);
  assert.equal(parsePageInput('101%', TOTAL), -1);
  assert.equal(parsePageInput('-1%', TOTAL), -1);
});

test('parsePageInput 面对空串/非数字/空百分比一律 -1', () => {
  assert.equal(parsePageInput('', TOTAL), -1);
  assert.equal(parsePageInput('   ', TOTAL), -1);
  assert.equal(parsePageInput('abc', TOTAL), -1);
  assert.equal(parsePageInput('%', TOTAL), -1);
  assert.equal(parsePageInput('12.7', TOTAL), 12, '小数四舍五入，不当成非法');
});

test('parsePageInput 在 total=0（还没 load）时任何输入都无效', () => {
  assert.equal(parsePageInput('1', 0), -1);
});

// ── ⑦ ParseResult → 拒绝原因 ────────────────────────────────────────

test('pdfFailReason：0 = 成功（空串 = 不打扰用户）', () => {
  assert.equal(pdfFailReason(0), '');
});

test('⭐ pdfFailReason：3 = 要密码，必须单独成一个原因', () => {
  // 用户看到"文件损坏"会去重新下载，而加密 PDF 重下多少次都一样
  assert.equal(pdfFailReason(3), 'PDF_ENCRYPTED');
});

test('pdfFailReason：其余错误码都归 PDF_BROKEN', () => {
  assert.equal(pdfFailReason(1), 'PDF_BROKEN');
  assert.equal(pdfFailReason(2), 'PDF_BROKEN');
  assert.equal(pdfFailReason(4), 'PDF_BROKEN');
  assert.equal(pdfFailReason(99), 'PDF_BROKEN', '未知码也不能说"成功"');
});

// ── ⑧ 端到端：翻页 → 存进度 → 重开 → 回到原页 ──────────────────────

test('⭐ 模拟一次完整阅读：翻到第 100 页存进度，重开能回到第 100 页', () => {
  const readAt: number = 99;                          // 0 基第 100 页
  const pct: number = percentOfPage(readAt, TOTAL);   // 存进库里的 percent
  assert.equal(Math.abs(pct - 99 / 339) < 1e-9, true);

  // 重开：chapterIndex 就是页码
  assert.equal(startPageOf(readAt, pct, TOTAL), 99);
  // 只拿到 percent（比如换版本）：反推也要落回同一页
  assert.equal(startPageOf(-1, pct, TOTAL), 99);
});

// ── ⑨ 书名取用（论文 PDF 的 metadata 多半是垃圾） ────────────────────

test('⭐ Word 导出的垃圾 title 不能当书名，退回文件名', () => {
  // 这是论文 PDF 最常见的情况：title 是当年随手起的草稿名
  assert.equal(pickPdfTitle('Microsoft Word - 论文初稿.doc', 'Attention Is All You Need'), 'Attention Is All You Need');
  assert.equal(pickPdfTitle('Microsoft PowerPoint - 组会汇报', 'BERT 精读'), 'BERT 精读');
});

test('空 / 过短的 title 退回文件名', () => {
  assert.equal(pickPdfTitle('', '深度学习'), '深度学习');
  assert.equal(pickPdfTitle('   ', '深度学习'), '深度学习');
  assert.equal(pickPdfTitle('A', '深度学习'), '深度学习');
});

test('正常 title 优先于文件名（元数据里的才是真书名）', () => {
  assert.equal(pickPdfTitle('Attention Is All You Need', '1706.03762'), 'Attention Is All You Need');
});

test('untitled / 无标题 也认作垃圾', () => {
  assert.equal(pickPdfTitle('Untitled', '我的论文'), '我的论文');
  assert.equal(pickPdfTitle('无标题文档', '我的论文'), '我的论文');
});

test('两边都空时返回空串，由调用方兜底（不当场炸）', () => {
  assert.equal(pickPdfTitle('', ''), '');
});
