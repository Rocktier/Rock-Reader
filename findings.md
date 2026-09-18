# Findings — Rock阅读（RockReader）

> 应用级技术台账。家族铁律与工程约定在 `..\planning\findings.md`（harmony-docs 仓库）。

## 产品边界（已定；**2026-09-18 党哥修订联网口径**）
- **口号：核心数据不联网** —— 书籍、进度、设置等核心数据**永不出设备**；**断网时功能 100% 可用**，不降级、不弹窗骚扰。
- **联网只为广告**：申请 `INTERNET` **仅用于 Ads Kit 广告**；**默认联网、默认呈现广告**；**不设广告开关、不在应用内告知可去广告**（党哥 2026-09-18 定）。想无广告的用户自行到系统设置切断本应用联网权限——**切断后功能完全不受影响**。
- **广告三条纪律**：① 阅读页／核心使用路径**绝不出现广告**；② 只出现在停顿处或用户主动触发的位置；③ **广告是可缺席图层，不参与布局**（缺席不留空洞）。
- **断网静默降级（硬要求）**：无网络/无权限时**不弹提示、不报错、不显示"网络异常"**，广告位与激励入口直接消失，功能与观感完全正常。
- **明确不做**：开屏广告（拖慢冷启动，撞铁律 1）、插屏广告（打断使用）、埋点、行为上报、后台常驻。
- **仍不做书源、不抓网、不上传任何内容或数据**（书源生态侵权，且与"核心数据不联网"正面冲突）。
- 对标安卓「阅读」的**阅读体验**（排版 / 翻页 / 书架 / 目录 / 净化），**不碰**它的书源生态（原项目因侵权已删库，见家族 findings §6）。
- 格式：首版 **TXT**，随后 **EPUB**；PDF 不做。
- 目标系统：**只支持 HarmonyOS 6+（单框架）** —— `compatibleSdkVersion = 20`（覆盖率约 99%），`targetSdkVersion = 24`（最新）。**HarmonyOS 4 及更早已放弃**（党哥 2026-09-18 定），所以只有一个包、一套 SDK、不做 API 差异分支。

## 关键能力对照（ArkTS Kit，版本可用性待实测）
| 需求 | 候选 API | 备注 |
|---|---|---|
| 选书导入 | `@ohos.file.picker`（DocumentViewPicker） | 拿 URI，授权可能是临时的 |
| 文件读写 | `@ohos.file.fs` | 支持按 offset 随机读，适合大文件 |
| 沙箱路径 | `context.filesDir` / `cacheDir` | 书籍拷进 `filesDir/books/` |
| 解压 EPUB | `@ohos.zlib` | ⚠️ 需验证是否支持 zip 归档（可能只有 raw deflate） |
| 解析 OPF/NCX | `@ohos.xml`（XmlPullParser） | EPUB 目录与元数据 |
| 文本测量/分页 | ~~`@ohos.measure`（measureText）~~ → **`@ohos.graphics.text`**（`ParagraphBuilder` + `Paragraph.layoutSync` + `getLineMetrics`，API 12+，部分 20+） | ✅ 2026-09-18 查证：**一次排版即可拿到每行 `startIndex`/`endIndex`**，不必逐段反复测量（详见「调研结论 B」） |
| 组件内布局信息（备选） | `TextController.getLayoutManager()`（12+）→ `LayoutManager.getLineCount()` / `getLineMetrics(i)` | 与上一行同一套 `LineMetrics`（单位 **px**，非 vp） |
| 解析 + 排版 + 翻页（整包可选） | `@kit.ReaderKit`（`bookParser` / `ReadPageComponent` / `readerCore`，**API 16+**） | ⚠️ 仅中国大陆 + 真机（无模拟器）+ 不支持 PDF；是否需 AGC 开通**待核实**（详见「调研结论 A」） |
| 编码解码 | `util.TextDecoder` | ⚠️ 需验证是否支持 GBK（中文 TXT 大头） |
| 目录/进度存储 | `@ohos.data.relationalStore` | 章节索引、阅读进度 |
| 轻量配置 | `@ohos.data.preferences` | 字号、主题等设置 |
| 并发 | `@ohos.taskpool` / `@ohos.worker` | 导入、解析、分页丢后台 |
| 自定义字体 | `@ohos.font`（registerFont） | 用户导入字体 |

