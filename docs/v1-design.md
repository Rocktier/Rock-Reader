# Rock阅读 / RockReader — v1 设计（Spec）

> **状态**：2026-09-18 定案（党哥确认）
> **归属**：长期记忆，随代码走（应用仓库）。家族规范见 `../../.planning/findings.md`、`../../MEMORY.md`；技术调研见 `../findings.md`「调研结论（2026-09-18）」。

---

## 0. 一句话

鸿蒙上一个**纯本地、零联网**的电子书阅读器：导入本地书 → 解析 → 分页 → 阅读 → 记住进度。
**v1 同时支持 TXT + EPUB**；阅读内核**自研**（Reader Kit 只留可插拔适配器位）；UI 走家族 **Nothing OS 风格**。

---

## 1. 范围

### 1.1 v1 做

| 模块 | 内容 |
|---|---|
| 导入 | 系统文件选择器（`picker.DocumentViewPicker`）→ 拷入沙箱 `filesDir/books/<id>/` |
| 书架 | 网格、继续阅读卡片、删除、进度显示 |
| TXT 解析 | 编码探测（BOM / UTF-8 校验 / GB18030 / UTF-16）+ 章节正则 + 字节偏移索引。**默认章节规则**：行首匹配 `第[一二三四五六七八九十百零〇0-9]+[章回节卷]`；无匹配时按每 3000 字兜底切章 |
| EPUB 解析 | zip 解包 → `container.xml` → OPF → NCX/Nav → XHTML → **段落模型** |
| 排版分页 | `@ohos.graphics.text` 一次 `layoutSync` 取全部行区间 → 页表 |
| 阅读页 | 横滑翻页 + 淡化、字号/行距/边距档位、夜间模式、目录跳转、进度持久化 |
| 设置 | 预设档位**芯片**（**无滑块**）、主题、翻页模式 |
| **广告** | Ads Kit **激励视频**（用户主动触发换增值）+ 书架/设置 **原生卡片**；**默认联网呈现**；**不设广告开关、不做应用内引导**；断网时静默消失 |

### 1.2 v1 明确不做

- 书源 / 抓网 / **上传任何内容或数据**；**核心数据永不出设备**（铁律 3「核心数据不联网」）
- **开屏广告**（拖慢冷启动，撞铁律 1）、**插屏广告**（打断使用）；**广告绝不出现在阅读页**
- PDF（Reader Kit 也不支持）
- **仿真翻页**（贝塞尔 + 阴影渲染，违背"快/小"）
- 云同步、账号、埋点、行为上报、后台常驻
- CSS 解析（EPUB 只认基础标签，样式由我们的排版参数决定）
- 自定义字体导入、TTS、字典、笔记/高亮（v2 候选）

### 1.3 平台

- **只支持 HarmonyOS 6+（单框架）**：`compatibleSdkVersion = 20`、`targetSdkVersion = 24`，单包发布
- 包名 `com.rocktier.rockreader`；应用名 中文「Rock阅读」/ 英文「RockReader」

---

## 2. 架构

**分层原则**：引擎层不依赖 ArkUI —— 这样它既能丢进 `taskpool`，又能在 CI 里用假实现单测（CI 无模拟器，这是唯一的自动化验证手段）。

```
pages/            Shelf │ Reader │ Settings              只渲染与交互，不做计算
viewmodel/        ShelfVM │ ReaderVM                      状态与流程编排
engine/           纯 TS，零 ArkUI 依赖，可 taskpool 可单测
  ├ parser/       BookParser 接口 ─┬ TxtParser
  │                                ├ EpubParser
  │                                └ ReaderKitParser（适配器位·待核实开通后接）
  ├ paginator/    Paginator（graphics.text）+ PageCache
  ├ zip/          ZipReader（@ohos.zlib 优先 → 自研中央目录 + raw inflate）
  └ encoding/     EncodingDetector
data/             BookDb（relationalStore）│ ReaderPrefs（Preferences）
common/           常量、主题 token、错误码
utils/            文件、URI/decodeURI、格式化
```

---

## 3. 核心接口（引擎层契约）

```ts
// ---- 解析 ----
interface BookParser {
  canHandle(file: BookFile): boolean;
  parse(ctx: ParseContext, onProgress?: (p: number) => void): Promise<ParsedBook>;
}

interface ParsedBook {
  meta: BookMeta;                        // 书名/作者/封面路径/格式
  chapters: ChapterIndex[];              // 章节清单
  readChapter(index: number): Promise<Paragraph[]>;
}

interface ChapterIndex {
  index: number;
  title: string;
  startByte: number; endByte: number;    // TXT：字节偏移（随机读）
  spineIndex?: number; href?: string;    // EPUB：书脊索引 + 资源路径
}

interface Paragraph { text: string; kind?: 'title' | 'body' | 'quote'; level?: number }

// ---- 排版 ----
interface Paginator {
  layout(text: string, style: LayoutStyle, viewport: Viewport): Promise<PageTable>;
}

interface LayoutStyle {                 // 只暴露"档位"，不暴露连续值（无滑块铁律）
  fontSizeLevel: 1|2|3|4|5;
  lineHeightLevel: 1|2|3;
  marginLevel: 1|2|3;
  fontFamily: string;
}

interface PageTable {
  signature: string;                    // = hash(字号档,行距档,视口宽,字体,段距)
  pages: Array<{ start: number; end: number }>;   // 字符索引区间（相对本章）
  totalChars: number;
}

// ---- 广告与联网（铁律 3「核心数据不联网」的落点）----
interface AdPolicy {
  hasNetwork(): boolean;                             // 断网 / 无联网权限 → false
  isRewardReady(id: string): boolean;                // 断网时恒为 false（入口直接消失）
  showReward(id: string): Promise<RewardResult>;     // 仅由用户主动触发
  showNative(slot: 'shelf' | 'settings'): void;      // 仅限停顿处，禁止出现在阅读页
}
// 三条纪律：① 阅读页/核心路径零广告 ② 只在停顿处或用户主动触发 ③ 广告是可缺席图层，不参与布局
// 默认态：**联网 + 呈现广告**；**无广告开关、无应用内引导**（"选择权"由系统权限承担）
// 硬要求：断网 / 无权限时**静默降级**——不发请求、不弹提示、不报错、不留空洞，功能与观感完全正常
// 反模式（禁止）：任何「网络异常 / 请检查网络 / 广告加载失败」提示；任何"可关闭广告"的文案或入口
```

**为什么这样切**：`Paginator` 与 `BookParser` 都是接口 → CI 里注入 `FakePaginator`（按固定字符数切页）和 `FakeParser`，就能把"导入→进度→翻页→落库"整条链路测穿；将来若 Reader Kit 可用，只需新增一个 `ReaderKitParser` 实现，UI 与排版层零改动。

---

## 4. 数据模型与存储

| 模型 | 关键字段 |
|---|---|
| `Book` | id, title, author, coverPath, format(text/epub), filePath, size, addedAt, lastReadAt |
| `ChapterIndex` | bookId, index, title, startByte, endByte, spineIndex, href |
| `PageTable` | bookId, chapterIndex, **layoutSignature**, pages(JSON), updatedAt ← 缓存，签名不匹配即失效重算 |
| `Progress` | bookId, chapterIndex, charOffset, percent, updatedAt |

- **关系型数据库**（`relationalStore`）：books / chapters / pagetables / progress
- **Preferences**：排版档位、主题、翻页模式、上次阅读的书 id
- 数据全部在应用沙箱，可导出、可彻底删除

---

## 5. 核心流程

