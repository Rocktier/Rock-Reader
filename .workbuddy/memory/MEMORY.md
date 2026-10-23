# RockReader 项目长期记忆

## 产品口径：非主动联网（党哥 2026-10-18 拍板）

**原文口径**：「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

边界（后续所有功能的设计前提）：

| 行为 | 判定 |
|---|---|
| 用户主动点「下载」→ 联网拉音色包/字体包 → 之后全程离线使用 | ✅ 允许 |
| 主要功能联网（云 TTS 每次朗读联网合成、在线书城、账号云同步） | ❌ 不允许 |
| 应用自己发起联网（启动检查更新、静默下载、遥测上报） | ❌ 不允许 |

UI 义务（凡是联网下载功能都要做到）：
1. 入口明示「联网下载」+ 资源大小，不拿「下载」二字含糊过去；
2. 下载进度可见、失败可重试、失败原因说人话；
3. 无网络时明确提示「此功能需要联网」，禁止静默失败；
4. 下载记录进 ReaderPrefs（含失败态），恢复网络后不重复下载已有资源。

当前适用范围：
- **音色**：凌飞哲（person 21）downloadVoice 归入允许范畴，需做下载 UI；
  聆小珊（13）内置无需下载；劳拉（8）英文音色不面向中文书。
- **字体**：设置面板「字体下载」入口同一范畴，同样要明示联网。
- **三方云 TTS**（Azure/讯飞等）：维持否决——那是主要功能联网，性质不同。

## 华为上架签名（两应用共用，2026-10-20 坐实）

- **个人开发者账号全账号只有 1 张发布证书** → 第二个应用（Rock私记）不另申请证书，
  复用 rockreader-v2 的 p12/cer，只为该包名单建发布 Profile（p7b）。
- 材料落位 `F:\AI\HarmonyOS\keys\`：rockreader-v2.p12/.cer（共用）、
  rockjournal-v1.p7b（Rock私记专属）；p12 口令在同目录 rockreader-v2-password.txt。
- build-profile 的 storePassword/keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117）；
  同机同钥匙的加密串可跨工程复制。
- 验签：`hap-sign-tool.jar verify-app -inFile X.app -inForm zip`（.app 内嵌的是 unsigned hap，
  签名在 .app 层，属正常）。

## 法律文件口径：一个链接覆盖全家族（2026-10-20 定）

- 博客 <https://www.91hym.cn/devs/756.html> 已扩为 **《Rock 家族 隐私政策、用户协议与
  数据权利》**，一篇三章 + 三个锚点 `#privacy` / `#agreement` / `#rights`，
  **Rock阅读 与 Rock私记 共用这一个链接**（原文那句「适用范围：Rock 家族全部应用」
  就是为此预留的）。今后新增 Rock 系应用，改这一篇即可，不要另起新页。
- AGC 三字段 = 同一链接 + 不同锚点。
- 唯一底稿在桌面 `Rock家族-隐私政策-用户协议-数据权利.md`；
  **同一份法律文件只留一个底稿**，多一份就多一处「政策与应用内不一致」的拒审风险。
- 双写纪律：博客 `#privacy` 章 == 各应用内「设置 → 隐私政策」全文，逐字一致。
- **Rock阅读 1.0.3 已于 2026-10-20 审核上架**（链接填的就是 756.html#privacy）。
  RockReader 应用内 Privacy.ets 同日同步为家族版（commit 41bb5cd，版本号未动），
  等下一个版本（1.0.4+）带出；在那之前应用内与网页有短暂不一致，但已上架应用
  一般不复查，风险可接受。

## 其他长期事实

- 官方 Core Speech Kit textToSpeech 音色库总共 **3 个**（SDK 声明 + 官网双源坐实）：
  聆小珊 13（内置）、凌飞哲 21（需下载）、劳拉 8（英文，需下载）。
- 官方无公开试听网页；RockReader 自身即试听器（同引擎最真实）。
- 模拟器实测有 TTS 能力（findings §15 坑 2 作废，§16 留证）；
  凌飞哲在模拟器缺音色包（码 1002300005），真机才能验证下载链路。

## ⚠️ release 混淆会改名序列化字段（2026-10-22 反汇编实证，数据安全级）

RockJournal 的 JSON 落盘字段被 release 混淆改了名 —— **1.0.2 已带混淆名写盘**：

| | NoteMeta 对象字面量的键 |
|---|---|
| debug（不混淆） | `id, date, createdAt, mood, moodText, preview, updatedAt, words, hasImage, imgRef, favorite, tags, unlockAt` |
| release（四开关全开） | `id, date, **m5**, mood, moodText, preview, **l5**, words, hasImage, **n5**, favorite, tags, unlockAt` |

