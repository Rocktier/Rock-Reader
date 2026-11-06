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

## 一之二、应用说明必写的两句话（党哥 2026-11-06 00:02 定，**上架文案硬要求**）

党哥原话：「现在手机端侧的 AI 应用越来越多，未来一定会爆发，我们做这个应用实际上也是为了给 AI 喂语料。
所以一定要在我们的应用说明中说明：第一，隐私完全不出互联网，不出设备。第二，一切以更好地让 AI 为人服务为目标。」

- **① 隐私完全不出设备、不出互联网**：不是"我们很重视隐私"，是**技术上做不到外传**（无网络权限 / 无网络请求）。
- **② 一切以更好地让 AI 为人服务为目标**：产品存在的理由是给 AI 备料，不是"又一个转换器"。
- 适用：all2md 的上架说明、应用内说明、商店副标题；Rock 家族同源口径可复用第①条。
- ⚠️ 写文案时**照抄这两条的意思，不要软化** —— "尽力保护"这种措辞等于没说。

## 二、签名与出包（每次出包必读 `reference-signing.md`）

- 出包 `assembleApp -p product=release -p buildMode=release --no-daemon`（不要 `--mode module`）；
  上传前必跑 `pwsh scripts/verify-upload.ps1`（不过就 throw），**闸门跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 后台当前应用 = 该应用。**包侧全绿仍 993 ⇒ 问题在包之外**（多半传错栏目）。
  993 分流：抠包内 Profile 看 `"type"` —— `debug` = 用错 product；`release` 但包名不符 = 拿错 Profile。
- build-profile 的 store/keyPassword 必须是 DevEco 加密串（明文报 00303116/00303117）。
- 版本号 `code = 1000000 + (minor + 1)`，**两处一起改**：`AppScope/app.json5` +
  `entry/src/main/ets/common/AppMeta.ets`（Reader 无 AppMeta；1.0.6 漏改 ⇒ smoke 红）。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。
  **博客在党哥自己的站上，代码改不到 ⇒ 改动要给党哥「照抄文本」。**
- 双写纪律：博客 `#privacy` == 两仓 `pages/Privacy.ets` == 逐字一致。
- ⚠️ **新增权限 ⇒ 必须同步隐私政策**（1.0.6 加麦克风后政策还写「不申请任何权限」= 拒审理由）
  ⇒ 同一提交内改完两仓 + 产出博客待同步文本。
  ⚠️ 例外：`backgroundModes` 不是权限、不采数据 ⇒ 政策无需改（Reader 1.0.8 已过审 = 实证）。

## 四、工程铁律（只列最高频的；全量 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **ArkUI V1 分支条件陷阱（家族最重要）**：`if` 的条件按**首次求值定型**，插桩只认表达式里
  **直接读 @State**（藏进 getter/方法追不到，`@Computed` 在 V1 救不了）。「数据变了 UI 不更新」按序查：
  ① ForEach key 少带变化位 ② 分支条件藏在 getter/方法 ③ 高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（第 8 次同型）⇒ 首选「表达式内联回 build()」。
  ⚠️ 更狠的形态（2026-11-06 书架封面）：带参 @Builder 里**只要还有 `if`**，分支按首次求值
  **定死** —— 里面碰 @State 派生的东西就永不更新 ⇒ 条件必须挪到**直接读 @State 的那个 body**。
  ⚠️ **`key` 不是万能解**：只对 ForEach 列表项有效，普通单子节点不因 key 重建。
- **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续；用独立 `suspended` 区分主动暂停。
- **浮层状态机**：别在开/关浮层时同步两套状态 ⇒ **到点才判断**（定时器里判「浮层开着」）。
  按钮覆盖多态时，**按了会发生什么必须写在按钮上**（OFF→滚屏 / RUNNING→停 / PAUSED→继续）。
- **锁库三铁律**（Journal）：① **先落盘再锁**（密钥一清 `encrypt()` 返 null ⇒ 防抖窗口内容永远存不下）
  ⇒ `onPageHide` 立刻落盘 + 锁延迟 > 防抖；② 只清密钥不够，还要清内存里的**内容预览**；
  ③ 送解锁页必须 `router.clear()` 再 `replaceUrl`（否则返回键翻回已解密页）。
- **日期一律本地时区**，禁用 `toISOString()`（东八区 00–08 点会写成昨天）。CI 有守门单测。
- **列表装饰竖条不能用 `height('100%')`** ⇒ 吃满 ListItem 变分隔线 ⇒ 固定 20vp + `alignSelf(Start)`。
- 🔒 **release 混淆**会改 JSON 落盘字段名 ⇒ 文件级 `-keep`（条目不能缩进）；**按名反射的跨模块契约**
  （AsrService 的 `RecognitionListener`）改名 ⇒ 语音静默失效。⚠️ TtsEngine 不必加，别盲目类推。