1. **导入**：picker 拿 URI → `decodeURI` → `fileIo` 转沙箱路径 → 按扩展名选解析器 → 建章节索引（后台）→ 落库 → 首章排版预热
2. **打开**：读 `Progress` → 定位章 → 查 `PageTable`：签名匹配**直接用**，否则 `taskpool` 重算本章 → 渲染当前页并**预取 ±2 页**
3. **翻页**：页表命中时**纯索引切换，零计算**；到章尾预取下一章排版
4. **进度**：每 5 页落一次 + `aboutToDisappear` / 页面隐藏时立即落（教训：进程被系统回收时只有正常退出才保存 → 进度会丢）

---

## 6. 性能预算（对齐铁律 1/2）

| 指标 | 做法 |
|---|---|
| 冷启动 ≤ 1s | 首屏只读书架表；非首屏模块懒加载；DB 异步查询 |
| 翻页 < 16ms | 页表命中 → 不做任何测量；排版全在 taskpool |
| 内存 | 只持当前章文本 + ±2 页；大 TXT **不整本入内存**，按字节偏移随机读 |
| 排版成本 | 整章**一次** `layoutSync` 拿全部行区间，**不逐页反复测量** |
| HAP ≤ 5MB | 0 三方库；zip 自研；矢量图标；只留 `arm64-v8a`；开混淆与资源压缩 |

---

## 7. 兜底与降级（每条都必须"能读"，而不是崩）

| 风险 | 兜底 |
|---|---|
| `graphics.text` 在 taskpool 不可用 | 降级为主线程**分块排版**（章节切块 + 时间片让出），保证不卡死 |
| `@ohos.zlib` 不支持 zip 归档 | 自研 zip 中央目录解析 + raw inflate（约 200~400 行） |
| 编码探测失败 | 让用户手选 UTF-8 / GB18030 / UTF-16 |
| EPUB 非标准 / 目录锚点空 | 明确提示"暂不支持"，目录项置灰，**不崩** |
| 超大文件 | 先提示，流式分章建索引（目标支持 50MB+ 单文件 TXT） |
| 排版与渲染不一致 | 测量与展示必须共用同一套 `LayoutStyle` + 视口，禁止两处各写一份参数 |
| **广告 SDK 拖慢冷启动 / 断网时初始化超时** | Ads Kit **延迟初始化**（不在首屏路径）+ **超时上限** + 全链路 `try/catch`；初始化失败或超时**直接当无广告**，绝不阻塞启动（铁律 1 优先于广告收入） |

---

## 8. UI 规范（Nothing OS × 家族品牌）

家族准则第四章已定方向：**黑白单色、克制、点阵、红点点缀**。

**色板**（沿用家族 token）

| Token | 深色（默认） | 浅色 |
|---|---|---|
| 背景 | `#000000` | `#ffffff` |
| 卡片 | `rgba(255,255,255,.03)` | `rgba(0,0,0,.03)` |
| 主强调 | `#ffffff` | `#000000` |
| **红点** | **`#FF4A3D`**（家族红，非 Nothing 官方红） | `#E64537` |
| 灰阶 | `#1A1A1A` `#2D2D2D` `#404040` `#737373` `#A6A6A6` | 同族反色 |

**字体三分工（关键纪律）**
- **正文绝不用点阵字体** —— 可读性优先，用系统字体
- **点阵/等宽只给"数码"**：页码、进度百分比、章节序号、时间
- UI 标题可用等宽大写 + `letter-spacing`

**已确认的三个决定**
1. **书封面 0 圆角**（矩形更像书），卡片/面板圆角 **12**
2. **启动停在书架**，顶部一张「继续阅读」大卡片，**不自动跳书**（沿用准则第十三章"不静默恢复上次文档"的精神）
3. **横滑翻页 + 淡化**，**v1 不做仿真翻页**

**档位 → 实际数值（唯一真源，排版层与 UI 层都必须读这张表，禁止各写一份）**

