# Rock 家族长期记忆（v3 · 2026-11-06）

> 只记**可执行**知识（命令、判据、禁令）。过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读 + Rock私记 **两仓** + 本地 all2md。
> 深度文件（同目录）：`reference-signing.md` 签名出包 · `reference-releases.md` 指纹/版本/基线 ·
> `reference-performance.md` 性能六律 · `reference-arkui-pitfalls.md` ArkUI/混淆/编译 ·
> `reference-simulator.md` hdc/模拟器 · `reference-clouddebug.md` AGC 云调试 · `reference-roadmap.md` 对标。

## 一、产品口径：非主动联网（2026-10-18 拍板）

「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 用户主动点「下载」→ 联网 → 之后离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见、失败可重试、无网时明说。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 麦克风不算联网（本地传感器）。**新增任何系统能力前先对照此表。**

## 一之二、应用说明必写的两句话（2026-11-06 定，**上架文案硬要求**）

1. **隐私完全不出设备、不出互联网** —— 不是"我们很重视隐私"，是**技术上做不到外传**（无网络权限 / 无网络请求）。
2. **一切以更好地让 AI 为人服务为目标** —— 产品存在的理由是给 AI 备料，不是"又一个转换器"。

适用 all2md 的上架说明 / 应用内说明 / 商店副标题；Rock 家族可复用第①条。
⚠️ **照抄意思，不要软化** —— "尽力保护"这种措辞等于没说。

## 二、签名与出包（每次出包必读 `reference-signing.md`）

- 出包 `assembleApp -p product=release -p buildMode=release --no-daemon`（不要 `--mode module`）；
  上传前必跑 `pwsh scripts/verify-upload.ps1`，**闸门跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 后台当前应用 = 该应用。**包侧全绿仍 993 ⇒ 问题在包之外**。
  993 分流：抠包内 Profile 看 `"type"` —— `debug` = 用错 product；`release` 但包名不符 = 拿错 Profile。
- build-profile 的 store/keyPassword 必须是 DevEco 加密串（明文报 00303116/00303117）。
- 版本号 `code = 1000000 + (minor + 1)`，**两处一起改**：`AppScope/app.json5` +
  `entry/src/main/ets/common/AppMeta.ets`（Reader 无 AppMeta；Journal 1.0.6 漏改 ⇒ smoke 红）。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。
  **博客在党哥自己的站上 ⇒ 改动要给党哥「照抄文本」**；双写纪律：博客 `#privacy` == 两仓 `pages/Privacy.ets` 逐字一致。
- ⚠️ **新增权限 ⇒ 必须同步隐私政策**（1.0.6 加麦克风后政策仍写「不申请任何权限」= 拒审理由）
  ⇒ 同一提交内改完两仓 + 产出博客待同步文本。
  ⚠️ 例外：`backgroundModes` 不是权限 ⇒ 政策无需改（Reader 1.0.8 已过审 = 实证）。

## 四、工程铁律（全量 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **ArkUI V1 分支条件陷阱（家族最重要）**：`if` 的条件按**首次求值定型**，插桩只认表达式里
  **直接读 @State**（藏进 getter/方法追不到，`@Computed` 在 V1 救不了）。「数据变了 UI 不更新」按序查：
  ① ForEach key 少带变化位 ② 分支条件藏在 getter/方法 ③ 高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（第 8 次同型）⇒ 首选「表达式内联回 build()」。
  ⚠️ 更狠：带参 @Builder 里**只要还有 `if`**，分支按首次求值**定死** —— 碰 @State 派生的东西就永不更新
  ⇒ 条件必须挪到**直接读 @State 的那个 body**（2026-11-06 书架续读卡封面即此形态）。
  ⚠️ **`key` 不是万能解**：只对 ForEach 列表项有效，普通单子节点不因 key 重建。
- **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续；用独立 `suspended` 区分主动暂停。
- **浮层状态机**：别在开/关浮层时同步两套状态 ⇒ **到点才判断**（定时器里判「浮层开着」）。
  按钮覆盖多态时，**按了会发生什么必须写在按钮上**（OFF→滚屏 / RUNNING→停 / PAUSED→继续）。
- **锁库三铁律**（Journal）：① **先落盘再锁**（密钥一清 `encrypt()` 返 null ⇒ 防抖窗口内容永远存不下）
  ⇒ `onPageHide` 立刻落盘 + 锁延迟 > 防抖；② 只清密钥不够，还要清内存里的**内容预览**；
  ③ 送解锁页必须 `router.clear()` 再 `replaceUrl`（否则返回键翻回已解密页）。
