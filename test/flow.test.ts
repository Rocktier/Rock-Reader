/**
 * 全流程不变量（纯逻辑，CI 可跑）
 *
 * 这条链路是：EPUB(zip) → 解析出章节 → 取章正文(纯文本) → 分页 → 页码 ↔ 字符偏移 → 进度恢复。
 * 这里不测具体数值，而是守住**不变量** —— 因为整条链路的 bug 几乎都表现为这几种：
 *   ① 丢字（分页边界把文字吃掉）  ② 重叠（同一段文字出现两次）
 *   ③ 错页（进度恢复后落到别的页）④ 崩（空章、单页章）
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ZipArchive } from '../entry/src/main/ets/engine/zip/ZipReader.ets';
import { epubChapterTextOf, parseEpubArchive } from '../entry/src/main/ets/engine/epub/EpubParse.ets';
import { FakePaginator, LayoutBox, PageCache, Paginator } from '../entry/src/main/ets/engine/paginator/Paginator.ets';
import { PageRange, PageTable, pageOfChar } from '../entry/src/main/ets/engine/paginator/PageTableBuilder.ets';
import { DEFAULT_LEVELS, LayoutLevels, layoutKey } from '../entry/src/main/ets/common/LayoutStyle.ets';
import { buildZip, bytesOf } from './zipfixture.ts';

/** 造一本有 n 章的合法 EPUB（章节正文含中文、换行、嵌套标签、实体） */
function makeEpub(chapterCount: number, parasPerChapter: number): Uint8Array {
  const manifest: string[] = [];
  const spine: string[] = [];
  const navPoints: string[] = [];
  const files: Array<{ name: string; data: Uint8Array }> = [];

  for (let i: number = 0; i < chapterCount; i++) {
    const id: string = 'c' + i;
    const href: string = 'ch' + i + '.xhtml';
    manifest.push(`<item href="${href}" id="${id}" media-type="application/xhtml+xml"/>`);
    spine.push(`<itemref idref="${id}"/>`);
    navPoints.push(
      `<navPoint id="n${i}"><navLabel><text>第${i + 1}章 标题</text></navLabel><content src="${href}"/></navPoint>`
    );
    let body: string = `<h1>第${i + 1}章 标题</h1>`;
    for (let p: number = 0; p < parasPerChapter; p++) {
      body += `<p>第${i + 1}章第${p + 1}段：思维力是孩子学习力的基础，&amp;符号与&#8220;引号&#8221;都要正确。<br/>换行后还有一句。</p>`;
    }
    files.push({
      name: 'OEBPS/' + href,
      data: bytesOf(`<html><head><title>t</title><style>p{color:red}</style></head><body>${body}</body></html>`)
    });
  }

  const opf = `<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>流程测试书</dc:title><dc:creator>测试</dc:creator></metadata>
  <manifest><item href="toc.ncx" id="ncx" media-type="application/x-dtbncx+xml"/>${manifest.join('')}</manifest>
  <spine toc="ncx">${spine.join('')}</spine></package>`;
  const ncx = `<?xml version="1.0"?><ncx><navMap>${navPoints.join('')}</navMap></ncx>`;
  const container = `<?xml version="1.0"?><container><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>`;

  return buildZip([
    { name: 'mimetype', data: bytesOf('application/epub+zip'), store: true },
    { name: 'META-INF/container.xml', data: bytesOf(container) },
    { name: 'OEBPS/content.opf', data: bytesOf(opf) },
    { name: 'OEBPS/toc.ncx', data: bytesOf(ncx) }
  ].concat(files));
}

function boxOf(signature: string, fontFamily: string = ''): LayoutBox {
  return {
    fontSizePx: 54, lineHeightPx: 102, widthPx: 900, heightPx: 1400,
    fontFamily: fontFamily, signature: signature
  };
}

test('全流程：EPUB → 章节 → 正文 → 分页，**一个字都不能丢、不能重复**', () => {
  const zip = ZipArchive.parse(makeEpub(5, 4));
  const parsed = parseEpubArchive(zip);
  assert.equal(parsed.chapters.length, 5);
  assert.equal(parsed.title, '流程测试书');

  const paginator: Paginator = new FakePaginator(137);   // 用质数当每页字数，容易暴露边界错误
  let totalChars: number = 0;

  for (let i: number = 0; i < parsed.chapters.length; i++) {
    const text: string = epubChapterTextOf(zip, parsed.chapters[i].href);
    assert.ok(text.length > 0, `第 ${i + 1} 章不该是空的`);
    assert.ok(!text.includes('<p>'), '正文里不该残留标签');
    assert.ok(text.includes('&符号与“引号”都要正确。'), '实体必须被还原');

    const table: PageTable = paginator.paginate(text, boxOf('flow' + i));
    totalChars += text.length;

    // ① 覆盖完整：首页从 0 开始，末页到末尾
    assert.equal(table.pages[0].start, 0, '第一页必须从 0 开始');
    assert.equal(table.pages[table.pages.length - 1].end, text.length, '最后一页必须到文本末尾');

    // ② 无空洞、无重叠
    let joined: string = '';
    for (let p: number = 0; p < table.pages.length; p++) {
      const range: PageRange = table.pages[p];
      assert.ok(range.end > range.start, `第 ${p + 1} 页必须是有效区间`);
      if (p > 0) {
        assert.equal(table.pages[p - 1].end, range.start, '页与页必须首尾相接');
      }
      joined += text.substring(range.start, range.end);
    }
    assert.equal(joined, text, '把所有页拼起来必须与原文完全一致（既不丢字也不重复）');

    // ③ 页码 ↔ 字符偏移 双向一致（进度恢复的正确性）
    for (let p: number = 0; p < table.pages.length; p++) {
      assert.equal(pageOfChar(table.pages, table.pages[p].start), p + 1,
        '每页起始偏移必须反查回这一页');
    }
    // 页内任意偏移都落在该页（末页末尾除外）
    for (let p: number = 0; p < table.pages.length - 1; p++) {
      const mid: number = Math.floor((table.pages[p].start + table.pages[p].end) / 2);
      assert.equal(pageOfChar(table.pages, mid), p + 1);
    }
  }
  assert.ok(totalChars > 0);
});

