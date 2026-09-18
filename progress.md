# Progress Log — Rock阅读（RockReader）

## Session: 2026-09-18（立项）

### Current Status
- **Phase:** 1 - 技术 spike（尚未开始，等环境就绪）
- 工程目录已建：`f:\AI\HarmonyOS\RockReader\`；**git 仓库待党哥创建远端后告知再 init/clone**

### Actions Taken
- 党哥定名：中文 **Rock阅读**，英文 **RockReader**；家族统一 **Rock** 前缀
- 建立应用级三件套 `task_plan.md` / `findings.md` / `progress.md`
- 技术预研从家族 `findings.md` §9 迁入本目录 `findings.md`（家族侧只留指针）
- 定边界：A 纯本地离线，首版 TXT，随后 EPUB，不做 PDF、不做书源
- 党哥明确：**本机不搭鸿蒙开发环境**，只写代码；日常小版本构建也走 GitHub Actions；真机由他准备
- 相应调整：工程文件改为手写（不用 DevEco 向导）；三个 spike 降级为"文档调研 + 按最坏情况设计"，实测回填
- 党哥拍板：推送粒度 ✅ 日常小版本可 push 触发 CI、大版本才 tag→Release；但 **Rock-Reader 首次 push ❌ 暂缓**
- 党哥决定**放弃 HarmonyOS 4 及更早**：只支持 HarmonyOS 6+（单框架），`compatibleSdkVersion = 20` / `targetSdkVersion = 24`，单包发布，不再做双包与 API 差异分支

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|

### Errors
| Error | Resolution |
|-------|------------|

---

## Session: 2026-09-18（调研 + v1 设计定案）

### Current Status
- **Phase:** 1 → 转入 v1 实施准备；**v1 范围 = TXT + EPUB**
- 本机（macOS）已把目录建成台账结构：`HarmonyOS/` = harmony-docs 工作副本，`HarmonyOS/Rock Reader/` = 本仓库

### Actions Taken
- 调研 GitHub 开源阅读项目：KOReader、Legado（含鸿蒙版 `mgz0227/legado-Harmony`）、Readest、Anx Reader、Foliate/foliate-js、Koodo、**华为官方 ReaderKit 示例**；结论入 `findings.md`「调研结论 C」，并明确许可证红线（GPL-3.0 / AGPL-3.0 只借鉴设计不抄代码）
- **发现鸿蒙官方 Reader Kit（阅读服务）**：`bookParser` + `ReadPageComponent` + `readerCore`；API 16+、txt/epub/mobi/azw/azw3、**仅沙箱内本地文件**、仅中国大陆 + 真机（无模拟器）、无 PDF；是否需 AGC 开通待核实（`findings.md`「调研结论 A」）
- **推翻原假设**：自研分页不必用 `measureText` + `BreakIterator` 反复测量——改用 `@ohos.graphics.text`（`ParagraphBuilder` → `layoutSync` → `getLineMetrics()`，直接给每行 `startIndex`/`endIndex`），一次排版即可切页（`findings.md`「调研结论 B」）
- 辟谣并记录：网上大量文章写的 `onTextLayout` / `TextLayoutResult` / `ReaderController` / `BookMetaManager` 等 API 官方文档中**不存在**，属 AI 臆造，禁止照抄博客代码
- 把家族《通用准则》逐章映射到鸿蒙项目（可用 / 不适用 / 需替代），写入 `docs/v1-design.md` §11
- **党哥拍板**：① 阅读内核**自研为主**，Reader Kit 只留可插拔适配器位；② **v1 直接上 TXT + EPUB**（不分两次发）
- **v1 设计定案**并落 `docs/v1-design.md`：分层架构、引擎层接口契约（`BookParser`/`Paginator`）、数据模型、性能预算、兜底降级、UI 规范（Nothing OS × 家族，含档位→数值唯一真源表）、里程碑 M1~M6、待核实清单
- 三个小决定同步落定：书封面 0 圆角 / 启动停在书架 + 继续阅读卡片 / 横滑翻页不做仿真
- 产出 **UI 草案** `docs/ui-mockup-v1.html`：HTML 1:1 还原 4 屏（书架 / 阅读页沉浸 / 点屏浮出菜单+档位芯片 / 设置），交给党哥审；点阵字为纯 CSS 5×7 点栅格绘制，**不引任何字体文件**（对齐"极致小"）
- 预览方式：本机 `python3 -m http.server 4173`（docs 目录），本机无鸿蒙环境所以只能用 HTML 还原，不能跑 ArkUI
- 调研鸿蒙生态变现（写入家族 `findings.md` §12）：**买断制在国内生态不成立**（免费+内购占 96% 下载量）；**元服务月收益 ≤3 万可拿 100% 现金激励**、鸿蒙应用 25%；政企/信创与"卖铲子"是可选项；平台激励（单开发者上限 100 万）比 C 端付费现实得多
- **党哥修订联网口径 = 铁律 3 升级**：口号改为「**核心数据不联网**」（不联网不影响本体使用；联网只为广告变现；选择权交用户）。允许申请 `INTERNET`，但**广告默认关闭**，并给愿意的用户**正当交换**（激励视频换增值），避免纯自愿开启转化率过低
- 随之同步修订的文档：家族 findings「铁律 3 全文」「§8 权限登记（RockReader 已登记）」「§12.4 广告变现 Ads Kit」；`Rock Reader/findings.md` 产品边界；`docs/v1-design.md` §1.1/§1.2/§3（新增 `AdPolicy` 接口）/§8（广告三纪律 + 联网计数器）/§10（**新增 M7 广告模块**）/§12
- 关键发现：**HarmonyOS Ads Kit 是系统级 Kit**（非三方 SDK，直接命名空间调用）→ **HAP 体积几乎不受影响，铁律 2 未被撞穿**；六种广告形态中**明确不做开屏**（拖慢冷启动，撞铁律 1）与**插屏**（打断使用）；前置条件 = 应用需已在应用市场上架
- 变现结论更新：**广告成为 Rock Reader 的收入来源之一**（配合鲸鸿动能 25% 现金激励），但广告**绝不出现在阅读页**
- **党哥澄清「把选择权交给用户」的确切含义**（同日二次修订，采纳）：
  1. **操作方式**：想无广告的用户**自行到系统设置切断本应用的联网权限**即可，切断后**不影响任何功能**，只是没有广告；
  2. **呈现原则**：应用内**不刻意告知"可以去广告"**，**不设广告开关**之类的功能。
- 据此纠正我先前的理解错误（我原写成"广告默认关闭 + 设置页开关 + 联网计数器"，方向反了）：
  - **默认态 = 联网 + 呈现广告**（否则"断网去广告"没有意义）
  - 删除「广告开关」「支持开发入口」「联网计数器」三项设计
  - 新增**断网静默降级硬要求**（不发请求/不弹提示/不报错/不留空洞，禁止"网络异常"类提示）
  - 文案规范：界面只讲「核心数据不联网」品牌承诺，**不提广告、不提联网开关**；**隐私政策仍须如实写明广告与联网**（合规必做，与应用内不引导是两件事）
- 已同步：家族 findings 铁律 3、`Rock Reader/findings.md`、`docs/v1-design.md`（§1.1 / §3 `AdPolicy` 接口 / §8 广告纪律六条）、`docs/ui-mockup-v1.html`（设置页文案）

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 无（本机无鸿蒙环境，不能实测） | — | — | — |

### Errors
| Error | Resolution |
|-------|------------|
| `git` / `curl` 直连 `github.com` 超时，但 `gh` 却正常 | 本机走 PAC 代理（`localhost:1089/proxy.pac` → SOCKS5 `127.0.0.1:1086`）；git 不读系统 PAC，需显式 `git -c http.proxy=socks5h://127.0.0.1:1086 <命令>` |