- **日期一律本地时区**，禁用 `toISOString()`（东八区 00–08 点写成昨天）。CI 有守门单测。
- **列表装饰竖条不能用 `height('100%')`** ⇒ 吃满 ListItem 变分隔线 ⇒ 固定 20vp + `alignSelf(Start)`。
- 🔒 **release 混淆**会改 JSON 落盘字段名 ⇒ 文件级 `-keep`（条目不能缩进）；**按名反射的跨模块契约**
  （AsrService 的 `RecognitionListener`）改名 ⇒ 语音静默失效。⚠️ TtsEngine 不必加，别盲目类推。
- **safe-delete**：单轮删 ≥50 文件会拦。报 `00308018` 且 Failed 在 `CompileArkTS` ⇒ 往下翻那行
  `[safe-delete]...` 指向真实目标；**只把 `.../cache/default/default@CompileArkTS` 改名 `.old-1` 就够**。
- 📁 **桌面交付物用中文应用名**：`Rock阅读-x.y.z-上架.app`（不要 RockReader），否则与旧存档认错包。
- **构建环境**：`DEVECO_SDK_HOME` 指到 `...\DevEco Studio\sdk`（根，指 `sdk\default` 报 00303312）；
  自带 hvigorw 已坏，用 DevEco 自带 node 跑 `hvigorw.js`。
- **模拟器点击坐标只取自 `uitest dumpLayout` 的 bounds**（截图目测偏 30px ⇒ 点空被空 onClick 吞掉）。
- 划词**长按让给系统**（自定义长按抢赢系统选词）；PDF **本地 x86 模拟器 `canIUse` 为 false ⇒ 只能真机验**。
- ⚠️ **记忆台账要进版本库**：Reader 全追踪；Journal 用 `.workbuddy/*` + `!.workbuddy/memory/` ⇒ 改完 `git ls-files` 验。
- **书架封面**：导入时抽一次落盘 `books/<id>/cover.jpg`。EPUB **四条来源**（properties /
  meta name=cover / guide 封面页抠 `<img>` / 裸 `cover.jpg` 启发式），MOBI 走 EXTH201；
  写盘前一律验文件头（`CoverImage.isImageBytes()`）。TXT/MD/HTML 永远无封面 ⇒ 回退首字占位。
  造数/推文件/截图命令 ⇒ `2026-11-06.md` 第八节。

## 五、性能层

详见 `reference-performance.md`。一句话：重活要让帧（`setTimeout(0)`，不是微任务）、点击后先给反馈、
后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 六、发版状态

| 应用 | APP ID | 包名 | 在架 |
|---|---|---|---|
| Rock阅读 | `6917617208943200991` | `com.rocktier.rockreader` | **1.0.12** |
| Rock私记 | `6917617645309338498` | `com.rocktier.rockjournal` | **1.0.11** |

（2026-11-06 20:35 党哥贴 AGC 应用列表；⇒ 11-05 那批「待审」两版都已过审上架。）

- 🟢 桌面 Reader 1.0.13 / Journal 1.0.12 两只包 **确认没传** ⇒ 不传，等下一版重出。
  ⚠️ **过审 ≠ 功能可用**（审核员不对麦克风说话；换编码入口也没上机点过）。
- ⭐ **判断「包有没有变」别用 md5**（签名含时间戳）⇒ 解包 `ets/modules.abc` 数符号次数。
- **发 Release 不盯（2026-10-29 定）**：push tag 后只推不监控，**下个任务开头**再看 `gh run list`。
- 下一版：Reader `1.0.14`/`1000015`；Journal `1.0.13`/`1000014`。
  指纹 / 未验项 / 测试基线（Reader 361、Journal 301）/ tag 规则 ⇒ **`reference-releases.md`**。

