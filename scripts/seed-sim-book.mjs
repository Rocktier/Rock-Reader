/**
 * 模拟器造书工具：把一本本地 TXT「变成」Rock阅读 书架上的书
 *
 * 为什么需要它（2026-10-27 实测踩出来的）：
 *   模拟器上没法用文件选择器把书导进来 ——
 *   ① `aa start -U file://...` 会被 AMS 做 URI 权限校验，无授权时**静默剥离** want.uri；
 *   ② 隐式 want（viewData）带 uri 在这台镜像上不命中（module.json5 注释里的对照矩阵：带 uri 的一律不命中）；
 *   ③ 媒体存储 /storage/media/** 被 SELinux 判为只读，shell 写不进去，文件选择器也看不见。
 *   ⇒ 唯一可行的办法：**直接造出「导入完成后的现场」** —— 书的文件 + books 行 + chapters 行。
 *
 * 关键设计：**切章规则绝不手写复刻**，直接跑产品自己的源码
 *   （esbuild 把 .ets 当 TS 编译，ChapterSplitter 是零鸿蒙依赖的纯逻辑），
 *   所以生成出来的 start_char/end_char 与应用导入时**逐字节一致**。
 *
 * 用法：
 *   node scripts/seed-sim-book.mjs <本地TXT> [书名] [作者] [bookId]
 *   → 在 seed-out/ 下生成 seed.sql（含 books + chapters 行）与切分摘要
 *
 * 设备侧怎么落地（shell 能做、且应用读得到）：
 *   1. 把书写进应用沙箱 —— 用 sqlite3 的 writefile（比 cat 权限高，能写应用私有目录）：
 *        python -c "..."            # 生成 x'十六进制' 的 writefile 语句
 *        hdc file send write.sql /data/local/tmp/write.sql
 *        hdc shell "cat /data/local/tmp/write.sql | sqlite3 :memory:"
 *        ⇒ 文件落在 /data/app/el2/100/base/<bundle>/haps/entry/files/<name>
 *      ⚠️ 路径要用**应用视角**：/data/storage/el2/base/haps/entry/files/<name>
 *   2. 执行 seed.sql：
 *        hdc file send seed.sql /data/local/tmp/seed.sql
 *        hdc shell "cat /data/local/tmp/seed.sql | sqlite3 <db路径>"
 *      ⚠️ 必须用 `cat ... | sqlite3` 管道；`sqlite3 <db> < file` 不生效（只执行第一行）。
 *      ⚠️ 写库前先 `aa force-stop` 应用，并删掉 -wal/-shm/-dwr/-compare 残件。
 */
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

// esbuild 装在本仓库里，而脚本可能被从别处调用 —— 用 require 锚定过来
const require = createRequire(import.meta.url);
const { build } = require('esbuild');

// 仓库根目录（本脚本在 scripts/ 下）—— 生成的入口文件要用**绝对路径**引产品源码，
// 否则从别的目录跑就会找不到（入口文件落在 seed-out/ 里）。
// 注意：Windows 盘符路径里的反斜杠会让 TS 的 import 语句解析失败，统一换成正斜杠。
const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..').replace(/\\/g, '/');

const argv = process.argv.slice(2);
if (argv.length < 1) {
  console.error('用法: node scripts/seed-sim-book.mjs <本地TXT> [书名] [作者] [bookId]');
  process.exit(1);
}
const srcTxt = resolve(argv[0]);
const title = argv[1] ?? srcTxt.split(/[\\/]/).pop();
const author = argv[2] ?? '';
const bookId = argv[3] ?? 'b_sim01';

const OUT_DIR = resolve('seed-out');
mkdirSync(OUT_DIR, { recursive: true });

// ---- 1. 用 esbuild 打包「跑产品切章代码」的入口 ----
const entry = join(OUT_DIR, '_entry.ts');
writeFileSync(entry, `
import { splitChapters, chapterSliceOf } from '${REPO_ROOT}/entry/src/main/ets/engine/text/ChapterSplitter';
import { readFileSync, writeFileSync } from 'node:fs';
const bytes = readFileSync(${JSON.stringify(srcTxt)});
// 应用侧走 detectEncoding → decodeBytes；本工具只处理 UTF-8 文本，
// 与 detectEncoding 对合法 UTF-8 的判定一致。
const text = new TextDecoder('utf-8').decode(bytes);
const chapters = splitChapters(text);
const out = chapters.map((c) => ({
  index: c.index, title: c.title,
  startChar: c.startChar, endChar: c.endChar,
  startByte: c.startByte, endByte: c.endByte,
  text: chapterSliceOf(text, c.startChar, c.endChar)
}));
writeFileSync(${JSON.stringify(join(OUT_DIR, '_chapters.json'))}, JSON.stringify({ totalChars: text.length, chapters: out }));
`);

const outfile = join(OUT_DIR, '_entry.mjs');
await build({
  entryPoints: [entry],
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node18',
  outfile,
  loader: { '.ets': 'ts' },
  resolveExtensions: ['.ets', '.ts', '.mjs', '.js', '.json'],
  logLevel: 'warning'
});
execFileSync(process.execPath, [outfile], { stdio: 'inherit' });

// ---- 2. 读回切分结果，生成 SQL ----
const data = JSON.parse(readFileSync(join(OUT_DIR, '_chapters.json'), 'utf-8'));
const size = readFileSync(srcTxt).length;
const q = (v) => `'${String(v).replace(/'/g, "''")}'`;

const sql = [
  `DELETE FROM books WHERE id = ${q(bookId)};`,
  `DELETE FROM chapters WHERE book_id = ${q(bookId)};`,
  `INSERT INTO books(id,title,author,format,path,size,added_at,last_read_at,group_name) VALUES(` +
    `${q(bookId)},${q(title)},${q(author)},${q('txt')},${q('<把这里换成设备上的书路径>')},` +
    `${size},${Date.now()},${Date.now()},${q('')});`
];
for (const c of data.chapters) {
  sql.push(
    `INSERT INTO chapters(book_id,idx,title,start_char,end_char,start_byte,end_byte,href,char_count) VALUES(` +
    `${q(bookId)},${c.index},${q(c.title)},${c.startChar},${c.endChar},${c.startByte},${c.endByte},${q('')},0);`
  );
}
writeFileSync(join(OUT_DIR, 'seed.sql'), sql.join('\n') + '\n');

// ---- 3. 同时生成 writefile 语句（把书本体送进应用沙箱用） ----
const hex = readFileSync(srcTxt).toString('hex');
writeFileSync(
  join(OUT_DIR, 'write.sql'),
  `select writefile('<把这里换成设备上的书绝对路径>', x'${hex}');\n`
);

console.log('--- 切分结果 ---');
console.log(`总字符 ${data.totalChars} / 章节 ${data.chapters.length} / 字节 ${size}`);
for (const c of data.chapters.slice(0, 3)) {
  console.log(`  [${c.index}] ${c.title}  chars ${c.startChar}-${c.endChar}  ${c.text.length}字`);
}
if (data.chapters.length > 6) {
  for (const c of data.chapters.slice(-3)) {
    console.log(`  [${c.index}] ${c.title}  chars ${c.startChar}-${c.endChar}  ${c.text.length}字`);
  }
}
console.log('产物:', join(OUT_DIR, 'seed.sql'), '与', join(OUT_DIR, 'write.sql'));
console.log('提示: 两份 SQL 里的路径占位符都要替换成设备上的真实绝对路径。');
