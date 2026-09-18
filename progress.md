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
