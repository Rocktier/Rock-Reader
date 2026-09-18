/**
 * ZIP 读取器 + raw DEFLATE 解压（纯逻辑，CI 可跑）
 *
 * 这是 M4（EPUB）最关键的一组回归：EPUB 就是 zip，
 * 而"能不能正确解压真实 deflate 流"在本机与 CI 都只能靠这里证明。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { inflateRaw } from '../entry/src/main/ets/engine/zip/Inflate.ets';
import { ZipArchive } from '../entry/src/main/ets/engine/zip/ZipReader.ets';
import { buildZip, bytesOf } from './zipfixture.ts';
import { deflateRawSync } from 'node:zlib';

test('inflateRaw：能解开 zlib 产出的 deflate 流（高压缩比文本）', () => {
  const original = '第一章 雨夜\n' + '这是一段用于验证解压正确性的中文正文。'.repeat(500);
  const raw = bytesOf(original);
  const deflated = new Uint8Array(deflateRawSync(Buffer.from(raw)));
  const out = inflateRaw(deflated);
  assert.equal(Buffer.from(out).toString('utf8'), original);
});

test('inflateRaw：近似不可压缩的数据也要能正确还原（会走到 stored/多块路径）', () => {
  // 确定性伪随机（不依赖 crypto，保证每次 CI 结果一致）
  const raw = new Uint8Array(200000);
  let seed = 123456789;
  for (let i = 0; i < raw.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
    raw[i] = (seed >>> 16) & 0xFF;
  }
  const deflated = new Uint8Array(deflateRawSync(Buffer.from(raw), { level: 1 }));
  const out = inflateRaw(deflated);
  assert.equal(out.length, raw.length);
  assert.ok(Buffer.from(out).equals(Buffer.from(raw)), '字节必须完全一致');
});

test('inflateRaw：小数据与空数据不崩', () => {
  assert.equal(inflateRaw(new Uint8Array(deflateRawSync(Buffer.from('a')))).length, 1);
  assert.equal(inflateRaw(new Uint8Array(deflateRawSync(Buffer.from('')))).length, 0);
});

test('ZipArchive：解析中央目录，列出全部条目', () => {
  const zip = buildZip([
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'META-INF/container.xml', data: bytesOf('<container/>') }
  ]);
  const archive = ZipArchive.parse(zip);
  assert.equal(archive.has('mimetype'), true);
  assert.equal(archive.has('META-INF/container.xml'), true);
  assert.equal(archive.has('nope.txt'), false);
  assert.deepEqual(archive.names().sort(), ['META-INF/container.xml', 'mimetype']);
});

test('ZipArchive：stored（不压缩）与 deflate 两种条目都能正确读出', () => {
  const text = '第二章 砾石\n正文内容，包含中文与符号：—「」…';
  const zip = buildZip([
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'OEBPS/ch1.xhtml', data: bytesOf(text) }
  ]);
  const archive = ZipArchive.parse(zip);
  assert.equal(archive.readText('mimetype'), 'application/epub+zip');
  assert.equal(archive.readText('OEBPS/ch1.xhtml'), text, 'UTF-8 多字节字符必须还原正确');
});

test('ZipArchive：带 BOM 的 XML 自动剥掉 BOM', () => {
  const bom = new Uint8Array([0xEF, 0xBB, 0xBF]);
  const body = bytesOf('<?xml version="1.0"?><a/>');
  const withBom = new Uint8Array(bom.length + body.length);
  withBom.set(bom, 0);
  withBom.set(body, bom.length);
  const archive = ZipArchive.parse(buildZip([{ name: 'x.xml', data: withBom }]));
  assert.equal(archive.readText('x.xml'), '<?xml version="1.0"?><a/>');
});

test('ZipArchive：不存在的条目抛 NO_ENTRY（不返回空、不静默）', () => {
  const archive = ZipArchive.parse(buildZip([{ name: 'a.txt', data: bytesOf('a') }]));
  assert.throws(() => archive.read('b.txt'), /NO_ENTRY/);
});

test('ZipArchive：不是 zip 的数据要明确抛错（不许当空书处理）', () => {
  assert.throws(() => ZipArchive.parse(bytesOf('this is definitely not a zip file at all........')), /BAD_ZIP/);
});

test('ZipArchive：超大文件的目录偏移错乱要被识别（截断的 zip）', () => {
  const zip = buildZip([{ name: 'a.txt', data: bytesOf('hello world') }]);
  const truncated = zip.slice(0, zip.length - 10);
  assert.throws(() => ZipArchive.parse(truncated), /BAD_ZIP/);
});