- 单开 `-enable-property-obfuscation` 或单开 `-enable-toplevel-obfuscation` 都**不**改名
  ⇒ 是四条开关联合作用的产物，单一 `-keep-property-whitelist` 拦不住
  （实测 26 字段名白名单：产物与不写逐字相同）。
- **根治 = 文件级 `-keep`**（保护 IndexCodec/NoteBlocks/BackupService 三个序列化真源），
  release 产物字段名已验证回到明文。
- **存量 = 读端 fallback**：NoteMeta 加三个 optional 旧名（m5/l5/n5），
  IndexCodec 明文优先、旧名兜底 ⇒ 1.0.2 用户升级不丢时间戳与图片引用。
- 格式坑：`-keep` / `-keep-property-whitelist` 的条目**不能缩进**（缩进 = 不解析）。
- 迁移守卫单测在 `test/indexcodec.test.ts`（3 条）。
- RockReader 侧无对象 JSON 落盘（显式字符串列名），不受影响，规则文件里写了预警。

## ⚠️ 日期一律用本地时区（todayKey/dateKeyOf），禁用 toISOString（UTC）

东八区 00:00~08:00 时 UTC 还是前一天 ⇒ 用 `new Date().toISOString().substring(0,10)`
做文件名会**写成昨天**。这个坑**出现过两次**：Editor.ets:171 先修过一次，
Settings 的备份/导出两处漏网（2026-10-23 凌晨实测：文件名显示 10-22，实为 10-23）。
CI 守门：`test/notemeta.test.ts`「dateKeyOf 必须产出本地日历日期，不是 UTC」。

## 命令行编译唯一可用方式（2026-10-22 实证）

项目自带 `hvigorw` wrapper **已损坏**（反复 Hvigor cleaning/installing 后静默退出）。
唯一可用命令（bash）：

