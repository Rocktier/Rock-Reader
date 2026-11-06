/**
 * 封面识别的四条真实写法（纯逻辑，CI 可跑）
 *
 * 背景：封面**不是**导入时"能抽就抽"的锦上添花 —— 书架上一本书有没有封面，
 * 直接决定用户能不能在几十本里一眼认出它。而 EPUB 的封面声明方式在现实中至少有四种：
 *   ① EPUB3 规范：manifest 的 `properties="cover-image"`
 *   ② EPUB2 老写法：`<meta name="cover">`（content 是 id，偶尔被写成文件名）
 *   ③ EPUB2 guide：`<reference type="cover">` 指到**一页 XHTML**，图在页面里
 *   ④ 什么都没有，只有个叫 cover.jpg 的文件
 * 只认前两种的话，第 ③④ 类书在书架上永远是首字占位 —— 这是本文件存在的理由。
 *
 * 全部用内存里现造的真实 zip 跑（与 epub.test.ts 同一套 buildZip），不引版权书。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ZipArchive } from '../entry/src/main/ets/engine/zip/ZipReader.ets';
import { parseEpubArchive } from '../entry/src/main/ets/engine/epub/EpubParse.ets';
import { coverImageOfPage, coverScoreOf, guessCoverHref, ManifestItem, parseOpf } from '../entry/src/main/ets/engine/epub/Opf.ets';
import { isImageBytes } from '../entry/src/main/ets/engine/importer/CoverImage.ets';
import { buildZip, bytesOf, BuildEntry } from './zipfixture.ts';

/** 假 JPEG 头（够过 isImageBytes，不需要真能解码） */
const JPG: Uint8Array = new Uint8Array([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00
]);
const PNG: Uint8Array = new Uint8Array([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D
]);

const CONTAINER = `<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>`;

const NCX = `<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1"><navLabel><text>第一章</text></navLabel><content src="ch1.xhtml"/></navPoint>
    <navPoint id="n2" playOrder="2"><navLabel><text>第二章</text></navLabel><content src="ch2.xhtml"/></navPoint>
  </navMap>
</ncx>`;

const CH1 = `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
<body><h1>第一章</h1><p>正文一。</p></body></html>`;
const CH2 = `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
<body><h1>第二章</h1><p>正文二。</p></body></html>`;

/** 封面页（EPUB2 形态）：整页只有一张图，没有任何文字 */
const COVER_PAGE = `<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Cover</title></head>
<body><div><img src="../Images/cover.jpg" alt="Cover"/></div></body></html>`;

function opfOf(manifestExtra: string, metaExtra: string, guide: string): string {
  return `<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>封面测试书</dc:title><dc:creator>某作者</dc:creator><dc:language>zh</dc:language>
    ${metaExtra}
  </metadata>
  <manifest>
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
    <item href="ch1.xhtml" id="c1" media-type="application/xhtml+xml"/>
    <item href="ch2.xhtml" id="c2" media-type="application/xhtml+xml"/>
    <item href="Images/inline.png" id="inline" media-type="image/png"/>
    ${manifestExtra}
  </manifest>
  <spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/></spine>
  ${guide}
</package>`;
}

function epubOf(opf: string, extra: BuildEntry[]): ZipArchive {
  const entries: BuildEntry[] = [
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'META-INF/container.xml', data: bytesOf(CONTAINER) },
    { name: 'OEBPS/content.opf', data: bytesOf(opf) },
    { name: 'OEBPS/toc.ncx', data: bytesOf(NCX) },
    { name: 'OEBPS/ch1.xhtml', data: bytesOf(CH1) },
    { name: 'OEBPS/ch2.xhtml', data: bytesOf(CH2) },
    { name: 'OEBPS/Images/inline.png', data: PNG }
  ];
  return ZipArchive.parse(buildZip(entries.concat(extra)));
}

test('封面①：EPUB3 的 properties="cover-image" 直接命中', () => {
  const opf = opfOf('<item href="Images/cover.jpg" id="cimg" media-type="image/jpeg" properties="cover-image"/>', '', '');
  const parsed = parseEpubArchive(epubOf(opf, [{ name: 'OEBPS/Images/cover.jpg', data: JPG }]));
  assert.equal(parsed.coverHref, 'OEBPS/Images/cover.jpg');
});

test('封面②：<meta name="cover"> 的 content 是 id —— 老写法仍要命中', () => {
  const opf = opfOf('<item href="Images/cover.jpg" id="cimg" media-type="image/jpeg"/>',
    '<meta name="cover" content="cimg"/>', '');
  const parsed = parseEpubArchive(epubOf(opf, [{ name: 'OEBPS/Images/cover.jpg', data: JPG }]));
  assert.equal(parsed.coverHref, 'OEBPS/Images/cover.jpg');
});

test('封面②b：content 被写成文件名（不是 id）也要命中 —— 按 id 找必然落空', () => {
  const opf = opfOf('<item href="Images/cover.jpg" id="cimg" media-type="image/jpeg"/>',
    '<meta name="cover" content="cover.jpg"/>', '');
  const parsed = parseEpubArchive(epubOf(opf, [{ name: 'OEBPS/Images/cover.jpg', data: JPG }]));
  assert.equal(parsed.coverHref, 'OEBPS/Images/cover.jpg');
});

