# Rock 家族长期记忆（v4 · 2026-11-06）

> 只记**可执行**知识（命令、判据、禁令）；过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读 + Rock私记 + all2md。**本文只留高频条目，细节全在深度文件**（同目录）：
> `reference-hig.md` HIG/HDS 设计基准 · `reference-asr.md` 语音 · `reference-signing.md` 签名出包 ·
> `reference-releases.md` 指纹/版本/基线 · `reference-performance.md` 性能 ·
> `reference-arkui-pitfalls.md` ArkUI/混淆/编译 · `reference-simulator.md` hdc/模拟器 ·
> `reference-clouddebug.md` AGC 云调试 · `reference-roadmap.md` 对标。

## 一、产品口径：非主动联网（2026-10-18 拍板）

原话：「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 用户主动点「下载」→ 联网 → 之后离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见、失败可重试、无网时明说。
- ❌ 主要功能联网（云 TTS / 在线书城 / 云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 麦克风不算联网（本地传感器）。**新增任何系统能力前先对照此表。**

## 一之二、应用说明必写的两句话（2026-11-06 定，**上架硬要求**）

1. **隐私完全不出设备、不出互联网** —— 不是"我们很重视隐私"，是**技术上做不到外传**（无网络权限 / 无请求）。
2. **一切以更好地让 AI 为人服务为目标** —— 产品存在的理由是给 AI 备料，不是"又一个转换器"。

适用 all2md 上架说明 / 应用内说明 / 商店副标题，Rock 家族可复用①。⚠️ **照抄意思，不许软化**。

## 二、签名与出包（每次必读 `reference-signing.md`）

- 出包 `assembleApp -p product=release -p buildMode=release --no-daemon`（不要 `--mode module`）；
  上传前必跑 `pwsh scripts/verify-upload.ps1`，**闸门跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 当前应用 = 该应用。**包侧全绿仍 993 ⇒ 问题在包之外**
  （抠包内 Profile 看 `"type"`：`debug` = 用错 product；`release` 但包名不符 = 拿错 Profile）。
- store/keyPassword 必须是 DevEco 加密串（明文报 00303116/00303117）。
- 版本号 `code = 1000000 + (minor + 1)`，**两处一起改**：`AppScope/app.json5` + `common/AppMeta.ets`
  （Reader 无 AppMeta；Journal 1.0.6 漏改 ⇒ smoke 红）。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。
  博客在党哥自己站上 ⇒ 改动要给党哥「照抄文本」；双写纪律：博客 `#privacy` == 两仓 `pages/Privacy.ets` 逐字一致。
- ⚠️ **新增权限 ⇒ 同一提交内改完两仓 + 产出博客待同步文本**（加麦克风后政策仍写「不申请任何权限」= 拒审）。
  例外：`backgroundModes` 不是权限 ⇒ 政策不改（Reader 1.0.8 已过审 = 实证）。

## 四、工程铁律（全量 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **ArkUI V1 分支条件陷阱（家族最重要）**：`if` 条件按**首次求值定型**，插桩只认表达式里**直接读 @State**
  （藏进 getter/方法追不到，`@Computed` 在 V1 救不了）。「数据变了 UI 不更新」按序查：
  ① ForEach key 少带变化位 ② 条件藏在 getter/方法 ③ 高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（第 8 次同型）⇒ 首选「表达式内联回 build()」。
  ⚠️ 带参 @Builder 里**只要还有 `if`**，分支同样按首次求值定死 ⇒ 条件必须挪到直接读 @State 的 body。
  ⚠️ **`key` 不是万能解**：只对 ForEach 列表项有效，普通单子节点不因 key 重建。
- **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续；用独立 `suspended` 区分主动暂停。
  浮层状态机同理：别在开/关时同步两套状态 ⇒ **到点才判断**；按钮覆盖多态时**按了会发生什么必须写在按钮上**。
- **锁库三铁律**（Journal）：① **先落盘再锁**（密钥一清 `encrypt()` 返 null ⇒ 防抖窗口永远存不下）
  ⇒ `onPageHide` 立刻落盘 + 锁延迟 > 防抖；② 只清密钥不够，还要清内存里的**内容预览**；
  ③ 送解锁页必须 `router.clear()` 再 `replaceUrl`（否则返回键翻回已解密页）。
- **日期一律本地时区**，禁用 `toISOString()`（东八区 00–08 点写成昨天）。CI 有守门单测。
- **列表装饰竖条不能用 `height('100%')`** ⇒ 吃满 ListItem 变分隔线 ⇒ 固定 20vp + `alignSelf(Start)`。
- 🔒 **release 混淆**会改 JSON 落盘字段名 ⇒ 文件级 `-keep`（条目不能缩进）；**按名反射的跨模块契约**
  （`RecognitionListener`）改名 ⇒ 语音静默失效。⚠️ TtsEngine 不必加，别盲目类推。
- **safe-delete**：单轮删 ≥50 文件会拦。报 `00308018` 且 Failed 在 `CompileArkTS` ⇒ 往下翻那行
  `[safe-delete]...` 指向真实目标；**只把 `.../cache/default/default@CompileArkTS` 改名 `.old-1` 就够**。
- 📁 **桌面交付物用中文应用名**：`Rock阅读-x.y.z-上架.app`（不要 RockReader），否则与旧存档认错包。
- **构建环境**：`DEVECO_SDK_HOME` 指到 `...\DevEco Studio\sdk`（根，指 `sdk\default` 报 00303312）；
  自带 hvigorw 已坏，用 DevEco 自带 node 跑 `hvigorw.js`。
