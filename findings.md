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