test('封面③：只有 guide 指到封面页 —— 抠出页面里的 <img>，而不是把 XHTML 当封面', () => {
  const opf = opfOf('<item href="Text/cover.xhtml" id="cp" media-type="application/xhtml+xml"/>', '',
    '<guide><reference type="cover" href="Text/cover.xhtml"/></guide>');
  const parsed = parseEpubArchive(epubOf(opf, [
    { name: 'OEBPS/Text/cover.xhtml', data: bytesOf(COVER_PAGE) },
    { name: 'OEBPS/Images/cover.jpg', data: JPG }
  ]));
  // 封面图本身没有声明 ⇒ coverHref 空，靠 guide 这条线索
  assert.equal(parsed.coverHref, '');
  assert.equal(parsed.guideCoverHref, 'OEBPS/Text/cover.xhtml');

  const imgHref = coverImageOfPage(COVER_PAGE, parsed.guideCoverHref);
  // '../Images/cover.jpg' 相对 'OEBPS/Text/' 要回到 'OEBPS/'
  assert.equal(imgHref, 'OEBPS/Images/cover.jpg');
  // 而且这确实是图片，不是那张 inline.png
  assert.equal(isImageBytes(JPG), true);
});

test('封面④：什么声明都没有，只有个叫 cover.jpg 的文件 —— 命名启发式兜底', () => {
  const opf = opfOf('<item href="Images/cover.jpg" id="img7" media-type="image/jpeg"/>', '', '');
  const parsed = parseEpubArchive(epubOf(opf, [{ name: 'OEBPS/Images/cover.jpg', data: JPG }]));
  assert.equal(parsed.coverHref, 'OEBPS/Images/cover.jpg');
});

test('启发式不认错：inline.png 之类不含 cover 的图绝不能被当封面', () => {
  const opf = opfOf('<item href="Images/pic01.png" id="pic1" media-type="image/png"/>', '', '');
  const parsed = parseEpubArchive(epubOf(opf, [{ name: 'OEBPS/Images/pic01.png', data: PNG }]));
  assert.equal(parsed.coverHref, '');
});

test('正封优先于缩略图/封底：同名带 cover 的两张图，精确命名的赢', () => {
  const items: ManifestItem[] = [
    { id: 'p1', href: 'Images/cover-back.jpg', mediaType: 'image/jpeg', properties: '' },
    { id: 'p2', href: 'Images/cover.jpg', mediaType: 'image/jpeg', properties: '' },
    { id: 'p3', href: 'Images/cover-thumb.jpg', mediaType: 'image/jpeg', properties: '' }
  ];
  assert.equal(coverScoreOf(items[2]), 2);
  assert.equal(coverScoreOf(items[1]), 3);
  assert.equal(guessCoverHref('OEBPS/', items), 'OEBPS/Images/cover.jpg');
});

test('启发式不越界：文字与音频文件都不算封面（哪怕 id 里带 cover 字样）', () => {
  const items: ManifestItem[] = [
    { id: 'coverpage', href: 'Text/cover.xhtml', mediaType: 'application/xhtml+xml', properties: '' },
    { id: 'coveraudio', href: 'Audio/cover.mp3', mediaType: 'audio/mpeg', properties: '' }
  ];
  assert.equal(guessCoverHref('OEBPS/', items), '');
});

test('SVG 封面页也能抠出图（<image xlink:href>）', () => {
  const svgPage = `<html xmlns="http://www.w3.org/1999/xhtml"><body><div>
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 600 800">
      <image width="600" height="800" xlink:href="../Images/cover.png"/>
    </svg></div></body></html>`;
  assert.equal(coverImageOfPage(svgPage, 'OEBPS/Text/cover.xhtml'), 'OEBPS/Images/cover.png');
});

test('封面页里没有图片 ⇒ 返回空串（调用方回退首字占位，不能崩）', () => {
  const textPage = `<html><body><h1>Cover</h1><p>这页只是文字</p></body></html>`;
  assert.equal(coverImageOfPage(textPage, 'OEBPS/Text/cover.xhtml'), '');
});

test('字节判定：认 jpg/png/gif/webp/bmp，不认 HTML 与过短数据', () => {
  assert.equal(isImageBytes(JPG), true);
  assert.equal(isImageBytes(PNG), true);
  assert.equal(isImageBytes(bytesOf('GIF89a......')), true);
  assert.equal(isImageBytes(bytesOf('RIFF0000WEBPVP8 ')), true);
  assert.equal(isImageBytes(bytesOf('<html><body>x')), false);
  assert.equal(isImageBytes(new Uint8Array([0xFF, 0xD8])), false); // 太短，可能是巧合
  // 真实场景：EPUB2 的封面页被误当图片写下去
  assert.equal(isImageBytes(bytesOf(COVER_PAGE)), false);
});

test('parseOpf 不再把「封面页」当章节封面：coverHref 与 guideCoverHref 各归各位', () => {
  const opf = opfOf('<item href="Text/cover.xhtml" id="cp" media-type="application/xhtml+xml"/>', '',
    '<guide><reference type="cover" href="Text/cover.xhtml"/></guide>');
  const pkg = parseOpf(opf, 'OEBPS/');
  assert.equal(pkg.coverHref, '', 'guide 指的是一页 XHTML，不是图片，不能塞进 coverHref');
  assert.equal(pkg.guideCoverHref, 'OEBPS/Text/cover.xhtml');
});