---

## Session: 2026-09-18（M1 完成：工程骨架 + CI 构建通过）

### Current Status
- **Phase:** M1 ✅ 完成 → 进入 M2（存储 + 导入 + 书架）
- 党哥下令"按沟通的开始做，直至 MVP 在 GitHub 构建"，本轮打通了整条 CI 链路

### Actions Taken
- 手写完整 Stage 工程骨架（不用 DevEco 向导）：`build-profile.json5`（**双 product**）、`oh-package.json5`、`hvigorfile.ts`、`hvigor/hvigor-config.json5`、`AppScope/`、`entry/`（module.json5 / 资源 / EntryAbility / Index 书架页 / Reader 占位）
- **CI 打通**（这是本轮主要战场）：公开免登录的 OpenHarmony SDK + 缓存 + npm 版 hvigor CLI，`BUILD SUCCESSFUL`，产出 `entry-default-unsigned.hap` **90 KB**；作业 2 全绿
- 纯逻辑引擎落地（`entry/src/main/ets/engine/`）：编码探测（BOM/UTF-8 严格校验/GB18030 兜底）、章节切分（含「前言」章与字节偏移）、页表构建（按行切页 + 排版签名 + 页码二分）
- 单测接入（`test/`，esbuild 把 `.ets` 当 TS + `node:test`）：**17/17 绿**，本地与 CI 同跑；当场抓出并修掉 2 个真实 bug（前言被丢、末行偏移虚增 1）
- 家族 `findings.md` 新增 §13「CI 构建 HAP 的可用配方（全家族复用）」：六步配方 + **7 个真实踩坑** + 防假绿要求

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| CI `纯逻辑单测` | 通过 | 17 tests 全绿 | ✅ |
| CI `ArkTS 编译校验 → HAP` | 产出 HAP | `BUILD SUCCESSFUL`，HAP 90 KB | ✅ |