| 档 | 字号 fontSize | 行距 lineHeight | 页边距 margin |
|---|---|---|---|
| 1 | 14 fp | 1.4 | 12 vp |
| 2 | 16 fp | 1.6 | 16 vp |
| **3（默认）** | **18 fp** | **1.9** | **20 vp** |
| 4 | 20 fp | 2.2 | 24 vp |
| 5 | 22 fp | 2.5 | 28 vp |

- 三个档位（字号/行距/边距）**共用同一序号**，取上表同一行的值；默认全部为 3。
- 表内数值是**唯一真源**：UI 芯片只写序号，排版层按序号查表，不出现第二份数值。

**其它**
- 阅读页**零常驻控件**：点屏幕中间才浮出上下两条细栏
- 底部进度 = Nothing 式**分段进度条**（每 10% 一格），不是连续滑块
- 设置页**一律不用滑块**：字号/行距/边距全用**档位芯片**，2×2 网格排布
- 任何情况下**不出现滚动条**（视觉隐藏 + 内容一屏展示）
- 空态**不放营销文案**
- 动效短促（≈0.2s）；卡片玻璃拟态 + `backdrop-blur`

**广告在 UI 上的纪律（2026-09-18 定稿）**

1. **阅读页永远零广告**——包括"翻页间隙"这种擦边球也不做。阅读体验是产品的命，不参与变现。
2. **只在停顿处或用户主动触发**：书架底部的原生卡片、设置页的「支持开发」入口、由用户点击发起的激励视频。**不做开屏、不做插屏**。
3. **不设广告开关、不做应用内引导**：设置页不放"显示广告 / 关闭广告"开关，也不出现"支持开发"这类文案。**"选择权"由系统权限承担**——用户自行到系统设置切断本应用联网权限即可**彻底无广告，且功能完全不受影响**。
4. **断网静默降级（硬要求）**：无网络 / 无权限时，广告位与激励入口**直接消失**：不发请求、不弹提示、不报错、不留空洞。**绝不出现「网络异常 / 请检查网络 / 广告加载失败」**——用户断网是主动选择，不是故障。
5. **文案规范**：应用内文案只讲品牌承诺（如设置页「核心数据不联网 · 书籍与进度全部在本机处理」），**不提广告、不提联网开关、不做联网计数器**（一旦说明就等于引导用户去关广告）。
6. **合规文本另计**：**隐私政策必须如实写明广告与联网**（法律与审核要求）——这与"应用内不引导"是两件事，前者必做，后者禁止。

---

## 9. 测试策略

| CI 可跑（纯 TS 单测） | CI 跑不了 |
|---|---|
| 编码探测（各编码样本） | UI / 仪器测试（**CI 无模拟器**） |
| 章节正则（多样式标题） | 真机翻页流畅度、续航、内存 |
| zip 中央目录解析 | 系统文件选择器交互 |
| OPF / NCX / Nav 解析 | |
| 页表切片算法（注入假 `LineMetrics`） | |
| `FakeParser` + `FakePaginator` 全链路 | |

**验收门槛**：CI 构建通过 + 上述单测全绿。

---

## 10. 里程碑

| # | 内容 | 验收标准 |
|---|---|---|
| M1 | 手写 hvigor 工程骨架（不用 DevEco 向导）+ CI workflow | CI 上"空工程能构建通过"、产出 HAP Artifacts |
| M2 | 存储 + 导入 + 书架（Nothing 风格先立住） | 能选书、拷进沙箱、落库、书架列出 |
| M3 | **TXT 全链路**：解析 + 分页 + 阅读页 | 50MB TXT 能打开、翻页跟手、进度可恢复 |
| M4 | **EPUB**：zip + OPF + 段落模型（复用 M3 管线） | 标准 EPUB 能读、目录可跳 |
| M5 | 设置 / 目录 / 夜间 / 进度打磨 | 档位切换重排正确、切主题不跳页 |
| M6 | 打磨 + 真机验证 | 冷启动 ≤1s、HAP ≤5MB、翻页无掉帧 |
| **M7** | **广告与联网（可选模块，最后做）**：Ads Kit 激励视频 + 书架/设置原生卡片 + 设置页开关 + 联网计数器 | **默认关闭时不发任何网络请求**；开启后广告不出现在阅读页；关闭后功能无影响 |

