# Task Plan: Rock阅读（RockReader）

> 应用级台账。家族级计划与铁律见 `..\planning\`（harmony-docs 仓库 `.planning/`）。
> 铁律全文：`..\planning\findings.md` 顶部常驻章节。

## Goal
做一个**纯本地、零联网**的鸿蒙电子书阅读器：导入本地书 → 解析 → 分页 → 阅读 → 记住进度。
**v1 范围 = TXT + EPUB 一起上**（党哥 2026-09-18 拍板）；阅读内核**自研为主**，Reader Kit 只留可插拔适配器位。
技术底座与调研结论见 `findings.md`「调研结论（2026-09-18）」；UI 方向 = 家族 Nothing OS 风格（黑白单色 + 点阵数码 + 红点 `#FF4A3D`）。

## Current Phase
Phase 6（M6 打磨 + 真机验证准备）

## Phases

### Phase 1: 技术调研 + 防御式实现 —— ✅ 2026-09-18 完成
> 本机不装 DevEco / SDK，**没有本地编译与运行能力**。所以 spike 降级为：查官方文档（并直接读 `interface_sdk-js` 的 `.d.ts`）确认 API → 代码里做能力探测与降级 → CI 构建校验 → **真机实测仍待 M6**。
- [x] 文本测量与分页：**推翻原假设** —— 不用 `@ohos.measure` 逐段测量，改用 `@ohos.graphics.text`（`ParagraphBuilder` → `layoutSync` → `getLineMetrics()` 直接给每行 `startIndex/endIndex`），一次排版即可切页
- [x] `util.TextDecoder` GB18030：**已停用**，改自研纯 TS 解码路径（`engine/text/Utf8Decode.ets` + `Encoding.ets` 探测），保证 CI 可测
- [x] `@ohos.zlib` 能否处理 zip：**结论 = 不用它**，自研中央目录 + raw inflate（理由：只有自研才能在 CI 里用真实 deflate 数据验证）
- [x] 章节取文本：用**字符偏移**（GBK 场景字节偏移对不上，见 findings）
- [x] **辟谣**：博客里流传的 `onTextLayout` / `TextLayoutResult` / `ReaderController` 等 API 官方不存在，一律以 `.d.ts` 为准
- **Status:** done（结论入 `findings.md`「调研结论 A~E」）

### Phase 2: 工程骨架（手写，不用 DevEco 向导）—— ✅ 2026-09-18 完成
- [x] 建工程目录 + 独立 git 仓库（远端 `Rocktier/Rock-Reader`）
- [x] 手写 hvigor 工程文件：`build-profile.json5` / `oh-package.json5` / `hvigorfile.ts` / `hvigor/hvigor-config.json5`
- [x] 手写 `AppScope/` + `entry/`（`module.json5`、`main_pages.json`、`EntryAbility.ets`、`Index.ets`、`Reader.ets`）
- [x] 包命名 `com.rocktier.rockreader`
- [x] `module.json5` **不声明** `ohos.permission.INTERNET`（核心数据不联网；广告 M7 再加）
- [x] 推到仓库触发 CI，**空工程在 CI 构建通过**：`BUILD SUCCESSFUL`，产物 `entry-default-unsigned.hap` **90 KB**
- [x] 纯逻辑单测接入 CI：`node:test` + esbuild 把 `.ets` 当 TS 编译，17 个用例全绿
- **Status:** done
- 配方与 7 个坑：家族 `findings.md` §13（全家族复用）；CI 文件 `.github/workflows/build.yml`

### Phase 3: 导入与书架 —— ✅ 2026-09-18 完成（MVP 级）
- [x] `filePicker`（`DocumentViewPicker`）选书 → 拷进沙箱 `filesDir/books/<id>/`
- [x] 书架列表（3 列网格）+ 继续阅读卡片（按 `last_read_at` 取最近一本）
- [x] 删除（长按 → 确认弹窗，只删库与沙箱副本，不动原文件）
- [x] 空态（不放营销文案）
- [ ] 分组/重命名、封面上显示单本进度（后置：M5 打磨）
- **Status:** done
- 实现：`data/BookDb.ets`、`engine/importer/BookImporter.ets`、`pages/Index.ets`

### Phase 4: 解析与索引 —— ✅ 2026-09-18 完成（TXT + EPUB）
- [x] TXT：编码识别（BOM → UTF-8 严格校验 → GB18030 兜底）+ 章节正则 + 兜底切章
- [x] 导入时建章节索引落 relationalStore（字符偏移 + UTF-8 字节偏移都存）
- [x] 取章：按**字符偏移**（GBK 场景字节偏移对不上，见 findings）
- [x] EPUB：自研 zip 中央目录 + raw inflate → container.xml → OPF → NCX/nav → XHTML → 纯文本
- [ ] 解析移入 `taskpool`（当前同步执行）——**实测数据不支持现在做**：真实书整本解析 7ms、全书解压转文本 22ms，远小于一帧感知阈值；真机若遇超大书卡顿再上
- **Status:** done

