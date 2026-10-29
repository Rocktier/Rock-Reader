# Rock 家族长期记忆（2026-10-28 精简版）

> 只记**可执行**知识（命令、路径、判据、禁令）。过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读（RockReader）+ Rock私记（RockJournal）**两个仓**。
> 详细背景见 `2026-10-27.md`（993 排查全过程）与 `2026-10-28.md`（1.0.6 收口）。

## 一、产品口径：非主动联网（党哥 2026-10-18 拍板）

「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 用户主动点「下载」→ 联网拉资源 → 之后离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见失败可重试、无网时明说。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 音色：凌飞哲 21 需下载、聆小珊 13 内置、劳拉 8 英文不面向中文书。三方云 TTS 维持否决。
- **新增任何系统能力前先对照此表。** 麦克风（1.0.6）不算联网 —— 本地传感器。

## 二、签名与出包（两次 993 后定稿，**每次出包必读**）

- 个人开发者账号全账号仅 1 张发布证书：两应用**共用** `rockreader-v2.p12/.cer`，各自建发布 Profile（`rockreader-v2.p7b` / `rockjournal-v1.p7b`）。材料在 `F:\AI\HarmonyOS\keys\`（不进 git）。
- build-profile 的 storePassword/keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117）。
- **出包命令（两仓通用）**：`assembleApp -p product=release -p buildMode=release --no-daemon`。不能带 `--mode module`（报 00306054）；**`product` 必须是 `release`**（buildMode 只管混淆，不管签名）。
- 🚦 **上传前必须跑闸门**：`pwsh scripts/verify-upload.ps1`（两仓各一份，已接进 `build-release.ps1`，不过就 throw）。实测：unsigned 包 ⇒ FAIL+退出码 1；signed 包 ⇒ 全 PASS+退出码 0。
- **交付纪律**：桌面/文件夹**只留一个**待传包（signed/unsigned 并排是常态，只在产物目录里挑包 = 自找 993）。旧包移入备份文件夹，不删。
- **上传纪律（第 0 步，只能靠人）**：先确认 **AGC 后台当前应用 = 该应用**（Reader `com.rocktier.rockreader` / Journal `com.rocktier.rockjournal`）。包侧全绿也发现不了传错栏目。
- 排查手册：`docs/AGC-993-排查手册.md`（Reader 仓）。桌面另有《上传前自检.txt》。

### 993 = Profile 文件非法（家族级，**已栽两次，成因不同**）

官方四成因：① Profile 被删；② Profile 不属于该应用；③ Profile 失效；④ 被自动签名。工程侧两条：**products[].signingConfig 必须指向发布签名**；**签名写在 hvigorfile.ts 的 overrides 里不被认可，必须写进 build-profile.json5**。

- **栽 1（10-25）= ④**：出包写了 `-p product=default` ⇒ 自动签名 ⇒ Profile `type=debug`。改 `product=release` 重打即好。
- **栽 2（10-27）= ②「传到错误的应用栏目下」（真凶）**：把 Rock阅读 的包传到 AGC「Rock私记」栏目下 ⇒ bundle-name 对不上 ⇒ 993。切到「Rock阅读」重传通过。
  ⚠️ 期间曾误判成"传了 unsigned 包"（诱因是产物目录 signed/unsigned 并排、文件名只差三个字母）。**教训：结构上像的诱因 ≠ 真凶**。
- **闸门的能力边界（家族铁律）**：闸门只能验**包**，验不了「传到哪个应用下」⇒ **包侧全绿而仍 993 ⇒ 问题在包之外**，先查上传目标应用。
- **Journal 侧同源 bug（已修）**：`build-release.ps1` 曾用 `-like "*signed*"` 挑产物，**"unsigned" 里也含 "signed"** ⇒ 会挑到 unsigned 包。已改 `-like "*signed.app" -and -notlike "*unsigned*"`。
- **判别口诀**：抠包内 Profile（`hap-sign-tool -outProfile` 找 `"type":"\w+"`）分流 —— `debug`=用错 product；`release` 但包名不匹配=拿错 Profile；过期=Profile 失效；**包侧全绿仍 993 ⇒ 先查上传目标应用**。

### 出包验收三步 + 工具坑（家族级）

- **① 验签**：`app_check_tool.jar` **已失效**（报 9132101）⇒ 用 `hap-sign-tool.jar verify-app -inFile X.app -inForm zip -outProfile <本地路径> -outCertChain <本地路径>` ⇒ `Digest verify result: true` + `verify-app success`。无 `verify-hap`；`-inForm` 只接受 `bin/elf/zip`。
- **② 抠包内 Profile 看 `type`**：必须 `release` + 本应用包名 + 无 `debug-info`/`development-certificate`。⚠️ p7b 是 PKCS#7 容器，JSON 内嵌二进制里 ⇒ **不能用 `LastIndexOf("}")`**，要从第一个 `{` 起做**带字符串感知的花括号配对**。
- **③ 本地 p7b 先验**：包内 Profile 与 `keys/*.p7b` 的 **md5 逐字节一致**。`-outProfile/-outCertChain` 必须是存在的本地路径（/tmp 报 11012005）。
- **PowerShell 三坑**：① `.ps1` 必须 **UTF-8 带 BOM**（PS 5.1 按 ANSI 读无 BOM ⇒ 中文乱码 ⇒「意外的标记 }」）；② 跑 java 工具**别用 `& java ... 2>&1`**（stderr 被转成错误记录，`Stop` 下直接中断）⇒ 用 `Start-Process` + `-RedirectStandardOutput/-RedirectStandardError`；③ `Start-Process`：参数含空格自己加引号；四项 proxy 同存抛「字典中的关键字重复」⇒ 临时摘掉。
  ⚠️ **Git Bash 里 `pwsh xxx.ps1` 被安全策略拦** ⇒ 一律用 PowerShell 工具调用。
- **release 构建偶发失败**：第一次跑可能 11 秒就 `Failed :entry:default@CompileArkTS` 且**日志无任何 ERROR 行**（真因不明）⇒ **原样重跑一次就 BUILD SUCCESSFUL**。遇「无信息失败」先重跑，别改代码。
- ⭐ **`.app` 的 md5 每次打包都变（签名块含时间戳）⇒ 不能用 md5 判断「包有没有变」**。
  md5 只适合当**指纹记录**（记下某一次包的 md5，便于日后核对是不是同一个）。
  要判断两个包是否等价 ⇒ **解包逐文件比**：`unzip X.app` → 得 `entry-default.hap`/`pac.json`/`pack.info`；
  再 `unzip entry-default.hap` → 比 `module.json` / `ets/modules.abc` / `resources/**` 的 md5。
  2026-10-28 实测：两个 .app 的 md5 不同，但 hap 内**所有内容文件逐字节相同** ⇒ 差异只在签名块。
  （顺带证实：`module.json5` 里的注释不进 hap ⇒ 改注释不必重新出包。）

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。**博客在党哥自己的站上，代码改不到 ⇒ 改动要给党哥「照抄文本」**。
- 双写纪律：博客 `#privacy` 章 == 两仓应用内 `pages/Privacy.ets` == 逐字一致。
- ⚠️ **新增权限 ⇒ 必须同步隐私政策**（1.0.6 踩到）：加麦克风后第四节原写「两款应用都不申请任何权限」⇒ **政策与实现不符 = 拒审理由**。已改两仓 `Privacy.ets`（70 段，逐字一致）；**博客侧待党哥手动同步**，文本见 `RockJournal/docs/blog-privacy-sync-1.0.6.md`。
  **纪律：以后任何新权限/新数据形态 ⇒ 同一提交内改完应用内两仓 + 产出博客待同步文本。**

## 四、工程铁律（踩过的坑）

完整清单（混淆 / 编译 / safe-delete / 浮层 / @Builder / ArkUI V1 分支陷阱 / form 卡片三铁律 / 沙箱写入）
⇒ 见同目录 **`reference-arkui-pitfalls.md`**。

**最要紧的 4 条（背下来）**：
1. **release 混淆会改名 JSON 落盘字段** ⇒ 文件级 `-keep` 保护序列化真源（`-keep` 条目**不能缩进**）。
   ⚠️ **`-keep` 还要保护「按名反射的跨模块契约」** —— 1.0.6 加了 `-keep ./src/main/ets/data/AsrService.ets`
   （`RecognitionListener` 五个方法名由系统 SDK 按名字回调，混淆改名 ⇒ 语音功能**静默失效**：能点、能进「在听」、永远等不到文字、零报错）。
2. **ArkUI V1 分支条件陷阱（家族级最重要发现）**：V1 是「状态变更 → 局部刷新」，**build() 不整体重跑，`if` 的分支条件按首次求值定型**；
   依赖插桩只认「表达式里直接读 @State」，藏进 getter/方法体里的访问**追不到** ⇒ 条件里**就地读 @State**。**@Computed 救不了**（本族是 V1）。
   「数据变了 UI 不更新」按序查：① ForEach key 少带变化位 ② 分支条件藏在 getter/方法里 ③ 组件高度被 layoutWeight 压成 0。
3. **@Builder 值参数不随 @State 重跑**（已第 6 次同型）⇒ ForEach key 带状态后缀 / 拆 if/else / 版本号 key 强制重建。
4. **safe-delete 钩子**：单轮删 ≥50 文件会拦（报 00308004 Unable to delete entry\build）⇒ **把 `entry/build`、`.hvigor` 改名让开再构建，不要硬删**。
5. **⭐ 浮层状态机铁律（2026-10-28 夜，两次重构才收敛）**：要让「浮层开着时后台行为停」，
   **不要**在「开浮层时暂停 / 关浮层时恢复」—— 那要在**每一处** `showXxx` 赋值点同步两套状态，漏一处就是幽灵 bug。
   ⇒ 改成**到点才判断**（在定时器回调里就地判 `if (浮层开着) return;`）：**状态只有一处，没有影子状态**。
   配套：浮层与控件**不能叠在同一位置**（菜单 bottomBar 与浮条叠着会互相吃掉落点）；
   一个按钮覆盖多态时，**按了会发生什么必须写在按钮上**（OFF→`滚屏`/RUNNING→`停滚屏`/PAUSED→`继续滚屏`），
   ⚠️ **PAUSED 必须映射到「继续」不能映射到「关掉」**。
6. **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续上（通勤场景）。
   用独立的 `suspended` 标志与「用户主动暂停」区分 —— 都用 PAUSED 会让用户以为自己按过暂停。

### ⭐ 验证层的四条工具坑（2026-10-28 晚，release 包实测现踩）
1. **debug 包通过 ≠ release 包通过** —— release 有混淆，**必须单独实测**。
   实证：混淆**没**破坏 SDK 按名回调的接口（`SpeakListener.onStart/onComplete` 照常触发）
   ⇒ Reader 仓**不必**给 TtsEngine 加 -keep（与 Journal 的 ASR 不同，不要盲目类推）。
2. **「日志没出现」≠「代码没执行」** —— `hilog` buffer 会被系统日志冲掉
   （3 分钟的系统日志就能冲没应用日志）。查应用日志必须**重启应用后立刻抓**，或先 `hilog -r`。
3. **`uitest dumpLayout` 不输出 Image 节点** ⇒ 判断「图标在不在」要**截图**（`uitest screenCap`），
   否则会把「dump 里没有」误判成「入口没渲染」。
4. **自动化摸朗读入口要先开菜单**：topBar/bottomBar 都在 `if (this.showMenu)` 浮层里；
   直接点 topBar 坐标会落到正文 ⇒ **触发翻页**（症状极具误导性）。

- **日期一律本地时区**，禁用 `toISOString()`（UTC，东八区 00–08 点写成昨天）。CI 有守门单测。
- **编译唯一可用方式**：自带 hvigorw wrapper 已损坏，必须用 DevEco 自带 node 跑 `hvigorw.js`；`DEVECO_SDK_HOME`/`JAVA_HOME` 指向 E 盘 DevEco。
- **测试基线**：Reader **229/229**（2026-10-28 夜：自动滚动 13 + AVSession 12 + 其余 204）；Journal **226/226**（1.0.6 新增 87 条）。

## 五、发版与版本状态

- tag：**2026-10-29 全部补齐并 push** —— Reader `v1.0.1~v1.0.8`（+`v0.1.0-alpha.1`/`fonts-v1`）、Journal `v1.0.0`/`v1.0.2~v1.0.6`（**本来就没有 1.0.1 这一版**）。
  push main 只跑编译校验+单测；**push tag v\* 才触发 `gh release create`**（编译失败则不执行）⇒ **CI 未修前 tag 推了也只有版本标记、没有 GitHub Release**。
  ⚠️ Reader 的 `fonts-v1` 本地与远端指向不同 commit（本地 0a3f3e5 / 远端 ed8e0c8）⇒ `git push --tags` 会被拒，**这是正常的**（字体包 tag 与版本发布无关，别动它）。
- Reader **1.0.6（code 1000007）2026-10-26 已提交 AGC，党哥确认通过**；**1.0.7（code 1000008）2026-10-27 22:38 已提交 AGC，10-28 审核已通过 ✅（已上架）**。
- **Reader 1.0.8（code 1000009）2026-10-28 23:27 出包完成**：两项新增 = ① 自动滚动（滚屏）② AVSession 媒体会话（回后台朗读不再即停）。
  release 包 md5 **`01257D024A494A5D9D638653B1B5C441`** / sha256 `2FB65553…15E821`，2,366,245 字节；闸门**全 PASS（13 项）**；桌面 `Rock阅读-1.0.8-上架.app` + `Rock阅读-1.0.8-上传前自检.txt`；上架说明 `docs/release-notes-1.0.8.md`。
  ✅ **已提交 AGC，2026-10-29 审核通过 ✅（已上架）**。
  ⚠️ `module.json5` 的 `backgroundModes` 合法值是 **`audioPlayback`**（写 `audio` 报 00303038）；它是后台模式声明**不是权限** ⇒ 零权限叙事不受影响，**隐私政策本次无需改动**。
  ✅ **AGC 上不需要为 backgroundModes 勾任何东西**（2026-10-28 查证更正，党哥找不到是因为**那个入口根本不存在**）：
  `backgroundModes` 不是 AGC 审批项；需 AGC 申请的是 `KEEP_BACKGROUND_RUNNING`，仅当调 `backgroundTaskManager.startBackgroundRunning()` 时才需要（本应用没调，保持零权限）；
  本应用走 AVSession 播控中心路线，release 包实测回后台朗读继续。**传完包去「应用上架 → 软件包管理」看该包的「上架自检」报告** —— 那才是权威待填清单。
  🎯 **1.0.8 已过审 = 上述结论的实证**（声明 `backgroundModes` 不勾任何东西、隐私政策一字未改，直接过审）⇒
  「新增权限 ⇒ 必须同步隐私政策」那条铁律**不适用于后台模式声明**（它不是权限、不采集数据）。
- Journal **1.0.5（code 1000006）** ✅ **10-26 提交 AGC、10-27 审核已通过（已上架）**。
- **Journal 1.0.6（code 1000007）** ✅ **2026-10-28 20:31 出包完成 → 10-29 审核通过（已上架）**：四项新增 = 多日记本 + 每日提示 + 自定义模板 + 语音转文字（只落文字不存音频）。release 包 md5 **`D7CED482E483D2A42398FF8BB6B33FA2`** / sha256 `18D537F6…F15AC4`，326,692 字节；闸门**全 PASS**（出包脚本内 + 桌面副本复跑）。上架说明 `docs/release-notes-1.0.6.md`；**博客隐私政策待党哥手动同步**（`docs/blog-privacy-sync-1.0.6.md`）。

## 六、CI 现状（党哥拍板「CI 不急」）

- **Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红**。根因：CI 用**公开 OpenHarmony SDK**，而 `@kit.CoreSpeechKit`、`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 报 10505001 / 10311003。后果：编译校验形同虚设，**打 tag 也不会发 GitHub Release**。
- **已排除**：注入 hms kit（hvigor 要 `compileApiVersion>9 && isHarmonyOS() && getHmsArkDir()`，OpenHarmony 永远拿不到）；改 runtimeOS 被 00303038/00303313 卡死；工程内桩被 `arkts-no-untyped-obj-literals`（10605038）拦。
- 党哥判断：「鸿蒙所有的应用开发都是在本机上进行」⇒ **CI 修复暂缓**。将来要修：CI 工作区把 kit 的类型声明**内联到消费文件顶部**（ArkTS 要求同文件），再改 import。
- ⭐ **发 Release 不盯（党哥 2026-10-29 定）**：push tag 之后**只推不监控** —— 不去等 CI 跑完、不去查 Release 有没有生成。
  **隔一段时间、等下一个任务开始时，再回头看那批 CI run 成功没有即可**（`gh run list`）。
  ⇒ 我做完「推 tag」这件事就可以收工汇报，**不要为了确认 CI 状态而空转等待**。
  10-29 推了 8 个 tag（Reader v1.0.1~v1.0.8 补 7 个 + Journal v1.0.3~v1.0.6 补 4 个），
  按此规则**不检查**，留到下个任务开头再看。

## 七、产品对标与迭代方向（Rock私记 vs 标杆）

主标杆 **Day One**（Apple Design Award / 4.8 分）。完整对标表（A 类待做项 / B 类联网取舍 / C 类我们领先）
⇒ 见同目录 **`reference-roadmap.md`**。

- **A 类·本地零联网（优先做）**：① 语音转文字 ✅1.0.6 已实现 ② 位置标签 ⬜ ③ 写作提醒 ⬜ ④ Markdown 双向 ⬜ ⑤ 自定义模板 ✅1.0.6 ⑥ 多日记本 ✅1.0.6 ⑦ PDF 导出 ⬜ ⑧ 每日提示 ✅1.0.6
- **B 类·需联网**（云同步 / 云端 AI / IFTTT）—— 与第一节口径冲突，**主动取舍，不是落后**。
- **C 类·我们领先（卖点）**：全量本地加密（Day One 免费版只传输加密）、时间胶囊硬封存（独占）、完全离线、不绑云账号。
- **坚决不做**：云同步 / 云端 AI。

## 八、ASR（Core Speech Kit）家族知识

**能力边界（官方口径）**：只有**中文普通话**、只有**离线模型**（短 ≤60s / 长 ≤8h）；**模拟器没有离线引擎 ⇒ 识别效果必须真机验**；仅中国区 Phone/Tablet。

**三个必踩的坑**
- **① `online` 名与值相反**：.d.ts 原话 _"**1**: offline"_ ⇒ **1 = 离线**（0 = 联网，未支持）。网上教程写 `online: 0` 表示离线是错的；与 TtsEngine 的 `TTS_ONLINE_MODE=1` 同口径，可交叉验证。
- **② `StartParams.extraParams['recognizeMode']` 必须显式给 0**：0 = **引擎自己开麦**（只要 MICROPHONE 权限，不必自己 AudioCapturer 喂 PCM）；**省略会默认走 1（外部 writeAudio）⇒ 起了引擎却没声音进来**。⚠️ 键名是字符串，编译器查不出。
- **③ 权限结果类型写不出名字**：`PermissionRequestResult` **没有导出到 `abilityAccessCtrl` 命名空间**（全 SDK .d.ts 都搜不到，只在 DevEco 提示用的 `api-version/AbilityKit.json` 里）⇒ **靠 `const res = await ...` 推断拿它**。

**固定套路**：监听器 5 个方法全必填（先 `const self=this`、字面量落接口变量、方法语法）；`createEngine` 用**回调版**，成功时 **err 是 undefined 不是 null**；结果累积 = **isFinal 累加 + 非 final 取最后一条**（引擎"越修越准地重发"）—— 留纯逻辑层，真机若发现是累计全文，改 `collectFinalText` 一行即可。

**没真机时的验证策略（可复用到任何"必须真机"的能力）**
1. 纯逻辑抽出（不引 @kit）⇒ esbuild + node:test 单测；
2. **用真 SDK 编译**（`-p product=default`，runtimeOS=HarmonyOS）验 API 签名 —— CI 的 OpenHarmony SDK 验不了；
3. **"用不了"当一等公民**：引擎起不来 ⇒ UNREADY + 按钮**禁用但保留** + 如实文案；
4. **按名反射的接口实现加 `-keep`**（混淆改名 ⇒ 静默失效）；
5. 上架说明一个字不提，直到真机验过。