EPUB 排在 TXT 之后但同属 v1：M3 的 Paginator / 存储 / 阅读页**全部复用**，M4 只是多一个解析器实现。

---

## 11. 家族合规对照

**铁律对齐**：① 快（页表缓存 + taskpool + 懒加载）；② 小（0 三方库 + 自研 zip + 矢量图标 + 单 arm64）；③ 离线（不申请 INTERNET，无账号/埋点/广告/后台常驻）。

**准则可搬**：品牌宗旨与三承诺、第四章视觉识别（含红点 `#FF4A3D`）、命名与仓库约定、第九章（发版等指令 / ponytail / 文档先于代码 / 不做高成本方案）、第十一章台账机制、**第十四章构建铁律**（构建全走 CI；私有仓库烧 Actions 配额 → Rock-Reader 已 PUBLIC 合适）、7.2 许可证传染。

**明确不适用（需鸿蒙版替代）**：第十三章桌面菜单栏（Tauri 专属，仅继承"启动不静默恢复"精神）、第六章 Windows 商店（→ AppGallery）、第十二章 Paddle 授权（→ 应用市场内购）、7.1 Tauri 技术栈（→ ArkTS）、第八章 cargo 镜像（→ ohpm/npm）。

**许可证红线**：KOReader(GPL-3.0)、Legado(GPL-3.0)、Readest(AGPL-3.0) **只借鉴设计，不抄代码**；Foliate/foliate-js(MIT) 可作参考。

---

## 12. 待核实（阻塞项，按优先级）

1. **`@ohos.graphics.text` 能否在 taskpool 后台线程使用** —— 决定排版是否真能离开 UI 线程（文档签名无 Context 依赖，但 `FontCollection.getGlobalInstance()` 不跨线程、`LineMetrics.runMetrics` 是 `Map` 不易传递）。**需 PoC**。
2. **`@ohos.zlib` 是否支持 zip 归档** —— 决定 EPUB 要不要自研 zip。
3. **`util.TextDecoder` 的 GB18030 支持** —— 决定中文 TXT 覆盖率。
4. **Reader Kit 是否需要 AGC 开通**（影响 M4 是否可走适配器捷径；不影响自研主线）。
5. 家族代码表里 **RockReader 的双字母代码**（拟 `RR`，需与 Rocktier 家族代码表核对后登记）。
6. **Ads Kit 是否需 AGC 开通/签约**；个人开发者的广告结算门槛与周期。
7. **Ads Kit 引入后的 HAP 体积实际增量**（验证"系统级 Kit 不占体积"的结论，与铁律 2 对齐）。
8. 华为审核对**广告位、隐私弹窗、个人信息告知（含未成年人保护）**的具体要求。
9. 若走「激励视频换增值」：可交换的增值物怎么定（候选：高级排版档位 / 主题包 / 字体包）——不能动"能不能读书"这条底线。

---

## 13. 风险

| 风险 | 应对 |
|---|---|
| EPUB 复杂度超预期（zip + OPF + XHTML 三块） | 解析器接口隔离：先只保证标准 EPUB，异常一律降级提示；必要时启用 Reader Kit 适配器 |
| 本机无鸿蒙环境，问题在 CI 之后才暴露 | 逻辑尽可能挤进纯 TS 单测；工程骨架先跑通 CI 再堆功能 |
| 排版精度（标点、中英混排）需真机反复调 | 排版参数全部走档位与集中配置，便于真机一次性调优 |

---

*本 spec 是 v1 的唯一设计真源；改动先改本文档，再改代码。*
