# RockReader 项目长期记忆（2026-10-25 压缩版）

## 产品口径：非主动联网（党哥 2026-10-18 拍板）

原文：「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 允许：用户主动点「下载」→ 联网拉音色/字体包 → 之后全程离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见失败可重试、无网时明说、下载记录进 ReaderPrefs（含失败态）。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 音色：凌飞哲 21 需下载（归允许范畴）、聆小珊 13 内置、劳拉 8 英文不面向中文书。三方云 TTS 维持否决。
- 字体下载入口同一范畴。**新增任何系统能力前先对照此表**。

## 华为签名与出包（993 事故后定稿，每次出包必读）

- 个人开发者账号全账号仅 1 张发布证书：RockReader 与 RockJournal **共用** rockreader-v2.p12/.cer，各自建发布 Profile（rockreader-v2.p7b / rockjournal-v1.p7b）。材料在 `F:\AI\HarmonyOS\keys\`，口令同目录 txt。
- build-profile 的 storePassword/keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117），同机可跨工程复制。
- **出包命令（两仓通用）**：`assembleApp -p product=release -p buildMode=release --no-daemon`。不能带 `--mode module`（报 00306054）；**`product` 必须是 `release`**。
- **出包验收三步（缺一不可）**：① `verify-app -inFile X.app -inForm zip` 验签过；② **抠出包内 Profile 看 `type`**——必须 `release` + 本应用包名 + 无 `debug-info`/`development-certificate`（验签通过 ≠ 用的是发布 Profile！）；③ 本地 `keys/*.p7b` 先验。`-outCertChain/-outProfile` 必须是存在的本地路径（/tmp 报 11012005）。
- 993 = Profile 文件非法，官方原因四 = 用了自动签名。`-p product=default` 的 signingConfig 是 DevEco 自动签名（调试证书+调试 Profile），buildMode 只管混淆不管签名。快速二分：先抠包内 Profile。

## 法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。唯一底稿在桌面 `Rock家族-隐私政策-用户协议-数据权利.md`，只留一个底稿。AGC 三字段 = 同一链接 + 不同锚点。今后新增 Rock 系应用改这一篇，不另起页。
- 双写纪律：博客 `#privacy` 章 == 应用内「设置 → 隐私政策」逐字一致。

## 工程铁律（踩过的坑）

- **release 混淆会改名 JSON 落盘字段**（Journal 1.0.2 已带混淆名写盘）：四个开关联合作用，单一白名单拦不住；根治 = 文件级 `-keep` 保护序列化真源，存量 = 读端 fallback 旧名。格式坑：`-keep` 条目不能缩进。Reader 侧无对象 JSON 落盘，不受影响。
- **日期一律本地时区**（todayKey/dateKeyOf），禁用 `toISOString()`（UTC，东八区 00–08 点会写成昨天）。CI 有守门单测。
- **编译唯一可用方式**：自带 hvigorw wrapper 已损坏，必须用 DevEco 自带 node 跑 hvigorw.js；`DEVECO_SDK_HOME`/`JAVA_HOME` 指向 E 盘 DevEco。debug：`assembleHap --mode module -p product=default -p buildMode=debug`；release 见上节。
- **safe-delete 钩子 vs 构建**：单轮删 ≥50 文件被拦截 → 构建报 00308018/00308001，真因在 `.hvigor/outputs/build-logs/build.log` 搜 safe-delete。正解：**改名让开、不删除**。长期建议：钩子豁免 `**/build/**` 与 `.hvigor/**`。
- **浮层「点外部关闭」不牢靠**：面板内容超高时关闭带 layoutWeight 被挤成 0 ⇒ 必须给显式 `×`；关闭带用固定高度（`SETTINGS_STRIP_VP=88`）；固定内容移进 Scroll；Scroll 用 `layoutWeight(1)` 且父链每层高度确定。`constraintSize({maxHeight})` 对 Scroll 无效。
- **@Builder 值参数不随 @State 重跑**（家族级，本族第 4 次同型坑）：选中态变了 UI 不更新 ⇒ ForEach key 带状态后缀，或直接调用拆 if/else。同族：日历染色 / 收藏星 / 胶囊剧透 / 编辑后列表 / 筛选 chip。**凡是「数据变了 UI 不更新」，先怀疑 key 少带了变化的那一位。**
- **UIAbility 基类没有 onConfigurationUpdate**：写 `super.` 能编译但运行时抛错，表现为窗口存在但内容全空（黑屏）。
- **ForEach item 无确定宽度时 `width('100%')` 回退成父级全宽**（Journal 统计页柱状图 12 个月并排铺开、只有第 0 个在屏内）：item 加 `layoutWeight(1)`。
- 图表数据顺序：左→右 = 过去→现在（newest 压轴），必须体现在单测里。
- 模拟器：dpr=3.5、视口≈359vp；**会自动锁屏**（黑屏截图 66908 字节是特征值；解锁 `keyEvent Power` + `swipe 628 2680 628 700`，不稳定会反复锁）。排查先确认不是锁屏。shell 无 wm 命令 ⇒ 横屏断点一律抽纯函数 + 单测守（shelfColsOf / readingMarginOf / formPadOf）。
- hdc/uitest 要诀：设备绝对路径需 `MSYS_NO_PATHCONV=1`；本地路径用相对（cd `/f/AI/HarmonyOS`）；键盘弹出后输入框位移，必须重新 dumpLayout 再 inputText；DEL = `keyEvent 7`；状态栏 y<136 吞点击；多步连点间隔 2~3s。
- 测试基线：Reader 185/185、Journal 136/136。
- tag：Reader v1.0.1~1.0.5、Journal v1.0.0/v1.0.2/v1.0.4（**本地未 push**；push 会触发 CI 建 GitHub Release，发版时机听党哥）。
