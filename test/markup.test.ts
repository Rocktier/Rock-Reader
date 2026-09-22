/**
 * HTML / Markdown / FB2 的纯逻辑（转纯文本 + 切章）
 *
 * 只测 `engine/text/Markup.ets` —— 那边不碰 fileIo，能在 CI 里跑。
 * IO 部分（MarkupParser）拖了 fileIo，只能靠真机。
 */
import { test } from 'node:test';
import assert from 'node:assert';
import {
  decodeEntities,
  fb2ToMarkdownish,
  htmlToMarkdownish,
  splitMarkdownChapters
} from '../entry/src/main/ets/engine/text/Markup.ets';

test('htmlToMarkdownish：script / style / 注释不进正文，h1 变标题行，br 变换行', () => {
  const html: string = '<html><head><title>书名</title><style>body{color:red}</style></head>' +
    '<body><script>alert(1)</script><!-- 注释 --><h1>第一章 雨夜</h1>' +
    '<p>第一段<br>第二行</p></body></html>';
  const out: string = htmlToMarkdownish(html);
  assert.ok(out.indexOf('alert') < 0, 'script 不该进正文');
  assert.ok(out.indexOf('color:red') < 0, 'style 不该进正文');
  assert.ok(out.indexOf('注释') < 0, 'HTML 注释不该进正文');
  assert.ok(out.indexOf('# 第一章 雨夜') >= 0, 'h1 必须变成 Markdown 标题行（否则切不了章）');
  assert.ok(out.indexOf('第一段\n第二行') >= 0, 'br 必须变成换行');
});

test('htmlToMarkdownish：实体解码后不留标签', () => {
  const out: string = htmlToMarkdownish('<p>a&amp;b&nbsp;c&#39;d</p>');
  assert.ok(out.indexOf('a&b c\'d') >= 0, `实体没解干净：${out}`);
  assert.ok(out.indexOf('<p>') < 0, '标签必须剥干净');
});

test('decodeEntities：命名实体与数字实体；不成实体的原样留下', () => {
  assert.equal(decodeEntities('&amp;&lt;&gt;&quot;&#39;'), '&<>"\'');
  assert.equal(decodeEntities('&#65;&#x42;'), 'AB');
  assert.equal(decodeEntities('&#'), '&#', '孤立的 &# 不该被吃掉');
  assert.equal(decodeEntities('a&#99999999999;b'), 'a&#99999999999;b', '超长数字不是实体');
});

test('splitMarkdownChapters：按标题切章，拼起来必须与原文逐字一致', () => {
  const text: string = '前言内容\n\n# 第一章 雨夜\n正文一\n\n## 小节\n正文二\n';
  const chapters = splitMarkdownChapters(text);
  assert.ok(chapters.length >= 3, `至少 3 章（前言+两章），实际 ${chapters.length}`);

  let joined: string = '';
  for (const c of chapters) {
    joined += text.substring(c.startChar, c.endChar);
  }
  assert.equal(joined, text, '所有章拼起来必须等于原文（不丢字、不重复）');
  assert.equal(chapters[chapters.length - 1].endChar, text.length, '最后一章要收到文末');
});

test('splitMarkdownChapters：一个标题都没有 → 兜底硬切（不白导入）', () => {
  const text: string = 'a'.repeat(7000);
  const chapters = splitMarkdownChapters(text);
  assert.ok(chapters.length >= 2, '没标题也必须切出多章');
  assert.equal(chapters[0].startChar, 0);
  assert.equal(chapters[chapters.length - 1].endChar, text.length);
});

test('fb2ToMarkdownish：section 标题变标题行，p 变段落，嵌套标签剥掉', () => {
  const xml: string = '<FictionBook><description><title-info><book-title>某书</book-title>' +
    '</title-info></description><body><section><title><p>第一章</p></title>' +
    '<p>这是<emphasis>强调</emphasis>的正文</p></section></body></FictionBook>';
  const out: string = fb2ToMarkdownish(xml);
  assert.ok(out.indexOf('# 第一章') >= 0, 'FB2 的 title 必须变成标题行');
  assert.ok(out.indexOf('这是强调的正文') >= 0, '内层的 emphasis 要剥掉、文字保留');
  assert.ok(out.indexOf('<p>') < 0, '标签必须剥干净');
  // 守卫：`<title-info>` 是 FB2 的**元数据**块，不能被当成章节标题
  // （写成 `<title\b[^>]*>` 就会中招 —— 整段 description 被吞掉，章名反而没了）
  assert.ok(out.indexOf('某书') < 0, 'description 里的 book-title 不该进正文');
});