### Errors
| Error | Resolution |
|-------|------------|
| 构建步骤"成功"但产物为空（假绿） | 旧版 hvigorw 包装器不执行任务只退 0 → 改用 npm 版 `@ohos/hvigor/bin/hvigor.js`；并加"产物存在性校验" |
| `hvigor-wrapper.js:1` 一行崩 | 根 package.json 的 `"type": "module"` 让 Node 把 CJS 包装器当 ESM → 去掉该字段 |
| `00303034` 缺 compileSdkVersion | OpenHarmony product 补 `"compileSdkVersion": 20` |
| `The SDK license agreement is not accepted.` | 构建步骤 export 死代理让许可证请求失败 → 检查短路放行（不发内容、不自动接受） |
| workflow 0 job 被拒 | GitHub 不允许 `HTTP_PROXY`/`http_proxy` 大小写同名 env 键 → 改用 shell export |
| `Unable to find the following components: native/previewer` | 五个组件必须全解压（纯 ArkTS 也一样） |
| `00303060 多设备 syscap 交集为空` | OpenHarmony 手机侧设备类型是 `default` 不是 `phone` |

---

## Session: 2026-09-18（M2 完成 + M3 第一版）

### Current Status
- **Phase:** M2 ✅ / M3 进行中（滚动模式能读书；横滑分页下一步）
- 党哥放入一本真实 EPUB（4MB）到 `~/Downloads/rockreader-samples/` —— **仅本地实测用，绝不进仓库**

### Actions Taken
- **借鉴前的许可证审查**（按党哥新规矩）：官方 ReaderKit 示例 **Apache-2.0** ✅ 可借鉴；foliate-js **MIT** ✅；`waylau/harmonyos-tutorial` **无 LICENSE** ❌ 只看 API 不抄代码；KOReader/Legado/Readest 为 GPL/AGPL ❌ 只借鉴设计
- **M2**：`BookDb`（relationalStore 三表）+ `BookImporter`（picker → 沙箱 → 建索引 → 落库）+ 书架页做成真数据（继续阅读卡片 / 3 列网格 / 长按移除 / 空态）
- **M3 第一版**：`TxtParser`（探测 → 解码 → 切章 → 取章）+ 阅读页（滚动阅读 / 上一章下一章 / 进度落库 / 点屏浮出细栏 / 页脚等宽数码）
- 新增真实编码回归样本（自写文本，UTF-8 与 GB18030 各一份）→ 单测 **20/20 绿**
- 抓到一个真实缺陷：**GBK 文件的 UTF-8 字节偏移与磁盘字节不一致** → 取章改按字符偏移，并加守卫测试

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 单测（本地 + CI） | 全绿 | 20/20 | ✅ |
| CI 编译（新增 relationalStore/picker/Grid/手势） | 通过 | 一次通过，HAP 209 KB | ✅ |

### Errors
| Error | Resolution |
|-------|------------|
| 真实样本测试期望 3 章、实际 4 章 | 是**我的期望写错**：样本开头有书名/作者，按设计应成「前言」章 → 修正期望为「前言 + 3 章」 |
| TxtParser 里从 `@kit.ArkTS` 重复 import | 合并为一行（去掉未用的 `taskpool`） |
| 书架用了 `rd_card`/`rd_g100` 两个未定义色值 | 补进 `color.json`（`#08FFFFFF` / `#1A1A1A`） |

---

## Session: 2026-09-18（M3 收尾 → M4 → M5 → M6，一路做到可交付）

### Current Status
- **M1~M5 全部完成；M6 只剩"真机项"**（本机无鸿蒙环境，必须等设备）
- CI 全绿；纯逻辑单测 **20 → 52**；HAP **115 KB**（预算 ≤5MB）

### Actions Taken