## 设计要点（对齐三条铁律）
**快**
- 大 TXT 绝不整体读入内存；导入时扫描一次建"章节/页 → 字节偏移"索引落库，之后按 offset `fs.read` 随机访问。
- 只缓存当前 ±2 页；导入/解析/分页全走 `taskpool`，UI 线程只渲染。

**小**
- 渲染用 ArkUI `Text`/`Span` 自绘分页，**不用 Web 组件**。
- EPUB 若 `@ohos.zlib` 不支持 zip 归档，自己写最小 zip 中央目录解析 + raw inflate（约 200~400 行），优先于引三方库。
- 图标用矢量；so 只留 `arm64-v8a`；开混淆与资源压缩。HAP 预算 **≤5MB**。

**离线**
- `module.json5` 不声明 `ohos.permission.INTERNET`。
- 无账号、无云同步、无埋点统计、无广告、无后台常驻。
- 全部数据只在应用沙箱，支持导出与彻底删除。

## 三个待验证 spike（按风险排序）
> ⚠️ **本机没有鸿蒙开发环境，无法本地实测**。策略：先查官方文档，再**按最坏情况设计**，实测等首次 CI 构建 / 真机到位后回填。
> 2026-09-18 文档查证结果见下方「spike 结果」表：zip 与 GBK **大概率都有官方能力**，因此不再一上来就自己造轮子，但兜底路径照旧保留。

1. **zip / EPUB 解压**：`@ohos.zlib` 能否直接处理 zip 容器
   - 最坏假设：不支持 zip 归档（只有 raw deflate）→ **自己写最小 zip 中央目录解析 + raw inflate**（约 200~400 行，符合"不引三方库"）
2. **GBK 解码**：`util.TextDecoder` 是否支持 GBK / GB18030
   - 最坏假设：不支持 → 首版先支持 UTF-8（含 BOM 识别）+ **编码手动选择**，GBK 映射后续自实现或按需加
3. **文本测量与分页**：`measureText` 可用性与精度
   - 最坏假设：能力有限 → 代码留兜底：测量失败退化为"按字符数估算分页"，保证能读，排版精度后调

> 这三个 spike 的结果直接写回本文件的「spike 结果」章节。

## spike 结果
> 「文档查证」= 2026-09-18 查官方文档/社区资料得出的倾向结论；「实测」= 等首次 CI 构建 / 真机后回填。