- **safe-delete**：单轮删 ≥50 文件会拦。报 `00308018` 且 Failed 在 `CompileArkTS` ⇒ 往下翻那行
  `[safe-delete]...` 指向真实目标；**只把 `.../cache/default/default@CompileArkTS` 改名 `.old-1` 就够**。
- 📁 **桌面交付物用中文应用名**：`Rock阅读-x.y.z-上架.app`（不要写 RockReader），否则与旧存档认错包。
- **构建环境**：`DEVECO_SDK_HOME` 指到 `...\DevEco Studio\sdk`（根，指 `sdk\default` 报 00303312）；
  自带 hvigorw 已坏，用 DevEco 自带 node 跑 `hvigorw.js`。
- **模拟器点击坐标只取自 `uitest dumpLayout` 的 bounds**（截图目测偏 30px ⇒ 点空被空 onClick 吞掉）。
- **划词 / PDF** 细则见 `reference-arkui-pitfalls.md` 与 `reference-roadmap.md`；只留两条硬判据：
  划词**长按让给系统**（自定义长按会抢赢系统选词）；PDF **本地 x86 模拟器 `canIUse` 为 false ⇒ 只能真机验**。
- ⚠️ **记忆台账要进版本库**：Reader 全追踪；Journal 用 `.workbuddy/*` + `!.workbuddy/memory/`
  ⇒ 改完 `git ls-files .workbuddy` 验一下。
- **书架封面**：导入时抽一次落盘 `books/<id>/cover.jpg`。EPUB **四条来源**（properties /
  meta name=cover / guide 封面页抠 `<img>` / 裸 `cover.jpg` 启发式），MOBI 走 EXTH201；
  写盘前一律验文件头。TXT/MD/HTML 永远无封面 ⇒ 回退首字占位。
  识别细则 + 造数/推文件/截图命令 ⇒ `2026-11-06.md` 第八节。

## 五、性能层

- 详见 `reference-performance.md`（AGC「点击操作完成快」口径 + 六律 + 验证层四坑）。
- 一句话：重活要让帧（`setTimeout(0)`，不是微任务）、点击后先给反馈、后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 六、发版状态

**在架版本（2026-11-06 20:35 党哥贴 AGC 应用列表，原始三列口径）**：

| 应用 | APP ID | 包名 | 在架 |
|---|---|---|---|
| Rock阅读 | `6917617208943200991` | `com.rocktier.rockreader` | **1.0.12** |
| Rock私记 | `6917617645309338498` | `com.rocktier.rockjournal` | **1.0.11** |

⇒ 11-05 那批「提交待审」的两版**都已经过审上架**（1.0.12 带 PDF 一期，1.0.11 带 Markdown 导入）。

- 🟢 **桌面待提交**：Reader 1.0.13 / Journal 1.0.12 两只包 **党哥 11-06 确认都没传** ⇒ 不传，
  等下一版一起重出。⚠️ **过审 ≠ 功能可用**（审核员不对麦克风说话；换编码入口也没上机点过）。
- ⭐ **判断「包有没有变」别用 md5**（签名含时间戳）⇒ 解包 `ets/modules.abc` 数符号次数
  （混淆会改内部函数名，只有字符串常量与 SDK API 名可查）。
- **发 Release 不盯（2026-10-29 定）**：push tag 后只推不监控，**下个任务开头**再看 `gh run list`。
- 下一版版本号：Reader `1.0.14`/`1000015`；Journal `1.0.13`/`1000014`。
  指纹 / 未验项 / 测试基线（Reader 361、Journal 301）/ tag 规则 ⇒ **`reference-releases.md`**。

## 七、CI 现状（党哥拍板「CI 不急」）

- Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红：CI 用**公开 OpenHarmony SDK**，而
  `@kit.CoreSpeechKit`/`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 10505001 / 10311003，打 tag 也不发 Release。
- 已排除：注入 hms kit；改 runtimeOS（00303038/00303313）；工程内桩（10605038）。
- 将来修法：CI 工作区把 kit 类型声明**内联到消费文件顶部**（ArkTS 要求同文件）再改 import。

## 八、产品对标与迭代方向

主标杆 **Day One**（Journal）/ **Apple Books·Kindle·静读天下**（Reader）。完整对账 ⇒ `reference-roadmap.md`。
文档：`RockReader/docs/生态融入与对标改进方案-2026-10-25.md`（第七节 = 真实差距）。

- **A 类·本地零联网（优先）**：① 语音转文字 ✅ ② 位置标签 ⬜ ③ 写作提醒 ⬜ ④ Markdown 双向 ⬜
  ⑤ 自定义模板 ✅ ⑥ 多日记本 ✅ ⑦ PDF 导出 ⬜ ⑧ 每日提示 ✅
- **B 类·需联网**（云同步 / 云端 AI / IFTTT）：与第一节冲突，**主动取舍，不是落后**。
- **C 类·我们领先**：全量本地加密、时间胶囊硬封存、完全离线、不绑云账号。**坚决不做**：云同步 / 云端 AI。

## 九、all2md → ⚠️ 台账已迁出，本文件不再记细节

**真源：`F:\AI\HarmonyOS\apps\all2md\` 三本台账**（`task_plan.md` / `findings.md` / `progress.md`），
按「阶段 / 主题」组织，不按日期记流水。只留两条跨项目禁令：

- ⚠️ 包名 `rock.all.2.md`、APP ID `6917620824955651111` —— **与 `com.rocktier.*` 不是同一体系，别顺手统一**。
- ⭐ 通用打法：**验不了机器就验数据** —— 纯逻辑抽到零 `@kit.*` 内核层，用真实文件导出中间数据喂它。

## 十、ASR（Core Speech Kit）—— 已修完上架，只留结论与判据

**边界**：只有中文普通话、只有离线模型（短 ≤60s / 长 ≤8h）；**模拟器无离线引擎 ⇒ 效果只能真机验**。

**四个坑**（② 是真凶，前三版一直带着）：
① `online` 名与值相反（.d.ts 原话「1: offline」⇒ **1 = 离线**，教程写 `online: 0` 是错的）；
② ⭐⭐ `StartParams.extraParams` 的键是 **`recognitionMode`**（re-cogni-**tion**-Mode，不是 `recognizeMode`）。
   **0 = 引擎自己开麦**；不传/键名错 ⇒ 默认 1 = 外部 `writeAudio` 喂流 ⇒ **引擎起了、权限有了、
   界面显示"正在聆听"、但永远没声音没结果，且没有任何错误码**。我们写错名整整带了 4 个版本（1.0.6–1.0.9）。
   ⚠️ 同一个 createEngine 里还有 **`recognizerMode`**（'short'/'long' 选模型），**是另一个字段**，别混。
   现在键名收在 `AsrText.asrEngineExtra()/asrStartExtra()`，由单测盯拼写。
③ `PermissionRequestResult` 没导出到 `abilityAccessCtrl` ⇒ 靠 `const res = await ...` 推断；
④ `vadEnd` 默认 800ms ⇒ 换气就被判"说完了"，后半句丢；我们设 3000ms。

**判据**：云测报「语音不生效」不能直接当结论（机器人不会对着麦克风说话），**也不能当噪音忽略**。
看 HiLog 有没有 `asr: onResult` —— 有回调没文本 = 音频进来了但识别不出；**一个回调都没有 = 音频压根没进来**（坑②的样子）。

**「必须真机才能验」的通用打法**：① 纯逻辑抽出（不引 @kit）用 node:test 测；② 用真 SDK 编译验签名；
③ **「用不了」当一等公民**（UNREADY + 按钮禁用但保留 + 如实文案）；④ 按名反射的实现加 `-keep`。

## 十一、ArkTS 类型三坑（all2md 2026-11-03）

① **`null` 与 `undefined` 是两种类型**，`x === undefined` 挡不住 null ⇒ 签名写 `T | null | undefined`，两边都判；
② **非空断言 `!` 不允许**，自写 `isAbsent()` 也不是类型守卫 ⇒ 只能内联判空让类型自然收窄；
③ `arr[k].field !== undefined ? arr[k].field : ''` **收窄失效**（两次下标是不同表达式）⇒ 先 `const x = arr[k];` 再判。

## 十二、设计基准：Apple HIG（党哥 2026-11-05 立，**家族基本要求**）

**唯一设计基准 = <https://developer.apple.com/cn/design/> 《人机界面指南》。**
**UI 类的 skill 只起优化作用，不能起决定作用** —— 与 HIG 冲突时一律以 HIG 为准。
适用于 Rock 家族 + all2md + 以后所有应用。

### 硬指标（做界面时逐条量，不靠感觉）

| 项 | 要求 | 出处 |
|---|---|---|
| 点击目标 | **推荐 44×44pt；绝对最小 28×28pt** | 无障碍 |
| 对比度 | ≤17pt 全字重 **4.5:1**；≥18pt 或粗体 **3:1**；深色浅色**各自**要过 | 无障碍 / 颜色 |
| 字号 | iOS 默认 17pt、**最小 11pt**；避免细体字重；字样种类要少 | 字体排印 |
| 文字放大 | 至少支持放大 **200%**，放大后不许截断/重叠（横排元素该改竖排） | 无障碍 |
| 颜色 | **不许只用颜色传达信息**（配形状/图标/文字）；深浅色都要有；禁止硬编码系统语义色 | 颜色 |
| 布局 | 重要内容靠上；对齐+缩进表达层级；相关项分组；渐进显示；遵守安全区 | 布局 |
| 动效 | 尊重「减少动态效果」；用淡入淡出替代位移 | 无障碍 |

### 自检怎么做（可执行，不是"看一眼好不好看"）

1. **量**：`uitest dumpLayout` 拿每个可点元素的 bounds，任一维 < 88px（44vp@2x）即违规。
2. **算**：文字色 vs 背景色按 WCAG 公式算比值（sRGB 反 gamma → 相对亮度 → (L1+.05)/(L2+.05)）。
3. **验**：系统切深色截图、字体调到最大截图，两套都要不糊不截断。**查**：状态位是否只靠颜色区分。

⚠️ 家底好的地方别推翻：all2md 的 `Tokens.ets` 已是量化 token，自检只补缺口，不重做视觉。

### 平台材质层（党哥 2026-11-06：综合苹果和华为）

**HIG 管可量化硬指标，HarmonyOS Design / HDS 管平台视觉语言**（毛玻璃、渐变模糊、按压弹性、
悬浮圆角）—— 两者不冲突，各管一层；UI 类 skill 仍只做优化，不能决定。

- 官方「空间化 / 沉浸光感」六特性 + 四档材质（业务推荐 `ADAPTIVE`）；
  ⚠️ 普通组件只在 Navigation 标题栏 / 底部 TabBar 生效 ⇒ **内容区大卡用通用
  `backgroundBlurStyle`，不假装接了 HDS**；官方明说「光感不能牺牲操作效率」「耗 GPU」。
- Apple《材质》：**Liquid Glass 不要在内容层用**；材质只做承载层，文字要落在对比度
  可确定的表面 ⇒ 玻璃优先用在浮层 / 抽屉（背后有正文才透得出来），不是首页大卡。
- 半透明只写组件 `.opacity()`；**资源色一律 6 位**（8 位会被静默吞成透明）。
- ⭐ **淡化 ≠ 降对比度**：说明 / slogan 用 11fp + `muted` + 留白退后，4.5:1 照守，
  **文案一字不改**（产品说明两条硬要求不软化）。
- ⭐ **动效别用 `if (entered)` 包内容**（V1 分支条件按首次求值定型）⇒ @State 数值 +
  `.animation()`；时长抽常量，接系统「减少动效」开关时置 0 降级。

### 重点色块与字号双峰（2026-11-06 家族两仓改版立）

- **要立焦点就立"一块墨"**：首屏只留**一个**实心色面（阅读「继续阅读」卡、私记今日卡），
  其余全部退到纸面 —— 靠**面积与反差**立重点，不靠加粗描边、不靠再加一个颜色。
  改版前两仓的共同病是"每个元素都在说话"：标题/按钮/统计同一量级平铺，于是没有重点。
- 语义色**成对** `heroBg` / `heroText`，四套主题各给一套值，页面零 `if (isDark)`。
  ⚠️ **深色下不能拿 `text` 反白**：`text` 是 86% 白，反白就是一块白卡压纯黑，夜里刺眼。
  深色取「抬一档的卡片灰」(`#303030`)，浅色/护眼才真用墨。单测守三条：
  块上文字 ≥4.5:1、块与页底 ≥1.25:1、**深色下块亮度必须低于正文色**。
- **字号双峰**：一页只留两档（大标题/大数字 30–38、元数据 11），中间层（14/16fp 说明块）全撤。
  ⚠️ 小字**不得低于 11fp**（HIG 下限）—— 9/10fp 的元数据在 3x 屏上就是读不清，别用"精致"换可读性。
- **动效**:`common/Motion.ets`（两仓各一份，纯数值 + 纯函数可单测）：`motionMs(base, reduced)`
  在降级时返回 **0**（瞬时，不是变慢）、`staggerMs(index, cap)` **必须封顶**（否则长列表末尾等到几秒后）。
  ⚠️ **入场只用位移/缩放，不用 opacity** —— `entered` 万一没翻成 true，
  "动效没播"会变成"内容不见了"；位移卡住只差几 vp，功能一点不少。