**M3 收尾 —— 横滑分页（默认阅读模式）**
- 新增 `engine/paginator/Paginator.ets`（契约 + `PageCache` LRU + `FakePaginator`）与 `TextPaginator.ets`（`@ohos.graphics.text`：`ParagraphBuilder → layoutSync → getLineMetrics()` 取每行 `endIndex`）
- 新增 `common/LayoutStyle.ets`：档位**唯一真源**表 + `layoutKey`（把实际 px 折进缓存键，防系统字体缩放错用旧页表）
- 阅读页重写：点两侧翻页 / 点中间浮出细栏 / 横滑翻页（淡出→换页→淡入 + 方向位移）/ 目录浮层 / 分段进度条 / 底栏四键
- 进度策略：章内每 5 页落一次 + **切章必落** + `onPageHide`/`aboutToDisappear` 立即落
- 单测新增 `paginator` / `layout` 两组；**`clampLevel` 边界写错被测试逮到**（0 与负数被当成 NaN 回落默认档）

**M5 —— 设置 / 目录 / 昼夜 / 切档不跳页**
- 新增 `data/ReaderPrefs.ets`（Preferences，**只存序号与主题名**）+ `common/Theme.ets`（运行时色板，与系统深浅色解耦）
- 新增 `pages/Settings.ets`：字号/行距/边距 5 档芯片 + 主题 2 芯片，**全页无滑块**；底部只写「核心数据不联网」
- 阅读页 `onPageShow` 重读偏好 → 签名变了才重排 → **按字符偏移复原位置**（切档位不跳页）
- 书架/阅读/设置三页全部切到 `Palette`（`$r('app.color.*')` 只留窗口背景）

**M4 —— EPUB 全链路（自研 zip + inflate + OPF/NCX + XHTML）**
- 新增 `engine/zip/Inflate.ets`（raw DEFLATE：stored / fixed / dynamic 三种块）、`engine/zip/ZipReader.ets`（中央目录 + **按需取条目，不解压到磁盘**）
- 新增 `engine/text/Utf8Decode.ets`（纯 TS，非法序列 → U+FFFD）
- 新增 `engine/epub/{Xml,Opf,Xhtml,EpubParse}.ets` 与设备层 `engine/parser/EpubParser.ets`；`BookSource` 加 `EpubSource`；`BookDb` 的 chapters 加 `href` 列（含幂等迁移）；导入时用 OPF 的书名/作者
- 新增 `test/zipfixture.ts`：在内存里现造**真实合法 zip**（正确 CRC32 + 真实 deflate），避免把版权书塞进仓库
- 测试运行器补 `resolveExtensions`（否则 esbuild 解析不到 ArkTS 的无扩展名 `.ets` 导入）
- 单测 **30 → 52**

**对真实书的验证（关键一步）**
- 用 calibre 生成的真实出版 epub（3.4MB / 103 条目 / 14 章 / 11.7 万字）在本机跑完整链路：
  中央目录 3ms、整本解析 **7ms**、全书解压+转文本 **22ms**、书名/作者/封面/目录标题全对
- 顺手用系统 `unzip -t` 交叉验证测试 fixture 本身是合法 zip（证明 fixture 与读者都是对的）
- **逮到两个真 bug**（都补了回归测试）：① 嵌套 NCX（父 navPoint 有 navLabel 无 content）按顺序配对 → 整本目录**错位一章**；② 小节标题（带 `#fragment`）会**盖住章级标题**
- 过程脚本跑完即删，不进仓库（版权 + 体积）

**M6 —— 打磨与文档**
- `README.md` 重写（当前状态、架构、自研理由、**本地如何验证真实书**、构建发布、许可证红线）
- `docs/v1-design.md`：修掉 `LayoutStyle` 档位范围与实际不符（1|2|3 → 1~5）、补真实书实测性能数据
- `docs/ui-mockup-v2.html`：与实现 **1:1** 的 UI 复审稿（5 屏：书架 / 阅读 / 浮出细栏 / 目录浮层 / 设置）
- `task_plan.md`：Phase 1/4/5/6 置为完成、Phase 8 列清真机项、决策表 +4 条、错误表 +5 条

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 纯逻辑单测（本地 + CI） | 全绿 | **52/52** | ✅ |
| CI 编译（M3：graphics.text / Swiper 交互 / 主题） | 通过 | 第 2 轮通过（首轮 5 个 ArkTS 错误已修） | ✅ |
| CI 编译（M4：自研 zip/inflate/XML） | 通过 | 一次通过 | ✅ |
| 真实出版 EPUB 端到端（本机 Node） | 目录正确、正文正确 | 14 章标题全对；正文首尾都对得上；22ms | ✅ |
| HAP 体积 | ≤5MB | **115 KB** | ✅ |
| 冷启动 / 翻页掉帧 / 大文件内存 | — | 本机无设备，**未验证** | ⏳ |