test('全流程：换排版（字号/字体/视口）后，按字符偏移能原地复原', () => {
  const zip = ZipArchive.parse(makeEpub(2, 6));
  const parsed = parseEpubArchive(zip);
  const text: string = epubChapterTextOf(zip, parsed.chapters[0].href);
  const paginator: Paginator = new FakePaginator(120);

  const before: PageTable = paginator.paginate(text, boxOf('sig-before'));
  assert.ok(before.pages.length >= 2, '这一章至少要能切出 2 页，测试才有意义');
  // 用户读到中间页（挑一个页首偏移，重点验"不跳页"）
  const readTo: number = before.pages[Math.floor(before.pages.length / 2)].start;

  // 换一套参数（相当于用户在设置里改了字号/字体）
  const after: PageTable = paginator.paginate(text, boxOf('sig-after', 'Some Font'));
  assert.notEqual(before.signature, after.signature);

  const page: number = pageOfChar(after.pages, readTo);
  const range: PageRange = after.pages[page - 1];
  assert.ok(readTo >= range.start && readTo < range.end,
    '换排版后，原来的位置必须落在复原出来的那一页里（不许跳页/丢位）');
  assert.ok(text.substring(range.start, range.end).length > 0);
});

test('全流程：空章 / 单页章不崩，进度反查不越界', () => {
  const paginator: Paginator = new FakePaginator(100);

  const empty: PageTable = paginator.paginate('', boxOf('e'));
  assert.equal(empty.pages.length, 1, '空章也要有一页');
  assert.equal(pageOfChar(empty.pages, 0), 1);
  assert.equal(pageOfChar(empty.pages, 9999), 1, '越界偏移必须夹回有效页，不能返回 0 或越界');

  const single: PageTable = paginator.paginate('很短', boxOf('s'));
  assert.equal(single.pages.length, 1);
  assert.deepEqual(single.pages[0], { start: 0, end: 2 }, '不足一页时末页必须精确到文本长度');
});

test('全流程：页表缓存按签名隔离，换签名必须重算（不允许错用旧页表）', () => {
  const zip = ZipArchive.parse(makeEpub(1, 3));
  const parsed = parseEpubArchive(zip);
  const text: string = epubChapterTextOf(zip, parsed.chapters[0].href);
  const paginator: Paginator = new FakePaginator(90);
  const cache: PageCache = new PageCache(4);

  const levels: LayoutLevels = DEFAULT_LEVELS;
  const keyA: string = '0|' + layoutKey(levels, 54, 102, 900, '');
  const keyB: string = '0|' + layoutKey(levels, 54, 102, 900, 'Source Han Serif');

  assert.equal(cache.get(keyA), null);
  cache.put(keyA, paginator.paginate(text, boxOf(keyA)));
  assert.notEqual(cache.get(keyA), null);
  assert.equal(cache.get(keyB), null, '换了字体就是另一个 key，绝不能用旧页表');

  cache.put(keyB, paginator.paginate(text, boxOf(keyB)));
  assert.notEqual(cache.get(keyB), null);
  assert.notEqual(cache.get(keyA), null, '容量 4 里放 2 个签名，两者都该在（不该互相挤掉）');

  // 容量上限仍然生效（真正验老化要压满容量）
  const tiny: PageCache = new PageCache(1);
  tiny.put(keyA, paginator.paginate(text, boxOf(keyA)));
  tiny.put(keyB, paginator.paginate(text, boxOf(keyB)));
  assert.equal(tiny.get(keyA), null, '容量 1 时旧签名必须被淘汰');
  assert.notEqual(tiny.get(keyB), null);
});

test('全流程：章节序号连续、href 唯一（目录跳转依赖这两个前提）', () => {
  const parsed = parseEpubArchive(ZipArchive.parse(makeEpub(7, 1)));
  const seen: Set<string> = new Set<string>();
  for (let i: number = 0; i < parsed.chapters.length; i++) {
    assert.equal(parsed.chapters[i].index, i);
    assert.ok(!seen.has(parsed.chapters[i].href), 'href 不能重复（重复会让两章显示同一内容）');
    seen.add(parsed.chapters[i].href);
    assert.ok(parsed.chapters[i].title.length > 0, '标题不能为空（目录会有空行）');
  }
});
