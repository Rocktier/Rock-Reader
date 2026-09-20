/**
 * EPUB 非正文页剔除（P11-1 + P12-1，纯逻辑，CI 可跑）
 *
 * 守两类规范标记：
 *   ① 目录页 —— `properties="nav"`（EPUB3）/ guide 的 `<reference type="toc">`（EPUB2）/
 *      文件名像目录 + 链接密度（启发式兜底）
 *   ② `linear="no"` —— EPUB 规范：该文档**不属于线性阅读顺序**（版权页 / 彩插 / 附录常这么标）
 * 以及两条保底：判据踩空时整体放弃剔除（**宁可能读，不能空手**）。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ZipArchive } from '../entry/src/main/ets/engine/zip/ZipReader.ets';
import { parseEpubArchive } from '../entry/src/main/ets/engine/epub/EpubParse.ets';
import { buildZip, bytesOf } from './zipfixture.ts';

interface Doc {
  id: string;
  href: string;
  /** 页内 HTML 片段 */
  body: string;
  /** itemref 的 linear 属性；省略 = 不写 */
  linear?: string;
  /** manifest item 的 properties 属性；省略 = 不写 */
  properties?: string;
}

/** 造一本 spine 完全可控的 EPUB，用来验证"哪些条目会进正文流" */
function makeEpub(docs: Doc[], guideTocHref?: string, guideCoverHref?: string): Uint8Array {
  const manifest: string[] = [];
  const spine: string[] = [];
  const files: Array<{ name: string; data: Uint8Array }> = [];

  for (let i: number = 0; i < docs.length; i++) {
    const d: Doc = docs[i];
    const props: string = d.properties === undefined || d.properties.length === 0
      ? '' : ` properties="${d.properties}"`;
    manifest.push(`<item href="${d.href}" id="${d.id}" media-type="application/xhtml+xml"${props}/>`);
    const lin: string = d.linear === undefined || d.linear.length === 0 ? '' : ` linear="${d.linear}"`;
    spine.push(`<itemref idref="${d.id}"${lin}/>`);
    files.push({ name: 'OEBPS/' + d.href, data: bytesOf(`<html><body>${d.body}</body></html>`) });
  }

  const refs: string = (guideTocHref === undefined ? '' : `<reference type="toc" href="${guideTocHref}"/>`) +
    (guideCoverHref === undefined ? '' : `<reference type="cover" href="${guideCoverHref}"/>`);
  const guide: string = refs.length === 0 ? '' : `<guide>${refs}</guide>`;
  const opf = `<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>目录测试书</dc:title></metadata>
  <manifest>${manifest.join('')}</manifest>
  <spine>${spine.join('')}</spine>${guide}</package>`;
  const container = `<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`;

  return buildZip([
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'META-INF/container.xml', data: bytesOf(container) },
    { name: 'OEBPS/content.opf', data: bytesOf(opf) }
  ].concat(files));
}

test('linear="no" 的条目不进正文流（规范：不属于线性阅读顺序）', () => {
  const zip = ZipArchive.parse(makeEpub([
    { id: 'cover', href: 'cover.xhtml', body: '<p>版权页：版权所有</p>', linear: 'no' },
    { id: 'c1', href: 'c1.xhtml', body: '<h1>第一章</h1><p>正文一</p>' },
    { id: 'c2', href: 'c2.xhtml', body: '<h1>第二章</h1><p>正文二</p>' }
  ]));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 2);
  assert.ok(!parsed.chapters.some((c) => c.href.indexOf('cover') >= 0), '版权页不该排进正文');
  assert.ok(parsed.chapters[0].href.indexOf('c1.xhtml') >= 0, '章节顺序应保持 spine 顺序');
});

test('guide 的 <reference type="toc"> 指向的页面被剔除（EPUB2 规范指针）', () => {
  // 文件名 tocpage 不像 toc/nav/contents，页内也只有 1 个链接 ——
  // 只靠"文件名 + 链接密度"判不出来，必须靠规范指针
  const zip = ZipArchive.parse(makeEpub([
    { id: 'toc', href: 'tocpage.xhtml', body: '<h1>目录</h1><a href="c1.xhtml">第一章</a>' },
    { id: 'c1', href: 'c1.xhtml', body: '<h1>第一章</h1><p>正文</p>' }
  ], 'tocpage.xhtml'));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 1);
  assert.ok(parsed.chapters[0].href.indexOf('c1.xhtml') >= 0);
});

test('保底：若 linear="no" 把全部条目都排除掉，则整体放弃按它过滤（宁可能读）', () => {
  const zip = ZipArchive.parse(makeEpub([
    { id: 'a', href: 'a.xhtml', body: '<p>甲</p>', linear: 'no' },
    { id: 'b', href: 'b.xhtml', body: '<p>乙</p>', linear: 'no' }
  ]));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 2, '全书都被标 linear=no 时不能把书读空');
});

test('properties="nav"（EPUB3 规范标记）仍然生效', () => {
  // 文件名 navdoc 也不像目录 → 只能靠 manifest 的 properties
  const zip = ZipArchive.parse(makeEpub([
    { id: 'nav', href: 'navdoc.xhtml', body: '<h1>目录</h1><a href="c1.xhtml">第一章</a>', properties: 'nav' },
    { id: 'c1', href: 'c1.xhtml', body: '<h1>第一章</h1><p>正文</p>' }
  ]));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 1);
});

test('guide 的 <reference type="cover"> 指向的封面页被剔除（EPUB2 老书全靠它）', () => {
  // 实测样书：102 个 itemref 里一个 linear 属性都没有，cover 页只能靠 guide 的 type="cover" 认出来
  const zip = ZipArchive.parse(makeEpub([
    { id: 'tp', href: 'titlepage.xhtml', body: '<p>封面图</p>' },
    { id: 'c1', href: 'c1.xhtml', body: '<h1>第一章</h1><p>正文</p>' }
  ], undefined, 'titlepage.xhtml'));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 1, '封面页不该进正文流');
  assert.ok(parsed.chapters[0].href.indexOf('c1.xhtml') >= 0);
});

test('linear="yes" 与不写该属性一样：正常进正文流（别把默认值当排除条件）', () => {
  const zip = ZipArchive.parse(makeEpub([
    { id: 'c1', href: 'c1.xhtml', body: '<h1>第一章</h1><p>正文一</p>', linear: 'yes' },
    { id: 'c2', href: 'c2.xhtml', body: '<h1>第二章</h1><p>正文二</p>' }
  ]));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 2);
});