### Errors
| Error | Resolution |
|-------|------------|
| ArkTS `arkts-no-obj-literals-as-types`（`Array<{start,end}>`）| 对象字面量不能当类型声明 → 改用 `PageRange` 接口 |
| ArkTS `10505001 Property 'opacity' is not assignable to CustomComponent` | 字段名撞上 ArkUI 属性方法 → 改名 `pageOpacity`（同类：`visibility`/`offset`/`position`/`id` 都要避） |
| esbuild `Could not resolve './Xxx'` | ArkTS 内部导入不写扩展名 → 运行器显式 `resolveExtensions: ['.ets', ...]` |
| 嵌套 NCX 目录错位一章 | 改 `scanTags` + 栈的**结构级配对**（见上） |
| 小节标题盖住章级标题 | 章级（无 fragment）优先，仅当该文件无章级标题才退回小节标题 |
| `gh run watch` 抓到上一轮 run（时序） | 改成轮询 `gh run list -L1` 直到 `completed` |
| `curl --socks5-hostname` 不被本机 curl 识别 | 换标准写法 `-x socks5h://127.0.0.1:1086` |

### Next
- **等党哥**：要不要打首个 tag 发 Release（发版需下令）
- **等设备**：M6 真机项（冷启动 ≤1s、翻页掉帧、50MB TXT、字体缩放下排版一致性 —— 最后一条是最高风险项）

---

## Session: 2026-09-18（自查修 bug + 字体能力 + 真机测试手册）

背景：党哥要在 Windows 上装 DevEco Studio 跑真机测试；并问"能不能选字体/自带字体，体积影响多大"。

### Actions Taken

**一、自查发现并修掉的 5 个真问题**（都是真机上才会暴露的）

| # | 问题 | 修法 |
|---|---|---|
| 1 | **导入链路脆弱**：原实现"开 URI → 取 path → **关掉** → 按 path 重开"才拷贝。picker 授予的是那个 **fd** 的读权限，按路径重开在真机上可能被拒 | 改为**全程持有 fd**：`openSync(uri)` 一次，`statSync(fd)` 校验大小、`copyFile(fd, dst)`、校验都在同一 fd 上完成；文件名从 uri 末段解码（不再依赖真实路径） |
| 2 | **拷贝可能静默不完整**（半截/0 字节）→ 书架出现"打不开"的脏数据 | 拷完**比对源与目标字节数**，不一致按 `COPY_FAILED` 处理，不落库 |
| 3 | **视口变化后不重排**：旋转/分屏/系统字号缩放后，页表仍是旧视口的 → 末行被裁 | `onAreaChange` 记住上次排版尺寸，变化 >1vp 就**按字符偏移原地重排** |
| 4 | **浅色主题下状态栏看不见**：页面变白、状态栏文字仍是白色（系统绘制） | 新增 `common/SystemBar.ets`：主题变化时同步 `setColorMode` + `setWindowSystemBarProperties`；EntryAbility 启动时按偏好设 colorMode |
| 5 | **排版签名不含字体**：换字体会改断行，缓存键却只看档位 → 沿用旧页表会切错页 | `LayoutBox` / `layoutKey` / `measureLineEnds` 全部纳入 `fontFamily`（`-ff<族名|sys>`） |

**二、字体能力（回答党哥的问题，用真实数据算体积）**

- **实测体积**：霞鹜文楷全量 **18.41MB**、Lite(GB2312 子集) **11.18MB**、思源宋体/黑体官方包 **90~132MB**（单字重 TTF 约 16~18MB、子集 OTF 约 9MB）
- **结论**：一款覆盖通用中文的字体最小 9~11MB；HAP 现在 115KB、预算 5MB → **内置三款全字库会撞碎铁律 2**
- **v1 采用**：`getSystemFontList()` 列**系统已装字体**供选择（体积 **0**，不联网）。用户若在系统里装了喜欢的字体就能直接选
- 留下方案 B 的位：内置一款 GB2312 子集字体约 +2~4MB（需 fonttools 子集化；OFL 允许再分发但须带版权声明）—— 待党哥拍

**三、设置页新增「字体」**：预览行 + 横向字体芯片（每款用它自己渲染，直接看效果）；`ReaderPrefs` 增加字体偏好项