## 七、CI 现状（拍板「CI 不急」）

Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红：CI 用**公开 OpenHarmony SDK**，
而 `@kit.CoreSpeechKit`/`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 10505001 / 10311003，打 tag 也不发 Release。
已排除：注入 hms kit / 改 runtimeOS（00303038、00303313）/ 工程内桩（10605038）。
将来修法：CI 工作区把 kit 类型声明**内联到消费文件顶部**（ArkTS 要求同文件）再改 import。

## 八、产品对标与迭代方向

主标杆 **Day One**（Journal）/ **Apple Books·Kindle·静读天下**（Reader）。完整对账 ⇒ `reference-roadmap.md`。

- **A 类·本地零联网（优先）**：语音转文字 ✅ / 位置标签 ⬜ / 写作提醒 ⬜ / Markdown 双向 ⬜ /
  自定义模板 ✅ / 多日记本 ✅ / PDF 导出 ⬜ / 每日提示 ✅
- **B 类·需联网**（云同步 / 云端 AI / IFTTT）：与第一节冲突，**主动取舍，不是落后**。
- **C 类·我们领先**：全量本地加密、时间胶囊硬封存、完全离线、不绑云账号。**坚决不做**：云同步 / 云端 AI。

## 九、all2md → 台账已迁出

**真源 `F:\AI\HarmonyOS\apps\all2md\` 三本台账**（`task_plan.md` / `findings.md` / `progress.md`），
按「阶段 / 主题」组织。只留两条跨项目禁令：

- ⚠️ 包名 `rock.all.2.md`、APP ID `6917620824955651111` —— **与 `com.rocktier.*` 不是同一体系，别顺手统一**。
- ⭐ 通用打法：**验不了机器就验数据** —— 纯逻辑抽到零 `@kit.*` 内核层，用真实文件导出中间数据喂它。

## 十、ASR（Core Speech Kit）

**边界**：只有中文普通话、只有离线模型（短 ≤60s / 长 ≤8h）；**模拟器无离线引擎 ⇒ 只能真机验**。

**四个坑**（② 是真凶，前三版一直带着）：
① `online` 名与值相反（.d.ts 原话「1: offline」⇒ **1 = 离线**，教程写 `online: 0` 是错的）；
② ⭐⭐ `StartParams.extraParams` 的键是 **`recognitionMode`**（re-cogni-**tion**-Mode，**不是**
   `recognizeMode`）。**0 = 引擎自己开麦**；不传/键名错 ⇒ 默认 1 = 外部 `writeAudio` 喂流
   ⇒ **引擎起了、权限有了、界面显示"正在聆听"、但永远没声音没结果，且无任何错误码**。
   写错名带了 4 个版本（1.0.6–1.0.9）。⚠️ 同一 createEngine 里还有 **`recognizerMode`**
   （'short'/'long' 选模型），**是另一个字段**。键名现收在 `AsrText.asrEngineExtra()/asrStartExtra()`。
③ `PermissionRequestResult` 没导出到 `abilityAccessCtrl` ⇒ 靠 `const res = await ...` 推断；
④ `vadEnd` 默认 800ms ⇒ 换气就被判"说完了"；我们设 3000ms。

**判据**：云测报「语音不生效」不能直接当结论，**也不能当噪音忽略**。看 HiLog 有没有 `asr: onResult` ——
有回调没文本 = 音频进来了识别不出；**一个都没有 = 音频压根没进来**（坑②）。

**「必须真机」的通用打法**：① 纯逻辑抽出（不引 @kit）用 node:test；② 用真 SDK 编译验签名；
③ **「用不了」当一等公民**（UNREADY + 按钮禁用但保留 + 如实文案）；④ 按名反射的实现加 `-keep`。

## 十一、ArkTS 类型三坑

① **`null` 与 `undefined` 是两种类型**（`x === undefined` 挡不住 null ⇒ 签名写 `T | null | undefined`）；
② **非空断言 `!` 不允许**，自写 `isAbsent()` 也不是类型守卫 ⇒ 只能**内联判空**收窄；
③ `arr[k].field !== undefined ? …` **收窄失效**（两次下标是不同表达式）⇒ 先 `const x = arr[k];`。

## 十二、设计基准：Apple HIG + 鸿蒙 HDS（家族基本要求）

**唯一设计基准 = <https://developer.apple.com/cn/design/>《人机界面指南》**（鸿蒙侧对照
<https://developer.huawei.com/consumer/cn/design/>）。**UI 类 skill 只起优化作用，不能起决定作用** ——
与 HIG 冲突一律以 HIG 为准。适用 Rock 家族 + all2md + 以后所有应用。

### 硬指标（逐条量，不靠感觉）

| 项 | 要求 |
|---|---|
| 点击目标 | **推荐 44×44pt；绝对最小 28×28pt** |
| 对比度 | ≤17pt 全字重 **4.5:1**；≥18pt 或粗体 **3:1**；深色浅色**各自**要过 |
| 字号 | 默认 17pt、**最小 11pt**；避免细体；字样种类要少 |
| 文字放大 | 至少 **200%**，放大后不许截断/重叠（横排该改竖排） |
| 颜色 | **不许只用颜色传达信息**（配形状/图标/文字）；禁止硬编码系统语义色 |
| 布局 | 重要内容靠上；缩进表达层级；相关项分组；遵守安全区 |
| 动效 | 尊重「减少动态效果」，降级为瞬时 |

### 自检怎么做 → 见下方「审计三抓手」

⚠️ 家底好的地方别推翻：all2md 的 `Tokens.ets` 已是量化 token，只补缺口。

### 平台材质层（苹果 + 华为各管一层）

**HIG 管可量化硬指标，HDS 管平台视觉语言**（毛玻璃、渐变模糊、按压弹性、悬浮圆角），两者不冲突。

- HDS「沉浸光感」的**生效范围有限**：普通组件只在 Navigation 标题栏 / 底部 TabBar 生效
  ⇒ 内容区大卡用通用 `backgroundBlurStyle`，**不假装接了 HDS**（官方也说「光感不能牺牲操作效率」「耗 GPU」）。
- Apple《材质》：**Liquid Glass 不在内容层用**；玻璃优先给浮层 / 抽屉（背后有正文才透得出来）。
- 半透明只写组件 `.opacity()`；**资源色一律 6 位**（8 位被静默吞成透明）。
- ⭐ **淡化 ≠ 降对比度**：说明 / slogan 用 11fp + `muted` + 留白退后，4.5:1 照守，**文案一字不改**。
- ⭐ **动效别用 `if (entered)` 包内容** ⇒ @State 数值 + `.animation()`。

### 重点色块与字号双峰（2026-11-06 两仓改版立）

- **要立焦点就立"一块墨"**：首屏只留**一个**实心色面，其余退到纸面 —— 靠面积与反差立重点，
  不靠加粗描边。改版前的共同病是"每个元素都在说话"，于是没有重点。
- 语义色**成对** `heroBg`/`heroText`，四套主题各给一套，页面零 `if (isDark)`。
  ⚠️ **深色下不能拿 `text` 反白**（86% 白 ⇒ 一块白卡压纯黑），取抬一档的卡片灰。
- **字号双峰**：一页只留两档（30–38 与 11），中间层全撤。小字**不得低于 11fp**。
- **动效** `common/Motion.ets`（两仓各一份，纯数值 + 纯函数可单测）：`motionMs(base, reduced)`
  降级返回 **0**（瞬时，不是变慢）、`staggerMs(index, cap)` **必须封顶**。
  ⚠️ **入场只用位移/缩放，不用 opacity** —— `entered` 万一没翻成 true，"动效没播"会变成"内容不见了"。
- ⭐ **「减少动态效果」已接上（2026-11-06 三仓）**：读 `settings.display.ANIMATOR_DURATION_SCALE`
  （`@ohos.settings`，**0 = 动画立即结束**；⚠️ `@deprecated since 21`，compileSdk 20 暂安全，**升 21 要回来换**）。
  **纯判断放 `Motion.ets`、SDK 读取放 `SystemMotion.ets`** —— 引 `@ohos.settings` 或 `$r()` 的文件
  进不了 node:test（all2md 把纯函数塞 Tokens 里，测试直接 `$r is not defined`）。
  ⚠️ **`Number('')` 是 0 不是 NaN** ⇒ 必须显式挡空串，否则"读不到"被判成"用户要关动画"，
  动效静默全没且看着像设计决定。降级时连 setTimeout 都别排（闪一帧 = 内容闪一帧）。
- ⭐ **审计三抓手**（打磨前先跑，别凭感觉）：
  ① 字号分布 —— **必须查 token 值**，只扫字面数字会漏掉 9/10fp 那一大批；
  ② 点击目标 —— `.height(<44)` + 同块 `onClick`，再分「有 responseRegion（视觉小=合规）」与「没有」；
  ③ 对比度全组合 —— **别漏「强调色当底」**（主按钮即此形态）；判读时剔掉永不出现的理论组合。
- ⭐ **不达标优先改 token，不改调用点**（阅读 67 处、私记 62 处）。代价：11fp 会甩孤字
  （设置页「a）」），处理方式是**显式断行、断在语义边界**，不是缩文案。
- ⭐ **主按钮字色不是 `bg`**：那是"拿页面底色当字色"，护眼主题下压蓝底只有 4.3:1 ⇒
  与 heroBg/heroText 同款再立一对 `onAccent`。
- ⭐ **热区 44 要让位于"不压邻居"**：私记图片删除角标视觉 24、热区 40（缩略图间距 8、中心距 72）。