| 项 | 文档查证 | 采用的方案 | 兜底 | 实测 |
|---|---|---|---|---|
| zip / EPUB 解压 | **倾向可用**：`@ohos.zlib` 官方就叫 Zip 模块，提供 `compressFile` / `decompressFile`；官方架构指南还有「解压 Zip 文件」示例（`@ohos.zlib` + `@ohos.worker`） | 先用官方能力把 EPUB **整包解压到沙箱缓存目录**，再解析 OPF/NCX | 若不支持多条目归档 → 自写最小 zip 中央目录解析 + raw inflate（200~400 行） | ⬜ 未实测 |
| GBK 解码 | **倾向可用**：多篇资料显示 `util.TextDecoder` 支持多种编码格式，含 **GB18030**（向下覆盖 GBK）；`fs.readTextSync` 只支持 UTF-8，所以要用 TextDecoder | 用 `new util.TextDecoder('gb18030')` 解中文 TXT | 若不支持 → 首版仅 UTF-8（含 BOM 识别）+ 编码手动选择，GBK 后续自实现映射 | ⬜ 未实测 |
| 文本测量与分页 | 未查证 | 用 `@ohos.measure` 的 `measureText` 做逐段测量分页 | 测量能力不足 → 退化为按字符数估算分页，保证能读，精度后调 | ⬜ 未实测 |

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| ~~首版只做 TXT~~ → **v1 同时上 TXT + EPUB**（党哥 2026-09-18 拍板） | 不想分两次发；代价：zip 解包 + OPF/NCX 解析 + XHTML→段落模型 一起进 v1，见下方「未定/风险」 |
| **阅读内核自研为主**（党哥 2026-09-18 拍板） | UI 完全可控、不受地区限制、不依赖 AGC 审批；`graphics.text` 让分页成本大降（调研结论 B）。`Reader Kit` 只保留**可插拔适配器**位，等开通条件核实后再接 |
| **解析器做成接口 + 多实现**（`TxtParser` / `EpubParser` / `ReaderKitParser`） | 解析层可替换：若 Reader Kit 可用，EPUB 直接换适配器实现，UI 与排版层零改动 |
| **排版抽象成 `Paginator` 接口**（输入 text+排版参数+视口 → 输出页表） | 便于注入 FakePaginator 做 CI 单测；也便于将来换 Reader Kit 或调优 |
| 自绘分页而非 Web 组件 | 小 + 快 |
| 字节偏移索引 + 随机读 | 大文件秒开、低内存 |
| 页表按 `layoutSignature`（字号档+行距档+视口宽+字体）缓存 | 排版结果可复用；签名不变时翻页零计算 |

## Resources
- 华为开发者文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/
- 家族 findings（版本/环境/CI）：`..\planning\findings.md`

---

# 调研结论（2026-09-18）：技术选型与设计方向

## A. 官方 Reader Kit（阅读服务）—— 鸿蒙自带的整套阅读内核

来源：华为官网 `reader-introduction` / `reader-api`（API 参考更新 2026-09-14）、官方示例 `HarmonyOS_Samples/readerkit_samplecode_arkts` + `ReaderKit_Codelab_ArkTS`、掘金实操笔记（2025-06-28）、51CTO 星光计划手记（2026-04-27）。

| 维度 | 事实 |
|---|---|
| 三个核心模块 | `bookParser`（解析）、`ReadPageComponent`（阅读页组件）、`readerCore`（控制器）——全部 `import from '@kit.ReaderKit'`，**随 SDK 提供，无需 ohpm 安装** |
| 能力 | 解析书名/作者/封面/目录/正文；txt 与富文本（html+css，W3C）排版；翻页动效走 **OpenGL/GPU**；进度感知；字体/字号/行距/背景/夜间模式 |
| 支持格式 | **txt、epub、mobi、azw、azw3**（**不支持 PDF**） |
| 版本/设备 | **API 16（HarmonyOS 5.0.4）及以上**；Phone / Tablet / PC-2in1；**真机才行，模拟器不支持** |
| 地区 | **仅中国大陆**（港澳台及海外不支持） |
| 硬限制 | ① **只支持应用沙箱内的本地文件**（不同书放不同目录）——与"纯本地离线"天然吻合；② 单文件 **≤300MB**；③ 无 DRM；④ 非标准格式可能解析失败需兜异常；⑤ 排版与交互**必须配套用 `ReadPageComponent`** |
| 实测踩坑 | 封面空白=`spineIndex` 写错；目录缩进错=`catalogLevel`；进页面黑屏=`pageShow` 未回调就关 loading；字体不生效=未注册 `resourceRequest`；白底白字=漏关 `nightMode`；退出必须 `off(...)` + **`releaseBook()`** 否则泄漏；`picker` 返回的 URI 要 `fileIo` 转沙箱路径 + `decodeURI` |
| 性能口径 | 拖动/翻页走 GPU；官方架构指南推荐 `controller.init()` 与 `getBookParserHandler()` 用 `Promise.all` 并行 |
| ⚠️ 待核实 | **是否需要 AGC 开通/签约才能用**——官方文档是 SPA 抓不到正文，两篇实操文章都没提。必须在浏览器里打开 `reader-kit-guide` 确认，或首次 CI/真机时验证 |