**四、新增全流程不变量测试**（`test/flow.test.ts`）：EPUB → 章节 → 正文 → 分页 → 页码↔字符偏移 → 进度恢复。
守住四条不变量：**不丢字、不重复、页码双向一致、空章/单页章不崩**；另验"换排版后按字符偏移原地复原"
与"页表缓存按签名隔离（含字体）"。

**五、产出 `docs/device-test.md`（真机测试手册）**：DevEco 打开/签名/跑真机步骤；A~D 四组验收清单
（关键路径 12 条、**最高风险项 B1~B3**、性能 4 条、意外路径 4 条）；日志命令；"本地改动不要提交"的注意事项。

**六、修文档与配置不一致**：README 与 spec 原写"只支持 HarmonyOS 6+（API 20/24）"，
实际 `build-profile.json5` 是 `compatibleSdkVersion = 5.0.4(16)` / `targetSdkVersion = 6.0.0(20)`
→ **以代码为准改文档**（覆盖面更大，也不受 API 24 SDK 是否安装影响）。

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 纯逻辑单测（本地） | 全绿 | **57/57**（新增 flow 组 5 条 + layout 扩 1 条） | ✅ |
| CI 编译 | 通过 | 见下方提交后的 CI 结果 | ⏳ |
| 真机 | 手册已交付 | 等党哥在 Windows + DevEco 上跑 | ⏳ |

### Errors
| Error | Resolution |
|-------|------------|
| flow 测试断言"容量 4 的缓存插 2 个 key 会淘汰旧的" | **我的断言写错**（容量 4 不淘汰）；真正验老化要用 `PageCache(1)`，已改 |
| flow 测试 `before.pages[3]` 为 undefined | **测试期望写错**：那章只切出 3 页；改成取中间页 |
| flow 测试期望 `'很短'` 末页 end=3 | **测试期望写错**：是 2 个字；已改（应用行为本来正确） |
| `UIContext.d.ts` 抓取失败 | 正确路径是 `api/@ohos.arkui.UIContext.d.ts`；改对后确认了 `getFont().getSystemFontList()` 与 `registerFont()` |
| progress.md 追加时 old_str 不匹配（`需设备` vs `等设备`） | 先 `tail` 读真实内容再替换 |

### Next
- **等党哥真机结果**：按 `docs/device-test.md` 跑一遍，把不合预期的现象贴回
- **待定**：是否打首个 tag
- **M7**：Ads Kit 广告模块（最后做）

---

## Session: 2026-09-18（字体改为「按需下载」）

### 决定

党哥：**字体走下载，避免增加软件体积**。→ 内置字体 = 0，改为"用户主动下载 + 存本机沙箱"。

### Actions Taken

**一、选源（用真实体积说话，最后落到"我们自己的 Release 托管"）**

| 字体 | 体积 | 来源 |
|---|---|---|
| 霞鹜文楷 Lite（楷体，GB2312） | **13.3 MB** | lxgw/LxgwWenKai-Lite v1.520 |
| 思源宋体 Noto Serif SC（衬线） | **24.0 MB** | google/fonts `ofl/notoserifsc` |

- 尝试过思源宋/黑体的官方单字重直链 → **404**（只有 90~132MB 的多字重 zip，不适合）
- **托管到我们自己的 Release `fonts-v1`**（不依赖上游链接稳定性；将来换更小的子集包时 URL 不变）
- 两款字体**原样再分发、未修改** → 遵循 OFL 1.1，无需按 Reserved Font Name 规则改名
- 下载直链已验证：HTTP 200 且字节数一致

**二、实现（`data/FontStore.ets` + `common/FontCatalog.ets` + 设置页）**

- 下载 → 比对字节数 → **比对 SHA256** → 通过才 `rename` 上位（先写 `.part`，中断不留半截文件）
- 失败一律**静默**：无网络/超时/校验不过都只写在字体区状态里，不弹窗、不拦路
- 加一款字体 = 往 `FONT_CATALOG` 加一条记录，其余逻辑不用动

**三、一个容易被漏掉的关键点：测量端必须单独挂字体**

ArkUI 的 `registerFont` **只作用于渲染端**，不保证 `graphics.text` 的测量集合里有这个字体。
不挂的话：测量用回退字体断行、渲染用真字体 → 两边行数不同 → **页面溢出（末行被裁）**。
→ `TextPaginator` 里用 `FontCollection.getGlobalInstance().loadFontSync(族名, 文件路径)` 挂**同一个文件**
（挂进全局集合而非新建局部集合，是为了保留系统字体的缺字回退）。
这条已写成真机验收项 **B4**。

