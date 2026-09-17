# Task Plan: Rock阅读（RockReader）

> 应用级台账。家族级计划与铁律见 `..\planning\`（harmony-docs 仓库 `.planning/`）。
> 铁律全文：`..\planning\findings.md` 顶部常驻章节。

## Goal
做一个**纯本地、零联网**的鸿蒙电子书阅读器：导入本地书 → 解析 → 分页 → 阅读 → 记住进度。首版打 TXT，跑通全链路后再上 EPUB。

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

### Phase 2: 工程骨架（手写，不用 DevEco 向导）
- [x] 建 `f:\AI\HarmonyOS\RockReader\` + 独立 git 仓库（远端 `Rocktier/Rock-Reader`）
- [ ] 手写 hvigor 工程文件：`build-profile.json5` / `oh-package.json5` / `hvigorfile.ts`
- [ ] 手写 `AppScope/` + `entry/`（`module.json5`、`main_pages.json`、`EntryAbility.ets`、`Index.ets`）
- [ ] 包命名 `com.rocktier.rockreader`
- [ ] `module.json5` **不声明** `ohos.permission.INTERNET`
- [ ] 推到仓库触发 CI，验证"空工程也能构建通过"（这是本机唯一的编译校验手段）
- **Status:** pending

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

### Phase 6: EPUB（TXT 跑通后）
- [ ] zip 解析（优先 `@ohos.zlib`，不行自己写中央目录 + raw inflate）
- [ ] `container.xml` / OPF / NCX 解析（`@ohos.xml`）
- [ ] 章节 HTML → 纯文本/富文本排版
- **Status:** pending

### Phase 7: 打包与交付
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
| ⏸ **首次 push 暂缓**（党哥 2026-09-18 ❌）：本地先写代码，等他下令一次性推 | 未推送期间没有 CI 校验，风险靠"查文档 + 保守写法 + 待验证清单"兜底 |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
|       | 1       |            |