**取舍**：省掉解析+排版+翻页三大块（有作者称开发工时压到 1/3），HAP 也更小（能力在系统里）。代价是**阅读页外观受 `ReaderSetting` 约束**，做不出家族自己的排版语言；且**仅中国大陆可用**（Rocktier 面向全球，是硬伤）。

## B. 自研排版：比原假设快得多（推翻 2026-09-18 早前的判断）

原台账假设"只能用 `@ohos.measure` 逐段测量 + `BreakIterator` 双向收敛"——那是社区普遍的写法，也是公认的性能瓶颈（掘金作者原话：反复测量是最大优化空间）。

**查证后的事实**（OpenHarmony 官方文档 `js-apis-graphics-text.md` / `ts-text-common.md` / `ts-basic-components-text.md`）：

1. **`@ohos.graphics.text`（ArkGraphics2D，API 12+）** 提供真正的排版对象：
   `FontCollection` → `ParagraphBuilder(paragraphStyle, fontCollection)` → `addText()` → `build()` → **`layoutSync(width)`** → `getLineMetrics()`。
2. **`getLineMetrics()` 直接返回每行 `startIndex` / `endIndex`**（外加 `height`/`topHeight`/`baseline`/`width`/`left`/`runMetrics`，**单位 px**）。
   → **一次排版 = 整章每行的字符区间**，分页只需"按行数切页 + `substring`"，**不存在反复测量的循环**。这就是 Android `StaticLayout` 的等价能力。
3. 组件侧同样可拿：`Text(content, {controller})` → `controller.getLayoutManager()`（12+）→ `getLineCount()` / `getLineMetrics(i)`。
4. API 24+ 还有 `layoutWithConstraints(size)` 直接返回"能容纳的字符范围"（正是社区求而不得的反向测量）；20+ 起有 CJK `autoSpace`、首行标点压缩（23+）、段落缓存（系统默认开启）等排版细节。
5. ⚠️ **辟谣（重要）**：网上大量文章（含某 CSDN「深度解析」）写的 `onTextLayout` 回调、`TextLayoutResult` 类型、`ReaderController`/`BookMetaManager` 等 API **在官方 ArkUI 文档中不存在**，属 AI 生成的臆造内容。**以官方 ArkUI/ArkGraphics2D 文档与官方示例为准**，别照抄博客代码。

**结论**：自研分页成本大幅下降，"极致快"可以靠 `layoutSync` 一次排版 + 页表缓存 + 章节级懒排版（照抄 KOReader 的思路）实现。

## C. 外部开源阅读项目（只借鉴设计，注意许可证）

| 项目 | 栈 / 许可 | 值得学的 | 不能碰的 |
|---|---|---|---|
| **KOReader** | Lua + crengine(C++) / GPL-3.0 | 章节级懒排版、页面缓存与预读、超多排版选项的组织方式、e-ink 思路 | 代码（GPL 传染，家族要考虑闭源/授权变现）；C++ 生态 |
| **Legado「阅读」/ legado-Harmony** | Android Java / 鸿蒙版已**闭源只发 HAP** / GPL-3.0 | 阅读体验对标清单：排版、翻页模式、目录、替换净化、进度 | 书源生态（侵权，见家族 findings §6）；代码（GPL-3.0） |
| **Readest** | Next.js + Tauri + foliate-js / **AGPL-3.0** | "多格式 → 统一排版管线"的架构观、阅读尺/专注模式等体验点子 | 代码（AGPL 传染）、WebView 渲染路线（重、慢） |
| **Anx Reader** | Flutter / 开源 | **极简沉浸式 UI**、无广告无推广的产品边界感 | 代码（技术栈不同） |
| **Foliate / foliate-js** | GTK / JS / **MIT** | EPUB 解析与阅读器交互设计（MIT 相对友好，可作参考） | — |
| **Koodo Reader** | Electron / 开源 | 书架信息架构（网格/列表、进度与标签） | Electron 体量 |
| **华为官方 ReaderKit 示例** | ArkTS | **最直接可搬运的 ArkTS 写法**（导入→解析→目录→设置→翻页） | — |