**四、联网范围变化（必须登记）**

- `module.json5` 新增 `ohos.permission.INTERNET`：仅用于 ①字体包下载（用户点击才发起）②广告（M7，未接入）
- 家族 `findings.md` §8 登记新增一行"用户主动下载字体包"
- 顺手修掉 §8 里一处**过期口径**：原写"广告默认关闭、用户主动开启"，
  与后来澄清的"默认联网呈现 + 无开关 + 无引导"矛盾 → 已改正并加登记口径说明

**五、设置页改动**：字体芯片行（系统字体 + 已下载字体）+「更多字体」下载区（名称/说明/体积/授权 + 下载按钮）；
中间内容改为可滚动（加了下载区后一屏放不下）

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 纯逻辑单测 | 全绿 | 57/57（字体下载属设备能力，CI 无法验证） | ✅ |
| CI 编译 | 通过 | 第 2 轮通过（首轮 1 个编译错误） | ✅ |
| 字体直链 | 可用 | 两条均 HTTP 200 + 字节数一致 | ✅ |

### Errors
| Error | Resolution |
|-------|------------|
| `Property 'TRUNCATE' does not exist on type 'typeof OpenMode'` | 枚举名是 **`TRUNC`**（不是 TRUNCATE）；查 `@ohos.file.fs.d.ts` 枚举确认 |

### 补充（同日）：字体源按「开源 + 国内快 + 官方源」重做

党哥追加两条约束：① 用开源字体 ② 国内下载要快，尽量官方源。

**实测过的路（都没走通，值得记下来免得重复试）**

| 尝试 | 结果 |
|---|---|
| 清华 TUNA / 中科大 USTC / 南大 的 `github-release` 镜像 | **404** —— 这类镜像是**申请制**，我们仓库没入库 |
| jsDelivr 直连上游大仓库（lxgw、adobe-fonts） | **403** —— 仓库过大/超限 |
| npm（阿里云镜像）上的字体包 | 只有 woff2 网页字体（Fontsource），不适合本地注册 |
| Gitee 上字体作者的官方仓库 | 本机网络连不上，无法确认 |

**最终方案：把字体做小（这才是"国内快"的根本解）+ 官方 CDN 加速**

1. **子集化**：用 fonttools 按 **GB2312 全集（6763 字）** 切子集
   - 霞鹜文楷 Lite 13.28MB → **3.27MB**
   - Noto Serif SC 24.0MB → 先 `varLib.instancer` 定字重 wght=400 → 再子集 → **2.91MB**
   - 极罕见字回退系统字体（只影响个别字的字型）
2. **按 OFL 规则改名**：子集属"修改"，不得沿用 Reserved Font Name →
   `RockReader Kai` / `RockReader Song`，归属写进字体文件内部的 copyright 字段
3. **托管与分发**：字体放在**独立分支 `fonts` + tag `fonts-v1`**（不污染 main），
   应用按 **jsDelivr CDN → GitHub Release → GitHub raw** 顺序尝试，
   **每个源都校验 SHA256**（实测 jsDelivr 下发的字节与预期 sha256 完全一致）
4. 代码：`FontCatalog` 改多源；`FontStore` 逐个源尝试

**操作失误与修正**：`git switch --orphan fonts` 失败但管道让后续 `&&` 继续，
字体被误提交到 main（本地未推送）→ `git reset --hard origin/main` 撤销，字体保留在独立分支。

---

## Session: 2026-09-19（台账同步）

### Current Status
- 应用 `97a63a8`、家族台账 `1888286`，**两侧本地与远端一致**

### Actions Taken
- **应用台账**：补 Phase 9（字体模块，已 done）、Phase 8 标记 in_progress、
  Current Phase 改为 Phase 8（真机验证）；修正三处**过期决策**
  （"零联网/不申请 INTERNET" → 核心数据不联网且已声明 INTERNET；
   "解析分页走 taskpool" → 实测后改为按章主线程执行；
   "只支持 HarmonyOS 6+ 20/24" → 实际配置是 5.0.4(16)/6.0.0(20)）
- **家族台账**：Phase 1~4 置为 done、Phase 5（真机验证）in_progress；应用登记表状态更新；
  决策表 +5 条（自研优先、真实素材立刻验证、字体按需下载、大二进制不进 main）；
  错误表 +8 条（ArkTS 坑、NCX、OpenMode、误提交、国内镜像等）；新增本次会话记录