- **模拟器点击坐标只取自 `uitest dumpLayout` 的 bounds**（截图目测偏 30px ⇒ 点空被空 onClick 吞掉）。
- 划词**长按让给系统**（自定义长按抢赢系统选词）；PDF **本地 x86 模拟器 `canIUse` 为 false ⇒ 只能真机验**。
- ⚠️ **记忆台账要进版本库**：Reader 全追踪；Journal 用 `.workbuddy/*` + `!.workbuddy/memory/` ⇒ `git ls-files` 验。
- **书架封面**：导入时抽一次落盘 `books/<id>/cover.jpg`。EPUB 四条来源（properties / meta name=cover /
  guide 封面页抠 `<img>` / 裸 `cover.jpg`），MOBI 走 EXTH201；写盘前验文件头。TXT/MD/HTML 无封面 ⇒ 首字占位。

## 五、性能层

详见 `reference-performance.md`。一句话：重活要让帧（`setTimeout(0)`，不是微任务）、点击后先给反馈、
后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 六、发版状态

**在架**：Rock阅读 `1.0.12`（`6917617208943200991` / `com.rocktier.rockreader`）、
Rock私记 `1.0.11`（`6917617645309338498` / `com.rocktier.rockjournal`）—— 2026-11-06 20:35 党哥贴 AGC 列表确认。

- 🟢 桌面 Reader 1.0.13 / Journal 1.0.12 两只包**确认没传** ⇒ 不传，等下一版重出。
  ⚠️ **过审 ≠ 功能可用**（审核员不对麦克风说话；换编码入口也没上机点过）。
- ⭐ **判断「包有没有变」别用 md5**（签名含时间戳）⇒ 解包 `ets/modules.abc` 数符号次数。
- **发 Release 不盯（2026-10-29 定）**：push tag 后只推不监控，**下个任务开头**再看 `gh run list`。
- 下一版：Reader `1.0.14`/`1000015`；Journal `1.0.13`/`1000014`。指纹/未验项/基线 ⇒ `reference-releases.md`。

## 七、CI 现状（拍板「CI 不急」）

Reader CI 自引入 `@kit.CoreSpeechKit` 起连续红：CI 用**公开 OpenHarmony SDK**，而
`@kit.CoreSpeechKit`/`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 10505001 / 10311003，打 tag 也不发 Release。
已排除：注入 hms kit / 改 runtimeOS / 工程内桩。修法：CI 工作区把 kit 类型声明**内联到消费文件顶部**再改 import。

## 八、产品对标（对账 ⇒ `reference-roadmap.md`）

标杆 **Day One**（Journal）/ **Apple Books·Kindle·静读天下**（Reader）。
A 类本地零联网优先（语音 ✅ / 模板 ✅ / 多本 ✅ / 每日提示 ✅；位置标签 / 写作提醒 / MD 双向 / PDF 导出 ⬜）。
B 类需联网（云同步 / 云端 AI）与第一节冲突 ⇒ **主动取舍，不是落后**。**坚决不做**：云同步 / 云端 AI。

## 九、all2md → 台账已迁出

真源 `F:\AI\HarmonyOS\apps\all2md\` 三本台账（`task_plan.md` / `findings.md` / `progress.md`），按阶段组织。
（**工程代码仓是 `F:\AI\HarmonyOS\all2md\`，与台账不是同一个 repo。**）只留两条跨项目禁令：

- ⚠️ 包名 `rock.all.2.md`、APP ID `6917620824955651111` —— **与 `com.rocktier.*` 不是同一体系，别顺手统一**。
- ⭐ 通用打法：**验不了机器就验数据** —— 纯逻辑抽到零 `@kit.*` 内核层，用真实文件导出中间数据喂它。

## 十、ASR（Core Speech Kit）

细节 ⇒ **`reference-asr.md`**。只留两条不可协商的：键名 **`recognitionMode`**（不是 `recognizeMode`），
值 0 = 引擎自己开麦 —— 拼错就"引擎起了、界面在听、永远没声且无错误码"；
云测报「语音不生效」不能当结论，也不能当噪音，看 HiLog 有没有 `asr: onResult`。

## 十一、ArkTS 类型三坑

① **`null` 与 `undefined` 是两种类型**（`x === undefined` 挡不住 null ⇒ 签名写 `T | null | undefined`）；
② **非空断言 `!` 不允许**，自写 `isAbsent()` 也不是类型守卫 ⇒ 只能**内联判空**收窄；
③ `arr[k].field !== undefined ? …` **收窄失效** ⇒ 先 `const x = arr[k];`。

## 十二、设计基准：Apple HIG + 鸿蒙 HDS

**唯一基准 = <https://developer.apple.com/cn/design/>**（鸿蒙侧对照 <https://developer.huawei.com/consumer/cn/design/>）。
**UI 类 skill 只起优化作用，不能起决定作用**，与 HIG 冲突一律以 HIG 为准。全家族 + 以后所有应用。
硬指标表 / 平台分层 / 审计三抓手 / 本轮四条实操结论 ⇒ **`reference-hig.md`**。

四条背得下来的：点击目标 **44pt（绝对最小 28）**、字号 **最小 11fp**、对比度 **4.5:1**、
**不许只用颜色传达信息**。另加：不达标**先改 token 不改调用点**；主按钮字色用 `onAccent` **不是 `bg`**；
说明/slogan 淡化靠留白 + `muted`，**文案一字不改**；热区 44 让位于「不压邻居」。