## D. UI 方向：Nothing OS × 家族品牌（落到阅读器）

家族《通用准则》第四章本来就写着「视觉方向：**Nothing OS 启发——黑/白单色、克制、点阵、红点点缀**」，本次要求与家族品牌方向一致。参考 Nothing 设计规范与本机家族 token：

- **色板**：直接沿用家族 token——背景 `#000`／昼 `#fff`、卡片 `rgba(255,255,255,.03)`、主强调白/黑、**红点 `#FF4A3D`**（不用 Nothing 官方的纯红 `#FF0000`，家族红才是签名）。灰阶走 5 级（`#1A1A1A`/`#2D2D2D`/`#404040`/`#737373`/`#A6A6A6`）。
- **字体三分工**：**正文绝不用点阵**（可读性优先，用系统字体/思源）；**点阵或等宽只用于数码与眉标**——页码、进度百分比、章节序号、时间；UI 标题可用等宽大写 + `letter-spacing`。
- **阅读页**：极致克制——正文之外**零常驻控件**；点屏幕中间才浮出上下两条细栏；底部进度做 Nothing 式**分段进度条**（每 10% 一格）而非连续滑块。
- **书架**：黑白网格 + 封面；元数据（页数/进度/时间）用等宽小字；空态不放营销文案（家族 Pic2Webp 已定）。
- **设置**：**一律不用滑块**（家族铁律，Pic2Webp 已确立）——字号/行距/页边距全改**预设档位芯片**；芯片排 2×2 网格避免怪异换行。
- **交互**：无滚动条（视觉隐藏）、一屏展示、卡片圆角 12、动效短促（≈0.2s）。
- **已定**（党哥 2026-09-18）：书封面 **0 圆角**（矩形更像书），卡片/面板 12 圆角。

## E. 待核实清单（写进 task_plan，别忘）

1. Reader Kit **是否需要 AGC 开通/签约**（决定它能不能作为基础依赖）。
2. `@ohos.graphics.text` 能否在 **taskpool/worker 后台线程**使用——文档签名无 Context 依赖，但 `FontCollection.getGlobalInstance()` 不跨线程、`LineMetrics.runMetrics` 是 `Map` 不易传递；需 PoC 验证（本机无环境，等首次 CI/真机）。
3. `TextDecoder` 的 GB18030 支持、`@ohos.zlib` 的 zip 归档支持——原三个 spike 仍然有效。
4. 家族代码表里 **RockReader 的双字母代码**（如 `RR`）需与 Rocktier 家族代码表核对后登记。

---

# M1 结果（2026-09-18）：工程骨架 + CI 构建通过 ✅

| 项 | 结果 |
|---|---|
| CI | GitHub Actions **全绿**（仓库 PUBLIC，不耗私有额度）：`纯逻辑单测` + `ArkTS 编译校验 → HAP` |
| 产物 | `entry/build/ci/outputs/default/entry-default-unsigned.hap` = **90 KB**（未签名；铁律 2 预算 ≤5MB 绰绰有余） |
| 编译校验方案 | 用**公开免登录**的 OpenHarmony SDK（apiVersion 20）+ **双 product**（`default`=HarmonyOS 正式包 / `ci`=OpenHarmony 编译校验），同一份源码 |
| 构建链 | `npm i @ohos/hvigor@6.0.6 @ohos/hvigor-ohos-plugin@6.0.6` → `node node_modules/@ohos/hvigor/bin/hvigor.js assembleHap`（**不用**仓库里的 hvigorw 包装器，它会假绿） |
| 单测 | `npm test`：esbuild 把 `.ets` 当 TS 编译 + `node:test`，**17/17 绿**（本地与 CI 都能跑） |
| 引擎落地 | `entry/src/main/ets/engine/`：`text/Encoding.ets`、`text/ChapterSplitter.ets`、`paginator/PageTableBuilder.ets`（纯逻辑、零 ArkUI 依赖，可进 taskpool） |

**踩坑记录**：7 个坑（假绿包装器 / `type:module` 冲突 / compileSdkVersion / 许可证联网检查 / 大小写同名 env 键 / 五个组件必须齐全 / OpenHarmony 设备类型是 `default`）已全量写入**家族** `findings.md` §13，后续鸿蒙应用直接复用。

**单测当场抓到的两个真实 bug**（已修）：
1. 首个章标题之前的内容（书名/前言）会被丢掉 → 改为单独成「前言」章；
2. `split('\n')` 尾部空元素导致字符偏移虚增 1 → 按剩余长度夹紧。

**遗留**：正式 HarmonyOS 包（`default` product）仍需一次性用华为账号下载 command-line-tools 才能在 CI 出；且拿到真机前也装不了（签名要绑定 UDID，见家族 findings §10）。

---

# M2 / M3 结果（2026-09-18，同日）

## 许可证审查（党哥要求：借鉴前先查、规避法律风险）

| 来源 | 许可证 | 结论 |
|---|---|---|
| 华为官方 `readerkit_samplecode_arkts` | **Apache-2.0** | ✅ 可借鉴（保留版权声明 + 标注修改）。已用于 `fileIo` 用法：`openSync` / `copyFile(fd, dst)` / `statSync` |
| `johnfactotum/foliate-js` | **MIT** | ✅ 可借鉴（EPUB 解析参考，M4 用） |
| `waylau/harmonyos-tutorial` | **无 LICENSE = 保留所有权利** | ❌ **只看 API 形态，一行代码不抄** |
| KOReader / Legado / Readest | GPL-3.0 / GPL-3.0 / AGPL-3.0 | ❌ 传染性许可，只借鉴设计 |

## 本批次抓到的真实缺陷

**GBK 文件的字节偏移对不上磁盘字节**：`ChapterSplitter` 的 `startByte/endByte` 是按「解码后按 UTF-8 重编码」的长度累加的；GBK 中文 2 字节而 UTF-8 中文 3 字节 → 按字节取章会取错段落（书还能打开，但内容错位，极难排查）。
修法：取章改按**字符偏移**（`readChapterTextByChars`，UTF-8 / GBK 都正确），并写了一条「设计决策守卫」测试把这个坑钉死。

## 交付物

| 模块 | 文件 |
|---|---|
| 本地库（三表 books / chapters / progress） | `data/BookDb.ets` |
| 导入（picker → 沙箱拷贝 → 建章节索引 → 落库） | `engine/importer/BookImporter.ets` |
| TXT 解析（探测/解码/切章/取章 + 全文缓存） | `engine/parser/TxtParser.ets` |
| 书架页（继续阅读卡片 + 3 列网格 + 长按删除 + 空态） | `pages/Index.ets` |
| 阅读页（滚动模式 + 章节切换 + 进度落库 + 点屏浮出细栏） | `pages/Reader.ets` |
| 测试 | **20/20 绿**，新增真实编码字节回归（UTF-8 / GB18030） |

**CI 结果**：一次性通过，HAP **209 KB**（骨架时 90 KB），仍远低于 5 MB 预算。

## ponytail 简化记录（都留了升级路径）

| 简化 | 代价 | 何时升级 |
|---|---|---|
| 不做「页表缓存表」 | 每次进章重算页表（10ms 级） | 真机实测卡顿再加 |
| 不做 sha256 去重 | 重复导入同一本书会产生两条记录 | 有用户反馈再加 |
| 全文缓存在内存（只缓存当前书） | 大文件占内存（JS 字符串约为原字节 2 倍） | 大文件实测后改「按真实字节扫描建索引 + 随机读」 |
| 解析未走 `taskpool` | 导入时可能短暂卡 UI | 与分页一起搬进 taskpool |
| 阅读页先只做滚动模式 | 横滑分页未上 | 下一步（`PageTableBuilder` 已就绪） |

---

# 实现结论（2026-09-18，M3~M6 完成时回填）

## 1. 两个"自研 vs 系统 API"的取舍（都是同一个理由）

**理由只有一条：本机没有鸿蒙环境，设备 API 在这里等于"上真机碰运气"；纯 TS 自研能在 CI 里被真实数据证明。**

| 能力 | 官方 API | 我们的选择 | 为什么 |
|---|---|---|---|
| zip 解包 | `@ohos.zlib.decompressFile`（文档明确只支持 zip） | **自研**中央目录 + 按需解包 | ① 能在 CI 用真实 deflate 数据测；② 不落地临时文件，读一章只解一章；③ 顺带避免"整本解压"的磁盘与时间开销 |
| DEFLATE | （同上） | **自研** `Inflate.ets`（RFC 1951） | 只有自研才证明得了"我们真能解开 zlib 产出的流" |
| XML/OPF/NCX | `@ohos.xml` | **自研**极小扫描器 | EPUB 结构文件规整，取属性/取文本两件事够用；换来 CI 可测 |
| UTF-8 解码 | `util.TextDecoder` | **自研** `Utf8Decode.ets` | 行为边界可控（非法序列 → U+FFFD，绝不抛错），且可测 |
| **文本测量分页** | `@ohos.graphics.text`（**必须用**） | 保留官方 API | 没有替代品：一次 `layoutSync` 拿每行区间是"快"的根。代价见 §4 风险 |

**代价**：多写约 500 行；**收益**：EPUB 链路在第一次上真机之前就已经被真实出版书证明是对的。

## 2. 真实书实测（本机 Node 跑引擎，未上设备）

样本：calibre 3.44 生成的正规 EPUB 2，3.4 MB、103 个 zip 条目、14 章、全书 11.7 万字。

| 步骤 | 耗时 |
|---|---|
| 中央目录解析（103 条目） | **3 ms** |
| 整本 EPUB 解析（container → OPF → NCX → 章清单） | **7 ms** |
| 全书 14 章解压 + XHTML→纯文本 | **22 ms** |

结论：**解析侧完全不需要 taskpool**（22ms 对用户不可感知）；`@ohos.graphics.text` 的单章排版同理。原设计"全在 taskpool"的判断按实测下调。

## 3. 真实书逮到的两个真 bug（已写回归测试）

1. **嵌套 NCX 会让整本目录错位一章** —— calibre 的 NCX 里父 `navPoint` 常常**只有 navLabel、没有自己的 content**。按"text 与 content 出现顺序配对"时，整个序列错开一格，结果是**每章标题都指向前一章的正文**。
   → 改为 `scanTags` + 栈的**结构级配对**（把最内层 navPoint 的 label 与自己的 content 配成一对）。
2. **小节标题盖住章级标题** —— 带 `#fragment` 的 navPoint 解析后与章级条目指向同一文件，先到先得时"小节"会赢（父节点的 content 在子节点之后才闭合，所以小节总是先进表）。
   → 规则改为：**无 fragment 的条目优先**；只有当该文件没有任何章级标题时才退回小节标题。

> 教训（值得进家族级）：**机器生成的"标准格式"也会有嵌套陷阱**，而这类 bug 只有喂真实文件才暴露。合成 fixture 能测通路，测不出结构错位。