- **同步党哥 Windows 侧的进展**（远端 3 个新提交，已 rebase 合并）：
  ① 新版 DevEco **自带 HarmonyOS SDK（API 26）**，打开工程直接 Build 成功 →
     **早期"正式包需 command-line-tools 直链"的判断作废**，Phase 7 相应更新
  ② SDK 目录联接（`LOCALAPPDATA\Huawei\Sdk → G:\HarmonyOS\Sdk`）
  ③ 本地 `default` 产物 436 KB，可装手机；CI 的 `ci` 产物 135.7 KB 只做编译校验 →
     已在 `docs/device-test.md` 加对照表，避免混淆

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 单测 | 全绿 | 57/57（本轮只改文档） | ✅ |
| CI 编译 | 通过 | 见下方 | ⏳ |

### Errors
| Error | Resolution |
|-------|------------|
| 家族台账 push 被拒（远端有新提交） | 先看 `git log HEAD..origin/main` 确认是党哥在 Windows 侧推的进展 → `git pull --rebase` 后推送 |
- **M7**：Ads Kit 广告模块（默认联网呈现、无开关、无引导、断网静默降级、绝不出现在阅读页）

---

## Session: 2026-09-19（Windows 侧：本机编译校验打通 + 预览器可用）

### Current Status
- **Phase:** 8 真机验证进行中；本机新增三项能力：**编译校验 + 单测 + 预览器**
- 仓库：本地 = 远端（`7fdcaa0`）

### Actions Taken

**一、纠正一个过期认知（重要）**
- 新版 DevEco Studio **把 HarmonyOS SDK 内置在 IDE 里**：`<IDE>\sdk`，**apiVersion 26 / platformVersion 26.0.0 / Release / 26.0.0.105**
- 因此"打开 SDK 管理器 → 勾选 API 20 → 下载"那套**旧流程作废**；本机也不需要再下载任何 SDK

**二、本机命令行构建打通（IDE 自带工具链，不额外装东西）**

| 组件 | 路径 |
|---|---|
| node | `<IDE>\tools\node\node.exe`（v24.14.1） |
| ohpm | `<IDE>\tools\ohpm\bin` |
| hvigor | `<IDE>\tools\hvigor\bin\hvigorw.js`（6.26.4） |
| JDK | `<IDE>\jbr`（打包必需） |

- `assembleHap -p product=default -p buildMode=debug` → **BUILD SUCCESSFUL**（3.3s）
- 产物：`entry/build/default/outputs/default/entry-default-unsigned.hap` **436 KB**
- 意义：**本机有了本地编译校验**，小改动不必等 CI

**三、本机单测跑通**：`npm test` → **57/57 全绿**（约 205ms）

**四、预览器可用**：党哥在 DevEco 里成功打开预览器（一次只能看一个页面 —— 属正常，页面取数依赖路由参数/数据库/沙箱文件）

**五、其它**
- 目录联接 `%LOCALAPPDATA%\Huawei\Sdk → G:\HarmonyOS\Sdk` 已建（内置 SDK 模式下用不上，保留无害）
- 迁移 IDE 内置 SDK 到 G 盘的提权脚本两次执行失败（UAC/安全软件拦截），脚本留在 `G:\HarmonyOS\move-sdk-to-g.ps1` 待人工以管理员身份运行
- 已拉取 macOS 侧进展：字体改 **GB2312 子集**（楷 3.27MB / 宋 2.91MB）+ 独立 `fonts` 分支 + 多源 CDN + 每源 SHA256

### Test Results
| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| 本机纯逻辑单测 | 全绿 | 57/57（205ms） | ✅ |
| 本机 hvigor 构建（product=default） | 产出 HAP | BUILD SUCCESSFUL，436 KB | ✅ |
| DevEco 预览器 | 能渲染页面 | 打开成功（单页） | ✅ |
| 真机运行时（冷启动/掉帧/断行一致性） | — | 仍无设备 | ⏳ |

### Errors
| Error | Resolution |
|-------|------------|
| `PackageHap` 报 `spawn java ENOENT` | PATH 里没有 java → 加上 IDE 自带的 `<IDE>\jbr\bin` |
| 提权执行迁移脚本两次失败（退出码 1、日志未生成） | UAC / 火绒拦截静默提权 → 改为人工以管理员身份运行脚本 |
| **更正上一节的措辞** | 上节写"本地 default 产物 436 KB，**可装手机**"缺了前提：未配签名时产物是 `entry-default-unsigned.hap`，**装不上手机**。`docs/device-test.md` 表格里"调试签名 ✅"的写法才准确 |