### Phase 5: 阅读页 —— ✅ 2026-09-18 完成
- [x] **横滑分页（默认模式）**：`TextPaginator` 一次 `layoutSync` 取每行区间 → 页表；页表按 `layoutKey` 缓存 → 翻页零测量
- [x] 交互：点两侧翻页 / 点中间浮出细栏 / 横滑翻页（淡出→换页→淡入 + 方向位移）
- [x] 目录浮层（跳章）、章节导航、分段进度条（Nothing 式每 10% 一格）、页脚等宽数码
- [x] 进度落库：章内每 5 页 + 切章必落 + `onPageHide`/`aboutToDisappear` 立即落
- [x] 字号/行距/边距档位切换（返回阅读页自动重排，**按字符偏移复原位置，不跳页**）
- [x] 昼/夜主题（运行时切换，与系统深浅色解耦）
- **Status:** done
- 实现：`engine/paginator/*`、`pages/Reader.ets`、`pages/Settings.ets`、`data/ReaderPrefs.ets`、`common/{LayoutStyle,Theme}.ets`

### Phase 6: EPUB（**已并入 v1**，党哥 2026-09-18 拍板）—— ✅ 2026-09-18 完成
- [x] zip 解析：**自研**中央目录 + raw inflate（`engine/zip/`）——理由：`@ohos.zlib` 设备才有、CI 里无法验证
- [x] `container.xml` / OPF / NCX / nav 解析（自研极小扫描器，`engine/epub/Xml.ets`）
- [x] XHTML → 纯文本（丢 head/style/script、实体还原、段落留空行；**v1 不解析 CSS**）
- [x] 复用同一个 `Paginator`（TXT 与 EPUB 共用分页/进度/设置管线）
- **Status:** done
- 真实出版 epub 实测（calibre 3.44 生成，3.4MB / 103 条目 / 14 章 / 11.7 万字）：解析 7ms，转文本 22ms，目录标题全对
- 过程中逮到两个真 bug（均已写回归测试）：① 嵌套 NCX 按顺序配对 → 整本目录错位一章；② 小节标题（带 `#fragment`）盖住章级标题
- ⚠️ 若 Reader Kit 开通条件核实通过 → 可用 `ReaderKitParser` 适配器替换（`BookSource` 接口位已留）

### Phase 7: 打包与交付
- [x] **发布流程（2026-09-18 实测通过）**：`git tag vX.Y.Z && git push origin vX.Y.Z` → CI 自动跑单测 + 编译 + **建 Release 并挂 HAP + SHA256SUMS**
  - 带连字符的 tag（如 `v0.1.0-alpha.1`）自动标记为 Pre-release
  - Release 说明里写明产物真相（product=ci / OpenHarmony / 未签名 / **不能装鸿蒙手机**），防止被误当可安装包分发
  - 验证方式：临时 tag `v0.0.1-compile-check` 端到端跑通后已删除（仓库当前无 tag / 无 release）
  - ⚠️ 发版时机仍遵守家族规矩：**党哥下令才打 tag**（准则第九章）
- [ ] **正式 HarmonyOS 包**（`default` product）：需党哥用华为账号下载 command-line-tools（Linux x64，登录门禁）→ 给我国内可访问直链 → 接进 CI
- [ ] **已签名可安装包**：需 AGC 调试证书（.p12/.cer/.p7b）+ **每台测试机注册 UDID**
- **Status:** in_progress（发布流程已通；正式包待 SDK）

### Phase 8: 真机验证（**M6 的剩余部分，本机做不到**）
- [ ] 冷启动实测 ≤1s（CI 只能证编译与体积，启动耗时必须真机）
- [ ] 翻页流畅度 / 掉帧（`layoutSync` 在真机上的实际耗时）
- [ ] 大文件（50MB+ TXT）导入耗时与内存峰值
- [ ] 系统字体缩放下排版是否与测量一致（**最高风险项**：测量用 `graphics.text`、渲染用 ArkUI `Text`，两者断行必须一致，否则页面会溢出）
- [ ] 昼/夜主题、档位切换的真机观感
- **Status:** pending（等设备 + 正式包）

