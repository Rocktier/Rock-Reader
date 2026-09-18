# Rock-Reader（Rock阅读）

鸿蒙（HarmonyOS）上的电子书阅读器。属于 Rocktier「Rock」软件家族。

- 中文名：**Rock阅读** ｜ 英文名：**RockReader** ｜ 包名：`com.rocktier.rockreader`
- 格式：**TXT + EPUB**（不打算做 PDF —— 那是另一套渲染）
- 目标系统：**HarmonyOS 5.0.4（API 16）及以上**，`targetSdkVersion = 6.0.0(API 20)`，单框架单包
  （CI 另有一个 `ci` 产物用 OpenHarmony SDK 只做编译校验 —— 所以**CI 的 HAP 装不上手机**）
- 阅读内核**自研**（见下文"为什么自研"），官方 Reader Kit 只留可插拔适配器位
- 字体：**不内置字体文件**，只列系统已装字体供选择（`getSystemFontList`，体积 0，不联网下载）

## 三条铁律（家族统一）

1. **极致快** —— 整章**一次**排版拿全部行区间 → 页表缓存 → 翻页只换字符串、零测量
2. **极致小** —— HAP **115 KB**（预算 ≤5MB）；**0 个三方库**（zip、inflate、XML、UTF-8 解码全部自研）
3. **核心数据不联网** —— 书、进度、设置**永不出设备**；断网时功能 100% 完整；联网只为广告变现（M7，且广告绝不出现在阅读页，用户可用系统联网权限自行选择"无广告"）

## 当前状态（2026-09-18）

| 里程碑 | 内容 | 状态 |
|---|---|---|
| M1 | 工程骨架 + CI 构建 | ✅ |
| M2 | 存储 + 导入 + 书架 | ✅ |
| M3 | TXT 全链路（解析 + 分页 + 阅读页） | ✅ |
| M4 | EPUB（zip + OPF/NCX + XHTML→纯文本） | ✅ |
| M5 | 设置档位 / 目录 / 昼夜主题 / 进度 | ✅ |
| M6 | 打磨 + 真机验证 | 🔶 打磨完成，**真机项待设备** |
| M7 | 广告（Ads Kit，可选模块） | ⬜ 未开始 |

**已验证的**：CI 每轮全绿；纯逻辑单测 **52 个用例**；真实出版 EPUB（3.4MB / 103 条目 / 11.7 万字）解析 7ms、全文转文本 22ms；HAP 115 KB。
**还没验证的**：真机运行时的一切（冷启动、翻页掉帧、字体缩放下排版一致性）—— 本机没有鸿蒙环境，详见 `task_plan.md` Phase 8。

## 为什么把引擎写成"纯 TS"

本机不搭鸿蒙环境，构建与校验全走 CI（家族准则第十四章）。设备 API 在这里等于"上真机碰运气"。
所以 zip 解包、DEFLATE 解压、XML/OPF/NCX 解析、UTF-8 解码**全部自研且不 import 任何 `@ohos`**，
于是它们能在 Node 里被真实数据测穿（`test/`）：

```
pages/       Index（书架）│ Reader（阅读）│ Settings（设置）
data/        BookDb（relationalStore）│ ReaderPrefs（Preferences）
engine/      ← 纯 TS，零 ArkUI / 零设备 API，可 CI 单测
  parser/    TxtParser │ EpubParser │ BookSource（抽象：TXT/EPUB 对阅读页透明）
  paginator/ PageTableBuilder（纯算法）│ TextPaginator（graphics.text）│ PageCache
  zip/       ZipReader（中央目录 + 按需取条目）│ Inflate（RFC 1951）
  epub/      Xml（含结构级 scanTags）│ Opf │ Xhtml │ EpubParse
  text/      Encoding（探测）│ ChapterSplitter │ Utf8Decode
  importer/  BookImporter（选择器 → 沙箱 → 索引 → 落库）
common/      LayoutStyle（**档位唯一真源**）│ Theme（运行时色板）│ Types
```

**关键纪律**：测量与渲染必须共用同一套参数（`common/LayoutStyle.ets` 的档位表是唯一真源，UI 只写序号）。

## 本地验证怎么做（本机无鸿蒙环境）

```bash
npm install          # 只为单测装 esbuild
npm test             # 52 个纯逻辑用例（编码/切章/分页/zip/EPUB/XHTML）
```

对**真实书**的验证（不进仓库，避免版权与体积问题）：

```bash
# 临时脚本把引擎当普通 TS 打包后在 Node 里跑真实 epub
npx esbuild <临时脚本>.ts --bundle --platform=node --format=esm \
  --loader:.ets=ts --resolve-extensions=.ets,.ts,.js --outfile=/tmp/x.mjs
node /tmp/x.mjs /path/to/real-book.epub
```

ArkTS 编译校验只在 CI 做（本机不装 SDK）；单测可以在本机跑，两边用同一套用例。

## 构建与发布

所有构建走 GitHub Actions（本仓库 PUBLIC，不消耗私有仓库配额）：

- **push main / PR** → 单测 + `assembleHap`（product=ci）+ 校验产物真实存在（防假绿）
- **push tag `v*`** → 额外建 GitHub Release，附 HAP + `SHA256SUMS`

```bash
git tag v1.0.0 && git push origin v1.0.0     # ⚠️ 发版时机由党哥下令（家族准则第九章）
```

⚠️ **当前 CI 产物不能装到鸿蒙手机**：它是 `product=ci`（runtimeOS = OpenHarmony）且**未签名**，只用于编译校验。
要出可安装包需两步（都需要党哥操作）：① 用华为账号下载 command-line-tools 并给国内可访问直链；
② AGC 调试证书 + 注册测试机 UDID。

## 许可证与借鉴红线

| 项目 | 许可 | 我们怎么对待 |
|---|---|---|
| KOReader | GPL-3.0 | 只借鉴设计（章节级懒排版、页缓存思路），**不抄代码** |
| Legado「阅读」/ legado-Harmony | GPL-3.0 | 只对标阅读体验；**书源生态一律不碰**（侵权，且违背"核心数据不联网"） |
| Readest | AGPL-3.0 | 只借鉴交互点子；**不采用 WebView 渲染路线** |
| 华为官方 ReaderKit 示例 | Apache-2.0 | 可参考/借鉴（`fileIo` 用法已注明来源） |
| `waylau/harmonyos-tutorial` | 无 LICENSE | **只看 API 形态，不借鉴代码** |

## 文档

| 文件 | 作用 |
|---|---|
| `docs/v1-design.md` | **v1 唯一设计真源**（改动先改它） |
| `docs/ui-mockup-v2.html` | UI 复审稿（浏览器直接打开；1:1 还原已实现的界面） |
| `task_plan.md` | 阶段计划、决策表、错误表（含踩过的 ArkTS 坑） |
| `findings.md` | 调研结论（Reader Kit / 自研排版 / 开源项目对比 / UI 方向） |
| `progress.md` | 每次会话做了什么 |