## 4. 字体决策（2026-09-18 党哥提问：能不能自带/让用户选？）

### 4.1 真实体积（不是估算，是下载头信息实测）

| 字体 | 体积 | 说明 |
|---|---|---|
| 霞鹜文楷 LXGW WenKai（全量 TTF） | **18.41 MB** | OFL，口碑很好的阅读字型 |
| 霞鹜文楷 **Lite**（GB2312 子集） | **11.18 MB** | 已经是子集了，仍然 11MB |
| 思源宋体 SC（官方发行包） | **132 MB** | 7 个字重 + 多语言子集合计；单字重 TTF 约 **16~18 MB**、单字重子集 OTF 约 **9 MB** |
| 思源黑体 SC（官方发行包） | **90 MB** | 同上口径 |
| Noto Serif CJK SC（官方包） | **132 MB** | 同上 |

**结论：一款能覆盖通用中文的字体，最小也是 9~11 MB 量级。** 而我们的 HAP 现在是 **115 KB**，
铁律 2 的预算上限是 **5 MB**。

### 4.2 四条路与取舍

| 方案 | 体积成本 | 判断 |
|---|---|---|
| **A. 列系统已装字体**（`getSystemFontList()`） | **0** | ✅ **v1 采用**：用户若在系统里装了喜欢的字体（主题字体），阅读器直接列出来可选 |
| B. 内置 1 款**子集**字体（GB2312 常用字 + 标点 + 拉丁） | **+2~4 MB**（需自行用 fonttools 子集化；OFL 允许再分发但须带版权声明） | ⚠️ 可行但会把 5MB 预算吃掉大半；缺字需回退系统字体 |
| C. 内置 3 款全字库 | **+33~55 MB** | ❌ **直接撞碎铁律 2**，也超过用户对"装个阅读器"的预期 |
| D. 联网按需下载字体包 | 0（+联网） | ❌ 与"核心数据不联网"的门面冲突；且需额外托管与校验；v1 不做 |

### 4.3 已实现的能力与技术要点

- **列系统字体**：`getUIContext().getFont().getSystemFontList()`（现代 API；`@ohos.font` 的全局函数已废弃）
- **自带字体（将来要用）**：`getUIContext().getFont().registerFont({ familyName, familySrc })`，字体放 `resources/rawfile/`
- ⚠️ **字体必须进排版签名**（本次已修）：换字体会改断行，若页表缓存键不含字体族，
  翻页会沿用旧页表 → **切错页/溢出**。现在 `layoutKey` 末尾带 `-ff<族名|sys>`，且 `measureLineEnds` 会传 `fontFamilies`

**待党哥拍**：是否走方案 B（内置一款子集字体，HAP 变成 2~4MB）。若走，选哪款字型（宋/楷/黑）。

## 5. 仍未验证 / 最高风险项

| 项 | 说明 | 何时能验 |
|---|---|---|
| **测量与渲染的断行是否一致** | 排版用 `@ohos.graphics.text`（px），渲染用 ArkUI `Text`（fp/vp）。两者若在标点、中英混排、系统字体缩放下断行不同，页面会溢出（表现为"最后一行被截"） | 真机（M6 Phase 8） |
| 冷启动 ≤1s | CI 只能证编译与体积 | 真机 |
| 翻页掉帧 | `layoutSync` 真机耗时 | 真机 |
| 50MB+ TXT | 当前同步读整本 + 全文缓存内存 | 真机 |
| Ads Kit 是否需 AGC 开通 | 官方文档是 SPA，抓不到正文 | 上架前 |

**已记录的对冲**：`TextPaginator.measureLineEnds` 对 `endIndex` 做了单调性夹紧与末尾补齐（宁可多切一页，不许丢字）；页表缓存键带实际 px（系统字体缩放变化不会错用旧页表）。