## Key Questions
1. ~~首版格式范围？~~ → **v1 = TXT + EPUB**（党哥 2026-09-18 拍板）
2. 阅读器要不要支持 PDF？→ **不做**（Reader Kit 也不支持；PDF 是另一套渲染）
3. ~~远端仓库名？~~ → **已定 `Rocktier/Rock-Reader`**（PUBLIC，已多次 push）
4. **待党哥定**：软著 / 隐私政策文本、首发定价（若要买断）、是否做「继续阅读」元服务卡片（M7+ 候选）
5. **待核实**（不阻塞开发）：Ads Kit 是否需 AGC 开通/签约；华为审核对广告位与未成年人保护的具体要求

## Decisions Made
| Decision | Rationale |
|----------|-----------|
| 纯本地离线，零联网，不做书源 | 党哥定的边界 A；对齐家族铁律 3 |
| 不申请 `ohos.permission.INTERNET` | 铁律 3；无账号、无同步、无统计 |
| 渲染用 ArkUI `Text`/`Span` 自绘分页，不用 Web 组件 | Web 组件重、慢，违背"极致小 / 极致快" |
| 大文件不整体读入，走字节偏移索引 + 随机读 | 避免 OOM；几十 MB TXT 也能秒开 |
| 优先不引三方库（zip / 编码必要时自己写最小实现） | 铁律 2：HAP ≤5MB |
| 解析、分页走 `taskpool` | 铁律 1：UI 线程不干活 |
| **只支持 HarmonyOS 6+**（`compatibleSdkVersion = 20` / `targetSdkVersion = 24`），放弃 HarmonyOS 4 | 党哥 2026-09-18 定：4.x 存量 <1%；单包更小、无 API 差异分支，贴合铁律 1、2 |
| 家族命名前缀 **Rock**（中文 Rock阅读 / 英文 RockReader） | 党哥 2026-09-18 定 |
| **本机不搭鸿蒙环境**，只写代码；工程文件手写，不用 DevEco 向导 | 党哥 2026-09-18 定；构建与校验全靠 CI |
| 三个 spike 改为"文档调研 + 防御式实现"，实测等首次 CI 构建 / 真机 | 本机无编译与运行能力，不能本地实测 |
| ~~首次 push 暂缓~~ → **已于 2026-09-18 完成首次 push**（4 个 commit） | 远端已有台账与 README；下一步补 CI workflow 与工程骨架 |
| **zip / inflate / XML 全部自研**（不用 `@ohos.zlib`、`@ohos.xml`） | 本机无鸿蒙环境：设备 API 只能"上真机碰运气"；自研纯 TS 能在 CI 里用**真实 deflate 数据**与**真实出版 epub** 验证。代价：多写约 500 行，收益：EPUB 链路第一次上真机前就已经被证明是对的 |
| **排版按"章"在主线程序列化执行**（暂不做 taskpool） | 实测：整本 11.7 万字解压+转文本 22ms，单章 `layoutSync` 更小；taskpool 会引入传递 `LineMetrics`/`FontCollection` 的跨线程风险，收益不抵风险。真机若卡再上 |
| **EPUB 段落模型 = 纯文本 + 空行分段**（不做富文本/标题样式） | 与 TXT 共用同一条分页/进度/设置管线；v1 不解析 CSS。代价：EPUB 标题不加粗。升级路径：`Paginator` 已按"文本 + 样式"接口预留 |
| **主题写在 TS 色板里，不用资源限定符** | 主题由用户在应用内选（昼/夜），必须与系统深浅色解耦；`resources/dark/` 只能跟随系统 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| `arkts-no-obj-literals-as-types` / `arkts-no-untyped-obj-literals` | 1 | `Array<{start:number;end:number}>` 这类**对象字面量不能当类型**；改为共用 `PageRange` 接口，字面量先赋给有类型的局部变量再 push |
| `10505001 Property 'opacity' is not assignable to base type 'CustomComponent'` | 1 | 组件字段名撞上了 ArkUI 的属性方法（`opacity`）；改名 `pageOpacity`。**同类陷阱**：`visibility` / `offset` / `position` / `id` / `key` 等都要避开 |
| esbuild `Could not resolve './Xxx'`（无扩展名 .ets 导入） | 1 | `test/run.mjs` 显式加 `resolveExtensions: ['.ets', ...]`；ArkTS 源码里本来就不写扩展名 |
| **嵌套 NCX 目录错位一章**（真实书实测发现） | 1 | 原实现按"text 与 content 出现顺序配对"；父 navPoint 有 navLabel 但无 content 时整体错位。改为 `scanTags` + 栈的**结构级配对**，并加回归测试 |
| **小节标题盖住章级标题**（真实书实测发现） | 1 | 带 `#fragment` 的 navPoint 解析成同一文件路径，先到先得会赢。改为章级（无 fragment）优先，仅当该文件无章级标题时才退回小节标题 |