```bash
export DEVECO_SDK_HOME="E:/Program Files/Huawei/DevEco Studio/sdk"
export JAVA_HOME="E:/Program Files/Huawei/DevEco Studio/jbr"
"/e/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "/e/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

（DevEco 装在 E 盘；NODE_HOME 指向 DevEco node 才有效，/c/Program Files 下没有 Huawei。）

## 世界百佳评审整改（2026-10-22 完成，commit 见 git log "review:"）

- 22 项 = 5×P0 + 9×P1 + 8×P2：代码层全部落地（真做或决策记录）。
- 决策记录收口的：索引增量写（>5MB/p95>50ms 触发）、字体下载联网（四步触发，
  牵动 INTERNET 权限+隐私政策+AGC 标签+商店文案，必须随版本走）、导入 taskpool、
  书架排序切换、导入文案诚实化（NOT_SUPPORTED 撤下 MOBI/AZW3 + PARSE_CRASHED/MOBI_TOO_NEW）。
- **模拟器验证（2026-10-22 晚已完成）**：阅读页三件套（书签/摘录入账，抽屉
  「标记 N」计数实见 1→2）、朗读取读正常（位置 0%→21%）、定时按钮循环
  （关→15→30→60→关）与倒计时递减（15 分→72 秒后 14 分）、语速六档面板。
  动效类（pageTransition/脉冲/浮现）无法静态验证 → 仍需真机/目视。
- **平板断点改为单测守门**：模拟器 shell **没有 wm 命令**（改不了分辨率），
  故把 shelfColsOf / readingMarginOf 抽成纯逻辑进 CI（LayoutStyle，共 5 条断言）。
- tag：RockReader v1.0.1/v1.0.2/v1.0.3 早已存在（指向正确），**v1.0.4 于 2026-10-23
  补打**（阅读 1.0.4 上架包同日产出，桌面三件）；RockJournal 本次补
  v1.0.0/v1.0.2（1.0.1 跳号既成事实不伪造）。**均为本地 tag 未 push**——
  push tag 会触发 CI 建 GitHub Release，发版时机由党哥下令。
- 测试基线：RockReader 182/182、RockJournal 130/130（npm test，esbuild 管道）。
- 复评清创（2026-10-23）：私记 517defa 修版本漂移/importAll O(N²)/备份文案/注释失真
  （见 RockJournal 仓日志）；阅读 8aa0816 修门面失实。教训：删私有方法必须 grep `this.` 全查
  （esbuild 管道不查 ArkTS，漏改一处 10505001）；出包流程加一步看测试报告（红灯包根因）。

## safe-delete 钩子 vs hvigor 构建（2026-10-23 实证，每次出包必踩）

- 钩子按「单轮批量删除 ≥50 文件需确认」拦截，而 hvigor 清编译缓存 / 替换旧产物
  （.app、app-symbol.zip 均为含 ≥50 文件的归档）必然触发 → 构建报 00308018/00308001，
  真因在 `.hvigor/outputs/build-logs/build.log`（搜 safe-delete）。
- 正解：**改名让开、不删除**——`entry/build/release/cache/default/default@CompileArkTS/
  esmodule/release/compiler.cache`、`build/outputs/release/*-signed.app`、
  `build/outputs/release/symbol/release/app-symbol.zip` 逐个 `mv X X.stale` 再重跑，
  其余任务 UP-TO-DATE 秒过；遗留 .stale 待党哥确认后清。
- 长期建议：safe-delete 钩子豁免 `**/build/**` 与 `.hvigor/**`。
- 另：`hap-sign-tool verify-app` 必带 `-outCertChain` / `-outProfile`，否则报 11011008。

## Rock阅读 1.0.4 上架包（2026-10-23 产出，桌面三件）

- `Rock阅读-1.0.4-上架.app`（AGC 传这个，2.3MB）/ `Rock阅读-1.0.4-留底.hap`（3.7MB）/
  `Rock阅读-1.0.4-更新说明.md`（AGC 粘贴版 + 审核员要点 + 两个商店待办：MOBI 文案同步、截图补拍）。
- 内容 = 世界百佳评审整改的用户可见部分：三件套（书签/摘录/全文搜索）、语速六档
  （真接通，Record<string,Object> 类型化字面量）、朗读定时、平板适配、MOBI 诚实化；
  **taskpool 与书架排序是决策否决/推迟，不在其内**。

## ⚠️ 浮层「点外部关闭」是**不牢靠的**——layoutWeight 会被内容挤成 0（2026-10-23 实测）

写齿轮抽屉/面板时，**永远要有显式关闭控件（×）**，不要只靠「点上面那条透出的空白」。
实证：Reader.ets 设置抽屉 = `[关闭带 layoutWeight(1)] + [面板]`，当面板内容总高
（4 行档位 ~457vp + Scroll 限高 420 + 头部）超过抽屉本体时，**关闭带被压成 2px**
（实测面板顶边紧贴状态栏）→ 面板铺满全屏且点不关，只剩系统返回一条出路。
修（四处，缺一不可）：
1. 面板头部加 `×`（accessibilityText「关闭设置」）—— 兜底出路；
2. 关闭带改**固定高度**（本项目 `SETTINGS_STRIP_VP=88`），不再用 layoutWeight；
3. 固定内容（档位行）一并**移进 Scroll**，整面板只留头部固定；
4. 容器内 Scroll 用 `.layoutWeight(1)` 让它能收缩；父链每层都必须**高度确定**
   （缺口 .height('100%')/layoutWeight 一层的，layoutWeight 就解析不出来）。
:::tip `constraintSize({maxHeight})` 不是给 Scroll 限高的正确手段——本项目原写法
（`constraintSize({maxHeight:420})`）在 Scroll 上未生效，且与 layoutWeight 混用会打架。
抄 tocList 的模式：`List/Scroll + layoutWeight(1)` + 父高度确定。

## 图表数据顺序约定：左→右 = 过去→现在（ newest 压轴）

`NoteMeta.monthlyWords` 返回**正序**（out[0] 最早、out[N-1] 是当月），理由：柱状图
从左到右就是时间推进，最新在右才符合读图直觉。曾因实现（最新在前）与页面注释
（最新在右）矛盾而被新写的单测当场抓出来——**凡是图表数据，顺序必须体现在单测里**。

## 模拟器 UI 自动化（hdc + uitest，免鼠标）

`HDC="E:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe"`
- 截图：`shell 'uitest screenCap -p /data/local/tmp/x.png'`；取回：`file recv`
- 操作：`shell 'uitest uiInput click|longClick|inputText|swipe X Y ...'`、
  `keyEvent Back`、`aa start -b <bundle> -a EntryAbility`
- 找坐标：`shell 'uitest dumpLayout -p /data/local/tmp/l.json'` → python 读
  `attributes.bounds`（格式 `[x0,y0][x1,y1]`，本机模拟器分辨率 1256×2760）
- **hdc 会把所有路径与 cwd 拼接** → 本地路径用相对（cd 到 `/f/AI/HarmonyOS` 再传
  `RockReader/...`）；设备绝对路径要 `export MSYS_NO_PATHCONV=1` 挡住 Git Bash 转换
- 状态栏（y<136）吞点击；多步连点会互相干扰 → 每步单独跑，间隔 2~3s

## 横屏/大屏：断点一律走「纯函数 + 单测」，别指望模拟器验证

模拟器 shell **没有 wm 命令**改不了分辨率，所有断点判定必须抽成纯函数从 CI 守：
- `LayoutStyle.shelfColsOf`（书架列数）/ `readingMarginOf`（阅读版心）/ **`formPadOf`**
  （表单页版心单侧补丁，FORM_MAX_VP=560，2026-10-23 加，用于 Privacy/About/Stats/Settings
  四个次级页；UI 层把返回值加进左右 padding，零结构改动）。
