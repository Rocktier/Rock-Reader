/**
 * 书架规则（分组 + 进度展示）单测
 *
 * 这些是纯逻辑，不含任何 @ohos，所以能在 Node 里跑（CI 无模拟器，这是唯一自动化验证手段）。
 * 防回归重点：脏数据（空分组名、NaN 进度）不许漏到 UI。
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  clampPercent,
  collectGroups,
  filledCells,
  filterByGroup,
  filterByStatus,
  filterByQuery,
  matchesQuery,
  normalizeQuery,
  GROUP_ALL,
  GROUP_UNFILED,
  MAX_GROUP_NAME,
  normalizeGroupName,
  percentText,
  STATUS_ALL,
  STATUS_DONE,
  STATUS_READING,
  STATUS_UNREAD,
  statusOf,
  toShelfItems
} from '../entry/src/main/ets/engine/shelf/ShelfRules.ets';
import { BookRecord, ShelfItem } from '../entry/src/main/ets/common/Types.ets';

function book(id: string, title: string, group: string): BookRecord {
  return {
    id: id,
    title: title,
    author: '',
    format: 'txt',
    path: '/tmp/' + id,
    size: 1,
    addedAt: 0,
    lastReadAt: 0,
    groupName: group
  };
}

test('分组名归一化：去首尾空白、折叠中间空白', () => {
  assert.equal(normalizeGroupName('  技术  '), '技术');
  assert.equal(normalizeGroupName('技术  书'), '技术 书');
});

test('分组名归一化：空串/空白/null 都落到「未分组」', () => {
  assert.equal(normalizeGroupName(''), GROUP_UNFILED);
  assert.equal(normalizeGroupName('   '), GROUP_UNFILED);
  assert.equal(normalizeGroupName(undefined as unknown as string), GROUP_UNFILED);
  assert.equal(normalizeGroupName(null as unknown as string), GROUP_UNFILED);
});

test(`分组名超长（> ${MAX_GROUP_NAME}）截断，避免 chip 撑破布局`, () => {
  const long: string = '一二三四五六七八九十十一十二十三';
  const got: string = normalizeGroupName(long);
  assert.equal(got.length, MAX_GROUP_NAME);
  assert.equal(got, long.substring(0, MAX_GROUP_NAME));
});

test('collectGroups：去重且保持书籍顺序（不排序，否则反直觉）', () => {
  const books: BookRecord[] = [book('a', 'A', '技术'), book('b', 'B', '小说'), book('c', 'C', '技术')];
  assert.deepEqual(collectGroups(books), ['技术', '小说']);
});

test('collectGroups：空分组名归到「未分组」，且只出现一次', () => {
  const books: BookRecord[] = [book('a', 'A', ''), book('b', 'B', '   '), book('c', 'C', '技术')];
  assert.deepEqual(collectGroups(books), [GROUP_UNFILED, '技术']);
});

test('filterByGroup：GROUP_ALL 不过滤；指定分组只留该组；未分组可被筛出', () => {
  const books: BookRecord[] = [book('a', 'A', '技术'), book('b', 'B', ''), book('c', 'C', '小说')];
  assert.equal(filterByGroup(books, GROUP_ALL).length, 3);
  assert.deepEqual(filterByGroup(books, '技术').map((b: BookRecord) => b.id), ['a']);
  assert.deepEqual(filterByGroup(books, GROUP_UNFILED).map((b: BookRecord) => b.id), ['b']);
  assert.equal(filterByGroup(books, '不存在的组').length, 0);
});

test('clampPercent：NaN / 负数 / 越界全部夹回 0~1（脏数据不许漏到 UI）', () => {
  assert.equal(clampPercent(Number.NaN), 0);
  assert.equal(clampPercent(-0.2), 0);
  assert.equal(clampPercent(1.8), 1);
  assert.equal(clampPercent(0.42), 0.42);
});

test('toShelfItems：缺进度记 0；进度为 NaN 也记 0，不许把 NaN 传进进度条', () => {
  const books: BookRecord[] = [book('a', 'A', ''), book('b', 'B', '')];
  const percents: Map<string, number> = new Map<string, number>();
  percents.set('b', Number.NaN);
  const items = toShelfItems(books, percents);
  assert.equal(items.length, 2);
  assert.equal(items[0].percent, 0, '没有进度记录 → 0');
  assert.equal(items[1].percent, 0, 'NaN 进度 → 0');
});

test('toShelfItems：有进度时原样带出（顺序与书籍一致）', () => {
  const books: BookRecord[] = [book('a', 'A', ''), book('b', 'B', '')];
  const percents: Map<string, number> = new Map<string, number>();
  percents.set('a', 0.25);
  percents.set('b', 0.9);
  const items = toShelfItems(books, percents);
  assert.deepEqual(items.map((i) => i.percent), [0.25, 0.9]);
});

test('阅读状态：0 → 未读；中间 → 在读；≥98% → 已读', () => {
  assert.equal(statusOf(0), STATUS_UNREAD);
  assert.equal(statusOf(-0.5), STATUS_UNREAD, '脏数据按未读处理');
  assert.equal(statusOf(Number.NaN), STATUS_UNREAD);
  assert.equal(statusOf(0.01), STATUS_READING);
  assert.equal(statusOf(0.5), STATUS_READING);
  assert.equal(statusOf(0.979), STATUS_READING);
  assert.equal(statusOf(0.98), STATUS_DONE, '留 2% 余量：最后一页读了一半也算读完');
  assert.equal(statusOf(1), STATUS_DONE);
  assert.equal(statusOf(3), STATUS_DONE, '越界进度按已读，不许出现第四种状态');
});

test('filterByStatus：按状态筛选；STATUS_ALL 不过滤', () => {
  const books: BookRecord[] = [book('a', 'A', ''), book('b', 'B', ''), book('c', 'C', '')];
  const percents: Map<string, number> = new Map<string, number>();
  percents.set('a', 0);
  percents.set('b', 0.4);
  percents.set('c', 1);
  const items: ShelfItem[] = toShelfItems(books, percents);

  assert.equal(filterByStatus(items, STATUS_ALL).length, 3);
  assert.deepEqual(filterByStatus(items, STATUS_UNREAD).map((i: ShelfItem) => i.book.id), ['a']);
  assert.deepEqual(filterByStatus(items, STATUS_READING).map((i: ShelfItem) => i.book.id), ['b']);
  assert.deepEqual(filterByStatus(items, STATUS_DONE).map((i: ShelfItem) => i.book.id), ['c']);
});

test('filledCells / percentText：与「继续阅读」卡片的 10 格进度一致', () => {
  assert.equal(filledCells(0, 10), 0);
  assert.equal(filledCells(0.5, 10), 5);
  assert.equal(filledCells(1, 10), 10);
  assert.equal(filledCells(2, 10), 10, '越界进度不许画出 20 格');
  assert.equal(percentText(0.123), '12%');
  assert.equal(percentText(1), '100%');
  assert.equal(percentText(Number.NaN), '0%');
});

// ------------------------------------------------------------------
// 书架搜索（1.0.7 新增）：书名 + 作者子串匹配
// ------------------------------------------------------------------

function bookWith(id: string, title: string, author: string): BookRecord {
  return {
    id: id,
    title: title,
    author: author,
    format: 'epub',
    path: '/tmp/' + id,
    size: 1,
    addedAt: 0,
    lastReadAt: 0,
    groupName: ''
  };
}

test('normalizeQuery：去首尾空白 + 大小写折叠（英文书名不必敲对大写）', () => {
  assert.equal(normalizeQuery('  三体  '), '三体');
  assert.equal(normalizeQuery('Clean Code'), 'clean code');
  assert.equal(normalizeQuery(''), '');
  assert.equal(normalizeQuery(undefined as unknown as string), '');
});

test('matchesQuery：书名或作者任一命中；空查询一律放行', () => {
  const b: BookRecord = bookWith('a', '三体', '刘慈欣');
  assert.ok(matchesQuery(b.title, b.author, '三体'));
  assert.ok(matchesQuery(b.title, b.author, '刘慈欣'), '作者也要能被搜到');
  assert.ok(matchesQuery(b.title, b.author, '刘'), '子串即可，不必输全名');
  assert.ok(!matchesQuery(b.title, b.author, '球状闪电'));
  assert.ok(matchesQuery(b.title, b.author, ''), '空查询 = 不过滤');
  assert.ok(matchesQuery(b.title, b.author, '   '), '纯空白同义');
});

test('matchesQuery：大小写无关（Clean Code / clean code 都能搜到）', () => {
  const b: BookRecord = bookWith('b', 'Clean Code', 'Robert Martin');
  assert.ok(matchesQuery(b.title, b.author, 'clean'));
  assert.ok(matchesQuery(b.title, b.author, 'CLEAN'));
  assert.ok(matchesQuery(b.title, b.author, 'martin'));
});

test('matchesQuery：作者缺失（OPF 里常整个缺席）不许抛异常', () => {
  const b: BookRecord = bookWith('c', '无名书', '');
  assert.ok(matchesQuery(b.title, b.author, '无名'));
  assert.ok(!matchesQuery(b.title, b.author, '随便'));
  // 脏数据更狠一点：title/author 直接是 undefined
  assert.ok(!matchesQuery(undefined as unknown as string, undefined as unknown as string, '任何'));
});

test('filterByQuery：命中保持原有顺序；支持同时打到书名和作者', () => {
  const books: BookRecord[] = [
    bookWith('a', '三体', '刘慈欣'),
    bookWith('b', '球状闪电', '刘慈欣'),
    bookWith('c', '老人与海', '海明威')
  ];
  const percents: Map<string, number> = new Map<string, number>();
  const items: ShelfItem[] = toShelfItems(books, percents);

  assert.deepEqual(filterByQuery(items, '刘慈欣').map((i: ShelfItem) => i.book.id), ['a', 'b']);
  assert.deepEqual(filterByQuery(items, '老').map((i: ShelfItem) => i.book.id), ['c']);
  assert.equal(filterByQuery(items, '托尔金').length, 0, '一个都搜不到要是空数组，不是报错');
});

test('filterByQuery：空查询原样返回同一个数组（省一次拷贝，顺序不变）', () => {
  const books: BookRecord[] = [bookWith('a', 'A', ''), bookWith('b', 'B', '')];
  const items: ShelfItem[] = toShelfItems(books, new Map<string, number>());
  const got: ShelfItem[] = filterByQuery(items, '');
  assert.equal(got.length, 2);
  assert.deepEqual(got.map((i: ShelfItem) => i.book.id), ['a', 'b']);
});
