/**
 * EPUB 解析端到端（纯逻辑，CI 可跑）
 *
 * 用**内存里现造的真实 zip** 跑完整链路：container.xml → OPF → NCX → 章清单 → 章正文 → 纯文本。
 * 这是"本机无鸿蒙环境"下唯一能证明 EPUB 真的能读的手段（另有一次对真实出版 epub 的手工验证）。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ZipArchive } from '../entry/src/main/ets/engine/zip/ZipReader.ets';
import { epubChapterTextOf, parseEpubArchive } from '../entry/src/main/ets/engine/epub/EpubParse.ets';
import { normalizeHref, parseNcx, resolveHref } from '../entry/src/main/ets/engine/epub/Opf.ets';
import { firstHeadingOf, xhtmlToText } from '../entry/src/main/ets/engine/epub/Xhtml.ets';
import { attrOf, decodeEntities, findElementTexts } from '../entry/src/main/ets/engine/epub/Xml.ets';
import { buildZip, bytesOf } from './zipfixture.ts';

const CONTAINER = `<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>`;

const OPF = `<?xml version='1.0' encoding='utf-8'?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>测试之书 &amp; 副标题</dc:title>
    <dc:creator opf:role="aut">某作者</dc:creator>
    <dc:language>zh</dc:language>
    <meta name="cover" content="cover-img"/>
  </metadata>
  <manifest>
    <item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>
    <item href="ch1.xhtml" id="c1" media-type="application/xhtml+xml"/>
    <item href="ch2.xhtml" id="c2" media-type="application/xhtml+xml"/>
    <item href="images/cover.jpg" id="cover-img" media-type="image/jpeg"/>
    <item href="images/inline.png" id="inline-img" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/>
    <itemref idref="inline-img"/>
    <itemref idref="c2"/>
  </spine>
</package>`;

const NCX = `<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1" playOrder="1"><navLabel><text>第一章 雨夜</text></navLabel><content src="ch1.xhtml"/></navPoint>
    <navPoint id="n2" playOrder="2"><navLabel><text>第二章 砾石</text></navLabel><content src="ch2.xhtml"/></navPoint>
  </navMap>
</ncx>`;

const CH1 = `<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>第一章</title><style>p{color:red}</style><script>var a=1;</script></head>
<body>
  <h1>第一章 雨夜</h1>
  <p>第一段。<br/>换行后的第二句。</p>
  <p>第二段：&amp;符号、&lt;标签&gt;、&#8220;引号&#8221;、&#x2014;破折号。</p>
  <div><p>第三段。</p></div>
</body>
</html>`;

const CH2 = `<html><head><title>第二章</title></head><body><h2>第二章 砾石</h2><p>砾石正文。</p></body></html>`;

function buildEpub(): Uint8Array {
  return buildZip([
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'META-INF/container.xml', data: bytesOf(CONTAINER) },
    { name: 'OEBPS/content.opf', data: bytesOf(OPF) },
    { name: 'OEBPS/toc.ncx', data: bytesOf(NCX) },
    { name: 'OEBPS/ch1.xhtml', data: bytesOf(CH1) },
    { name: 'OEBPS/ch2.xhtml', data: bytesOf(CH2) }
  ]);
}

test('EPUB：从 container.xml → OPF 拿到书名/作者（含实体解码）', () => {
  const parsed = parseEpubArchive(ZipArchive.parse(buildEpub()));
  assert.equal(parsed.title, '测试之书 & 副标题');
  assert.equal(parsed.author, '某作者');
  assert.equal(parsed.coverHref, 'OEBPS/images/cover.jpg', 'meta name=cover 指向的封面要解析出来');
});

test('EPUB：spine 顺序 = 章节顺序，非 HTML 条目被跳过', () => {
  const parsed = parseEpubArchive(ZipArchive.parse(buildEpub()));
  assert.equal(parsed.chapters.length, 2, 'images/inline.png 在 spine 里但不该变成一章');
  assert.deepEqual(parsed.chapters.map((c) => c.title), ['第一章 雨夜', '第二章 砾石'],
    '标题来自 NCX（而不是文件名）');
  assert.deepEqual(parsed.chapters.map((c) => c.href), ['OEBPS/ch1.xhtml', 'OEBPS/ch2.xhtml']);
  assert.deepEqual(parsed.chapters.map((c) => c.index), [0, 1]);
});

test('EPUB：章正文 = 纯文本（去标签、丢 head/style/script、实体还原、段落留空行）', () => {
  const parsed = parseEpubArchive(ZipArchive.parse(buildEpub()));
  const text = epubChapterTextOf(ZipArchive.parse(buildEpub()), parsed.chapters[0].href);

  assert.ok(text.includes('第一章 雨夜'));
  assert.ok(text.includes('第一段。'), 'br 应转成换行而不是粘连');
  assert.ok(text.includes('换行后的第二句。'));
  assert.ok(text.includes('&符号、<标签>、“引号”、—破折号。'), '命名实体与数值实体都要还原');
  assert.ok(!text.includes('<p>') && !text.includes('&amp;'), '不该残留标签或实体原文');
  assert.ok(!text.includes('color:red') && !text.includes('var a=1'), 'style/script 内容必须丢掉');
  assert.ok(text.includes('\n\n'), '段落之间要有空行分隔');
});

test('EPUB：没有 NCX/nav 时，用章内第一个标题兜底（再不行用文件名）', () => {
  const opfNoNcx = OPF.replace('<item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>', '')
    .replace('<spine toc="ncx">', '<spine>');
  const zip = buildZip([
    { name: 'META-INF/container.xml', data: bytesOf(CONTAINER) },
    { name: 'OEBPS/content.opf', data: bytesOf(opfNoNcx) },
    { name: 'OEBPS/ch1.xhtml', data: bytesOf(CH1) },
    { name: 'OEBPS/ch2.xhtml', data: bytesOf(CH2) }
  ]);
  const parsed = parseEpubArchive(ZipArchive.parse(zip));
  assert.deepEqual(parsed.chapters.map((c) => c.title), ['第一章 雨夜', '第二章 砾石']);
});

test('EPUB：结构不对时明确抛错（不许静默变成空书）', () => {
  const noContainer = buildZip([{ name: 'OEBPS/content.opf', data: bytesOf(OPF) }]);
  assert.throws(() => parseEpubArchive(ZipArchive.parse(noContainer)), /EPUB_NO_CONTAINER/);

  const badOpfPath = buildZip([
    { name: 'META-INF/container.xml', data: bytesOf(CONTAINER) },
    { name: 'OEBPS/other.opf', data: bytesOf(OPF) }
  ]);
  assert.throws(() => parseEpubArchive(ZipArchive.parse(badOpfPath)), /EPUB_NO_OPF/);

  const noSpine = buildZip([
    { name: 'META-INF/container.xml', data: bytesOf(CONTAINER) },
    { name: 'OEBPS/content.opf', data: bytesOf(OPF.replace(/<spine[\s\S]*?<\/spine>/, '<spine></spine>')) }
  ]);
  assert.throws(() => parseEpubArchive(ZipArchive.parse(noSpine)), /EPUB_BAD_SPINE/);
});

test('EPUB：href 相对路径解析（../、%20、#fragment 都要对）', () => {
  assert.equal(resolveHref('OEBPS/', 'ch1.xhtml'), 'OEBPS/ch1.xhtml');
  assert.equal(resolveHref('OEBPS/', '../images/a.jpg'), 'images/a.jpg');
  assert.equal(resolveHref('OEBPS/', 'Text/ch1.xhtml#p3'), 'OEBPS/Text/ch1.xhtml');
  assert.equal(resolveHref('OEBPS/', 'a%20b.xhtml'), 'OEBPS/a b.xhtml');
  assert.equal(normalizeHref('x.html#frag'), 'x.html');
});

test('EPUB：NCX 的 navLabel 与 content 按结构配对（扁平 NCX）', () => {
  const map = parseNcx(NCX, 'OEBPS/');
  assert.equal(map.get('OEBPS/ch1.xhtml'), '第一章 雨夜');
  assert.equal(map.get('OEBPS/ch2.xhtml'), '第二章 砾石');

  const broken = `<ncx><navMap><navPoint><navLabel><text>只有标签</text></navLabel></navPoint></navMap></ncx>`;
  assert.equal(parseNcx(broken, 'OEBPS/').size, 0);
});

test('EPUB：嵌套 NCX（父节点有标签但无 content）不许整体错位一章', () => {
  // 这是真实出版书（calibre 生成）的结构：父 navPoint 只有 navLabel，content 全在子节点上。
  // 早期实现按"text 与 content 出现顺序"配对 → 每章标题都指向前一章的正文，实测踩到。
  const nested = `<ncx><navMap>
    <navPoint id="a"><navLabel><text>Cover</text></navLabel><content src="titlepage.xhtml"/></navPoint>
    <navPoint id="b"><navLabel><text>测试之书</text></navLabel>
      <navPoint id="b1"><navLabel><text>封面</text></navLabel><content src="s000.html"/></navPoint>
      <navPoint id="b2"><navLabel><text>版权页</text></navLabel><content src="s001.html"/></navPoint>
      <navPoint id="b3"><navLabel><text>第一章 开头</text></navLabel><content src="s002.html"/></navPoint>
    </navPoint>
  </navMap></ncx>`;
  const map = parseNcx(nested, 'OEBPS/');
  assert.equal(map.get('OEBPS/titlepage.xhtml'), 'Cover');
  assert.equal(map.get('OEBPS/s000.html'), '封面');
  assert.equal(map.get('OEBPS/s001.html'), '版权页', '错一章的话这里会变成「版权页」的上一项');
  assert.equal(map.get('OEBPS/s002.html'), '第一章 开头');
  assert.equal(map.get('OEBPS/测试之书'), undefined, '父节点的标签不该被当成某一章的标题');
});

test('EPUB：小节标题（带 #fragment）不许盖住章级标题 —— 无论谁先出现', () => {
  // 真实书里父 navPoint 的 content 在子节点**之后**才闭合，所以小节总是先入表；
  // 若只靠"先到先得"，目录里显示的就会是小节名而不是章名。
  const nested = `<ncx><navMap>
    <navPoint><navLabel><text>第一章</text></navLabel><content src="s002.html"/>
      <navPoint><navLabel><text>第一章的一小节</text></navLabel><content src="s002.html#filepos3037"/></navPoint>
      <navPoint><navLabel><text>第一章的另一小节</text></navLabel><content src="s002.html#filepos9"/></navPoint>
    </navPoint>
  </navMap></ncx>`;
  assert.equal(parseNcx(nested, 'OEBPS/').get('OEBPS/s002.html'), '第一章');

  // 反过来（小节先出现）也要章级标题赢
  const reverse = `<ncx><navMap>
    <navPoint><navLabel><text>第一章的一小节</text></navLabel><content src="s002.html#f1"/></navPoint>
    <navPoint><navLabel><text>第一章</text></navLabel><content src="s002.html"/></navPoint>
  </navMap></ncx>`;
  assert.equal(parseNcx(reverse, 'OEBPS/').get('OEBPS/s002.html'), '第一章');

  // 该文件只有小节标题时，退回小节标题（总比文件名强）
  const onlySection = `<ncx><navMap>
    <navPoint><navLabel><text>只有小节</text></navLabel><content src="s009.html#f1"/></navPoint>
  </navMap></ncx>`;
  assert.equal(parseNcx(onlySection, 'OEBPS/').get('OEBPS/s009.html'), '只有小节');
});

test('XHTML：firstHeadingOf 供兜底标题用', () => {
  assert.equal(firstHeadingOf(CH1), '第一章 雨夜');
  assert.equal(firstHeadingOf('<html><body><p>没有标题</p></body></html>'), '');
});

test('XML 工具：属性取值支持单双引号，实体支持十进制与十六进制', () => {
  assert.equal(attrOf('<item href="a.xhtml" id=\'x1\' media-type="text/html"/>', 'id'), 'x1');
  assert.equal(attrOf('<item href="a&amp;b.xhtml"/>', 'href'), 'a&b.xhtml');
  assert.equal(attrOf('<item id="x"/>', 'nope'), '');
  assert.equal(decodeEntities('&#65;&#x42;'), 'AB');
  assert.equal(decodeEntities('&nbsp;&unknown;'), '\u00A0&unknown;');
  assert.equal(decodeEntities('没有实体'), '没有实体');
});

test('XML 工具：findElementTexts 能取多个同名元素的文本（命名空间前缀也认）', () => {
  const xml = `<r><dc:title>甲</dc:title><x/><title>乙</title><title></title></r>`;
  assert.deepEqual(findElementTexts(xml, 'title'), ['甲', '乙', '']);
});

test('XHTML：空内容与纯空白不生成垃圾行', () => {
  assert.equal(xhtmlToText('<html><body>   \n\n  </body></html>'), '');
  assert.equal(xhtmlToText('<p>a</p><p></p><p>b</p>'), 'a\n\nb');
});
