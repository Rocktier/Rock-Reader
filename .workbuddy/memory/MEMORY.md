# Rock 家族长期记忆（2026-11-03 精简版 v2）

> 只记**可执行**知识（命令、判据、禁令）。过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读（RockReader）+ Rock私记（RockJournal）**两仓**，外加本地新项目 all2md。
> 深度清单（同目录）：
> `reference-signing.md` 签名出包上传 · `reference-releases.md` 包指纹/版本/测试基线 ·
> `reference-performance.md` 性能六律 · `reference-arkui-pitfalls.md` ArkUI/混淆/编译坑 ·
> `reference-simulator.md` hdc/模拟器工具 · `reference-clouddebug.md` AGC 云调试（密码框黑屏/命令白名单/灌文件死路）· `reference-roadmap.md` 产品对标。

## 一、产品口径：非主动联网（党哥 2026-10-18 拍板）

「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 用户主动点「下载」→ 联网 → 之后离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见、失败可重试、无网时明说。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 麦克风（Journal 1.0.6）不算联网 —— 本地传感器。
- **新增任何系统能力前先对照此表。**

## 二、签名与出包（每次出包必读 `reference-signing.md`）

- 出包 `assembleApp -p product=release -p buildMode=release --no-daemon`（不要 `--mode module`）。
- 上传前必跑 `pwsh scripts/verify-upload.ps1`（不过就 throw），**闸门要跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 后台当前应用 = 该应用（Reader `com.rocktier.rockreader` / Journal `com.rocktier.rockjournal`）。
  **包侧全绿仍 993 ⇒ 问题在包之外**（多半传错栏目）。
- 993 分流口诀：抠包内 Profile 看 `"type"` —— `debug` = 用错 product；`release` 但包名不符 = 拿错 Profile。
- build-profile 的 store/keyPassword 必须是 DevEco 加密串（明文报 00303116/00303117）。
- `.app` 的 md5 **每次打包都变**（签名含时间戳）⇒ 只当指纹记录，不能当「包有没有变」的判据（要解包逐文件比）。
- 版本号规律：`code = 1000000 + (minor + 1)`。**改版本号两处一起改**：`AppScope/app.json5` + `entry/src/main/ets/common/AppMeta.ets`
  （Reader 无 AppMeta，Journal 有；1.0.6 漏改 ⇒ smoke 测试红）。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。
  **博客在党哥自己的站上，代码改不到 ⇒ 改动要给党哥「照抄文本」。**
- 双写纪律：博客 `#privacy` == 两仓应用内 `pages/Privacy.ets` == 逐字一致。
- ⚠️ **新增权限 ⇒ 必须同步隐私政策**（1.0.6 加麦克风后政策仍写「不申请任何权限」= 拒审理由）。
  纪律：任何新权限/新数据形态 ⇒ 同一提交内改完两仓 + 产出博客待同步文本。
- ⚠️ 例外：`backgroundModes` 不是权限、不采集数据 ⇒ 政策无需改（Reader 1.0.8 已过审 = 实证）。

## 四、工程铁律（只列最高频的；全量 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **ArkUI V1 分支条件陷阱（家族最重要）**：`if` 的分支条件按**首次求值定型**，依赖插桩只认表达式里**直接读 @State**；
  藏进 getter/方法体追不到。**@Computed 救不了**（本族 V1）。条件里就地读 @State。
  「数据变了 UI 不更新」按序查：① ForEach key 少带变化位 ② 分支条件藏在 getter/方法 ③ 高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（已第 6 次同型）⇒ key 带状态后缀 / 拆 if-else / 版本号 key 强制重建。
- **划词三条**（1.0.10 实测，细节 ⇒ reference-arkui-pitfalls 第五节）：
  ① Text 上挂自定义长按手势会**抢赢系统选词** ⇒ 长按完整让给系统，入口挂 menuItem；
  ② `onMenuItemClick` **返回 false**（true = 拦截 ⇒ 系统浮动菜单不收）；
  ③ 撤选区 = `Text(content,{controller})` + `setTextSelection(0,0)`（compileSdk 20 无 `clearFocus`）。
  ⚠️ 系统长按中文默认只选 1 字 ⇒ **门槛只能提示，不能拦显式操作**（否则点一下就是死路）。
  ⚠️ **划词不需要升 compileSdk**（`onTextSelectionChange` @since 11，`textSelectable`/`editMenuOptions` @since 12；
  只有 `SelectionContainer` 是 @since 26，划词用不到）⇒ 别再为它改工程配置。
- **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续（通勤场景）；用独立 `suspended` 标志区分主动暂停。
- **浮层状态机**：要让「浮层开着时后台行为停」，**不在开/关浮层时同步两套状态**（漏一处就是幽灵 bug）
  ⇒ **到点才判断**（定时器回调里判 `if (浮层开着) return;`）。状态只有一处，没有影子状态。
  按钮覆盖多态时**按了会发生什么必须写在按钮上**（OFF→滚屏 / RUNNING→停 / PAUSED→**继续**）。
- **锁库三铁律**（Journal 后台即锁）：① **先落盘再锁**（密钥一清 `encrypt()` 返 null ⇒ 防抖窗口内容永远存不下）
  ⇒ `onPageHide` 立刻落盘 + 锁延迟 > 防抖；② 只清密钥不够，还要清内存里的**内容预览**；
  ③ 送解锁页必须 `router.clear()` 再 `replaceUrl`（只 replaceUrl ⇒ 返回键翻回已解密页）。
- **日期一律本地时区**，禁用 `toISOString()`（UTC，东八区 00–08 点写成昨天）。CI 有守门单测。
- **列表装饰竖条不能用 `height('100%')`** ⇒ 吃满 ListItem 变分隔线 ⇒ 固定 20vp + `alignSelf(Start)`。
- 🔒 **release 混淆**：会改 JSON 落盘字段名 ⇒ 文件级 `-keep`（条目**不能缩进**）；还要保护**按名反射的跨模块契约**
  （AsrService 的 `RecognitionListener` 被 SDK 按名回调，改名 ⇒ 语音**静默失效**）。
  ⚠️ 反例：TtsEngine 不必加 -keep，**不要盲目类推**。
- **safe-delete 钩子**：单轮删 ≥50 文件会拦（00308004 Unable to delete entry\build）
  ⇒ **把 `entry/build`、`.hvigor` 改名让开再构建，不要硬删**。
- **构建环境**：`DEVECO_SDK_HOME` 指到 `...\DevEco Studio\sdk`（根，指 `sdk\default` 报 00303312）；
  自带 hvigorw wrapper 已坏，用 DevEco 自带 node 跑 `hvigorw.js`。
- **模拟器点击坐标只取自 `uitest dumpLayout` 的 bounds**（截图目测偏 30px ⇒ 点空被 Column 空 onClick 吞掉，表现「点了没反应」）。
- ⚠️ **记忆台账要进版本库**：Reader 仓 `.workbuddy/memory/` 全追踪，Journal 用 `.workbuddy/*` + `!.workbuddy/memory/`
  ⇒ 改 .gitignore 后 `git add -A` 并 `git ls-files .workbuddy` 验一下真的进去了。

## 五、性能层

- 详见 `reference-performance.md`（AGC「点击操作完成快」口径 + 六律 + 验证层四坑）。
- 一句话：重活要让帧（`setTimeout(0)`，不是微任务）、点击后先给反馈、后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 六、发版状态

- 🟡 **待上传：Reader 1.0.11（code 1000012）/ Journal 1.0.9（code 1000010）**，2026-11-04 23:15 出包、闸门全 PASS、tag 已推。
  桌面 `Rock阅读-1.0.11-上架.app`（2331 KB）/ `Rock私记-1.0.9-上架.app`（326 KB），
  清单 `桌面\Rock家族-1.0.11-1.0.9-待传清单.txt`（含可直接复制的更新说明）。
  在架仍是 Reader 1.0.10 / Journal 1.0.8。完整指纹、未验项、测试基线（307/307、247/247）、tag 规则
  ⇒ **`reference-releases.md`**。
- 下一版版本号：Reader `1.0.12` / code `1000013`；Journal `1.0.10` / code `1000011`。
- ⭐ **判断「包有没有变」不能看 md5**（签名含时间戳，每次都变）⇒ 解包 `ets/modules.abc` **数符号次数**比新旧包
  （`onBackPress` 0→2 这种）。混淆会改内部函数名，只有字符串常量与 SDK API 名可查。
- **发 Release 不盯（2026-10-29 定）**：push tag 后只推不监控，**下个任务开始时**再看那批 run（`gh run list`）。
  已按此核查过 2026-11-04：两仓含 tag 的 run 全 failure，但手动传包成功 ⇒ 不阻塞。

## 七、CI 现状（党哥拍板「CI 不急」）

- Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红：CI 用**公开 OpenHarmony SDK**，而
  `@kit.CoreSpeechKit`/`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 10505001 / 10311003。后果：打 tag 也不发 Release。
- 已排除：注入 hms kit；改 runtimeOS（00303038/00303313）；工程内桩（`arkts-no-untyped-obj-literals` 10605038）。
- 将来修法：CI 工作区把 kit 类型声明**内联到消费文件顶部**（ArkTS 要求同文件）再改 import。

## 八、产品对标与迭代方向

主标杆 **Day One**（Journal）/ **Apple Books·Kindle·静读天下**（Reader）。完整对账 ⇒ `reference-roadmap.md`。
文档：`RockReader/docs/生态融入与对标改进方案-2026-10-25.md`（第七节 = 真实差距，已按 10-29 实测修订）。

- **A 类·本地零联网（优先）**：① 语音转文字 ✅1.0.6 ② 位置标签 ⬜ ③ 写作提醒 ⬜ ④ Markdown 双向 ⬜
  ⑤ 自定义模板 ✅1.0.6 ⑥ 多日记本 ✅1.0.6 ⑦ PDF 导出 ⬜ ⑧ 每日提示 ✅1.0.6
- **B 类·需联网**：云同步 / 云端 AI / IFTTT —— 与第一节冲突，**主动取舍，不是落后**。
- **C 类·我们领先**：全量本地加密、时间胶囊硬封存、完全离线、不绑云账号。
- **坚决不做**：云同步 / 云端 AI。

## 九、all2md → ⚠️ 台账已迁出，本文件不再记细节

**真源：`F:\AI\HarmonyOS\apps\all2md\` 三本台账**（`task_plan.md` / `findings.md` / `progress.md`）。
党哥 2026-11-04 定：**台账按「阶段 / 主题」组织，不按日期记流水**。

只留三条**跨项目也成立**的禁令：
- ⚠️ 包名 `rock.all.2.md`、APP ID `6917620824955651111` —— **与 `com.rocktier.*` 不是同一体系，别顺手统一**（AGC 建了改不了）。
- ⚠️ **模拟器没有 PDFKit**（`canIUse` 返回 false，`pdfService` 运行时 undefined）⇒ **PDF 端到端只能真机验**。
- ⭐ 通用打法：**验不了机器就验数据** —— 纯逻辑抽到零 `@kit.*` 内核层，用真实文件导出中间数据喂它（三个真 bug 都是这么发现的）。

## 十、ASR（Core Speech Kit）

**边界**：只有中文普通话、只有离线模型（短 ≤60s / 长 ≤8h）；**模拟器无离线引擎 ⇒ 效果必须真机验**；仅中国区 Phone/Tablet。

**四个坑**（②是 2026-11-04 才查出来的真凶，前三版一直带着）：
① `online` 名与值相反（**.d.ts 原话「1: offline」⇒ 1 = 离线**，教程写 `online: 0` 是错的）；
② ⭐⭐ **`StartParams.extraParams` 的键是 `recognitionMode`（re-cogni-**tion**-Mode），不是 `recognizeMode`**。
   值为 **0** = 引擎自己开麦；**不传/键名错 ⇒ 默认 1 = 外部 `writeAudio` 喂流** ⇒ 我们从没喂过
   ⇒ **引擎起了、权限有了、界面显示"正在聆听"、但永远没声音没结果，且没有任何错误码**。
   我们写成 `recognizeMode` 整整带了 4 个版本（1.0.6～1.0.9），AGC 自检报「语音转文字不生效」才炸出来。
   ⚠️ 同一个 createEngine 里还有个 **`recognizerMode`**（'short'/'long'，选模型），是**另一个字段**，别混。
   官方示例的 createEngine 也一直带 `extraParams: { locate:'CN', recognizerMode:'short' }`，我们原来完全没给。
   ⇒ 现在键名收在 `AsrText.asrEngineExtra()/asrStartExtra()` 纯函数里，由单测盯拼写（字符串键只能这么守）。
③ `PermissionRequestResult` 没导出到 `abilityAccessCtrl` ⇒ **靠 `const res = await ...` 推断**。
④ `vadEnd` 短语音默认 **800ms** ⇒ 长句说到换气处就被判"说完了"，后半句丢；我们设 3000ms。

**判据：云测/自检的「语音不生效」不能直接当结论** —— 自动化机器人不会对着麦克风说话，
语音类功能在云测里被判"不生效"有结构性成分。**但也不能反过来当噪音忽略**（这次就是真 bug）。
分辨法：看 HiLog 有没有 `asr: onResult` —— 有回调没文本 = 音频进来了但识别不出；**一个回调都没有 = 音频压根没进来**（就是坑②的样子）。

**固定套路**：监听器 5 方法全必填（先 `const self=this`、字面量落接口变量、方法语法）；`createEngine` 用回调版，成功时 **err 是 undefined 不是 null**；
结果累积 = isFinal 累加 + 非 final 取最后一条。

**「必须真机才能验」的通用打法**：① 纯逻辑抽出（不引 @kit）用 node:test 测；② **用真 SDK 编译**验签名；
③ **「用不了」当一等公民**（UNREADY + 按钮禁用但保留 + 如实文案）；④ 按名反射的实现加 `-keep`；⑤ 上架说明一字不提，直到真机验过。

## 十一、ArkTS 类型三坑（all2md 2026-11-03，编译/单测才发现）

① **`null` 与 `undefined` 是两种类型**，`x === undefined` 挡不住 null ⇒ 签名写 `T | null | undefined`，判空两边都写；
② **非空断言 `!` 不允许**，自写 `isAbsent()` 也不是类型守卫 ⇒ 只能**内联判空**让类型自然收窄；
③ `arr[k].field !== undefined ? arr[k].field : ''` **收窄失效**（两次下标是不同表达式）⇒ 先 `const x = arr[k];` 再判。
