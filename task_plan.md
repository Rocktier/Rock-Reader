# Task Plan: Rock阅读（RockReader）

> 应用级台账。家族级计划与铁律见 `..\planning\`（harmony-docs 仓库 `.planning/`）。
> 铁律全文：`..\planning\findings.md` 顶部常驻章节。

## Goal
做一个**纯本地、零联网**的鸿蒙电子书阅读器：导入本地书 → 解析 → 分页 → 阅读 → 记住进度。
**v1 范围 = TXT + EPUB 一起上**（党哥 2026-09-18 拍板）；阅读内核**自研为主**，Reader Kit 只留可插拔适配器位。
技术底座与调研结论见 `findings.md`「调研结论（2026-09-18）」；UI 方向 = 家族 Nothing OS 风格（黑白单色 + 点阵数码 + 红点 `#FF4A3D`）。

## Current Phase
Phase 1

## Phases

### Phase 1: 技术调研 + 防御式实现（本机无环境，不能实测）
> 本机不装 DevEco / SDK，**没有本地编译与运行能力**。所以 spike 降级为：查官方文档确认 API 能力 → 代码里做能力探测与降级路径 → **真机/CI 构建后再回填实测结果**。
- [ ] `@ohos.measure` 文本测量与分页：查文档确认可用性与精度；代码留"测量失败则退化为按字符数分页"的兜底
- [ ] `util.TextDecoder` 是否支持 GBK / GB18030：查文档；不支持则自实现 GBK 映射（或先支持 UTF-8 + 手动选编码）
- [ ] `@ohos.zlib` 能否直接处理 zip：查文档；**默认按"不支持 zip 归档"设计**，先写好最小 zip 解析 + raw inflate
- [ ] `fs.read` 按 offset 随机读：查文档确认 API 语义
- [ ] 真机 / 首次 CI 构建成功后，回填 `findings.md` 的「spike 结果」表
- **Status:** pending

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

### Phase 3: 导入与书架
- [ ] `filePicker` 选书 → 拷进沙箱 `filesDir/books/`
- [ ] 书架列表（`LazyForEach`）+ 封面/进度/最后阅读时间
- [ ] 删除、重命名、分组（分组可后置）
- **Status:** pending

### Phase 4: 解析与索引
- [ ] TXT：编码识别（BOM / UTF-8 / GBK）+ 章节正则
- [ ] 首次导入建"章节 → 字节偏移"索引，落关系型数据库
- [ ] 分页：measure 逐段测量 → 页偏移表，缓存当前 ±2 页
- [ ] 全部解析走 `taskpool`，UI 线程只渲染
- **Status:** pending

### Phase 5: 阅读页
- [ ] 排版：字号/行距/段距/字重/简繁（逐步加）
- [ ] 翻页：滚动 + 覆盖翻页（先滚动，仿真后置）
- [ ] 目录跳转、进度条、夜间模式
- [ ] 阅读进度实时落库
- **Status:** pending

### Phase 6: EPUB（**已并入 v1**，党哥 2026-09-18 拍板）
- [ ] zip 解析（优先 `@ohos.zlib`，不行自己写中央目录 + raw inflate）
- [ ] `container.xml` / OPF / NCX / Nav 解析（`@ohos.xml`）
- [ ] XHTML → 段落模型（只认基础标签；**v1 不解析 CSS**）
- [ ] 交给同一个 `Paginator` 排版（与 TXT 共用管线）
- **Status:** pending
- ⚠️ 若 Reader Kit 开通条件核实通过 → 本 Phase 可整块换成 `ReaderKitParser` 适配器实现

### Phase 7: 打包与交付
- [x] **发布流程（2026-09-18 实测通过）**：`git tag vX.Y.Z && git push origin vX.Y.Z` → CI 自动跑单测 + 编译 + **建 Release 并挂 HAP + SHA256SUMS**
  - 带连字符的 tag（如 `v0.1.0-alpha.1`）自动标记为 Pre-release
  - Release 说明里写明产物真相（product=ci / OpenHarmony / 未签名 / **不能装鸿蒙手机**），防止被误当可安装包分发
  - 验证方式：临时 tag `v0.0.1-compile-check` 端到端跑通后已删除（仓库当前无 tag / 无 release）
  - ⚠️ 发版时机仍遵守家族规矩：**党哥下令才打 tag**（准则第九章）
- [ ] `.github/workflows/build.yml`：Linux + `hvigorw assembleHap`
- [ ] 签名走 Secrets，产物上传 Artifacts
- [ ] 单份 `build-profile.json5`：`compatibleSdkVersion = 20`、`targetSdkVersion = 24`（已放弃 HarmonyOS 4，不再出双包）
- [ ] 党哥下令后 push + tag + Release（挂 HAP）
- **Status:** pending

### Phase 8: 真机验证
- [ ] 等党哥自购鸿蒙设备后实测（导入、翻页流畅度、大文件、续航/内存）
- **Status:** pending

## Key Questions
1. 首版格式范围：**只做 TXT**，还是 TXT + EPUB 一起上？（建议先 TXT）
2. 阅读器要不要支持 PDF？（PDF 是另一套渲染，建议不做）
3. ~~远端仓库名？~~ → **已定 `Rocktier/Rock-Reader`**（PUBLIC；已本地 init + remote，首次 push 待党哥下令）

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

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |
