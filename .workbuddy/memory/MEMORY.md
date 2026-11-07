# Rock 家族长期记忆（v6 · 2026-11-06）

> 只记**可执行**知识（命令、判据、禁令）；过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读 + Rock私记 + all2md。细节在深度文件（同目录）：`reference-hig` 设计基准 ·
> `reference-asr` 语音 · `reference-signing` 签名/构建 · `reference-releases` 指纹/版本/CI ·
> `reference-performance` 性能 · `reference-arkui-pitfalls` ArkUI/混淆/书封/锁库 ·
> `reference-simulator` hdc/模拟器 · `reference-clouddebug` 云调试 · `reference-roadmap` 对标。
> ⚠️ 本文**上限约 4000 字符**（超了注入会被静默截断）⇒ 新增一条就把旧的一条挪进深度文件。

## 一、产品口径：非主动联网（2026-10-18 拍板）

「用户可以自己联网下载字体或音色，但**我们自己不会主动联网，主要功能也不联网**。」

- ✅ 用户点「下载」才联网，之后离线用；入口明示「联网下载」+ 体积、进度、失败重试、无网明说。
- ❌ 主要功能联网（云 TTS / 书城 / 云同步）；❌ 应用自发联网（检查更新 / 静默下载 / 遥测）。
- 麦克风是本地传感器，不算联网。**新增系统能力前先对照此表。**

## 二、上架说明必写的两句话（硬要求，**不许软化**）

1. **隐私完全不出设备、不出互联网** —— 不是"重视隐私"，是**技术上做不到外传**。
2. **一切以更好地让 AI 为人服务为目标** —— 产品是为 AI 备料，不是"又一个转换器"。

## 三、签名与出包（细则 ⇒ `reference-signing.md`）

- `assembleApp -p product=release -p buildMode=release --no-daemon`；上传前
  `pwsh scripts/verify-upload.ps1`，**闸门跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 当前应用。**包侧全绿仍 993 ⇒ 问题在包之外**
  （抠 Profile 看 `"type"`：`debug` = 用错 product；`release` 但包名不符 = 拿错 Profile）。
- 版本号 `code = 1000000 + (minor + 1)`，**两处同改**：`app.json5` + `common/AppMeta.ets`（Reader 无 AppMeta）。

## 四、法律文件：一个链接覆盖全家族

<https://www.91hym.cn/devs/756.html> 三章 + `#privacy`/`#agreement`/`#rights`，两应用共用。
博客在党哥自己站上 ⇒ 改动要给他「照抄文本」；双写纪律：博客 == 两仓 `pages/Privacy.ets` 逐字一致。
⚠️ **新增权限 ⇒ 同一提交内改完两仓 + 产出博客文本**；例外：`backgroundModes` 不是权限，政策不改。

## 五、工程铁律（全量 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **ArkUI V1 分支条件按首次求值定型**，插桩只认表达式里**直接读 @State**（藏 getter/方法追不到，
  `@Computed` 在 V1 救不了）。「数据变了 UI 不更新」按序查：① ForEach key 缺变化位
  ② 条件藏在 getter/方法 ③ 高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（第 8 次同型）⇒ 首选「表达式内联回 build()」。
  ⚠️ 带参 @Builder 里只要有 `if`，分支同样定死；⚠️ `key` 只对 ForEach 列表项有效。
- **页面内容超一屏必须套 `Scroll`**（2026-11-06 私记事故：裸 Column 把「关于/隐私政策」挤出屏幕
  且滑不动 ⇒ 审核员点不到隐私政策）。写法：标题栏留 Column 固定，正文 `Scroll{Column{}}.layoutWeight(1)`。
- **回后台 ≠ 用户暂停**：后台停表**不改状态**，回前台自动续；用独立 `suspended` 区分主动暂停。
  浮层同理：别同步两套状态 ⇒ **到点才判断**；按钮多态时**按了会发生什么必须写在按钮上**。
- **Journal 锁库三铁律 + 截图期把上锁档位临时改 5 分钟** ⇒ `reference-arkui-pitfalls.md` 第八节。
- **日期一律本地时区**，禁用 `toISOString()`（东八区 00–08 点写成昨天）。CI 有守门单测。
- 🔒 **release 混淆**改 JSON 落盘字段名 ⇒ 文件级 `-keep`（条目不能缩进）；**按名反射的跨模块契约**
  （`RecognitionListener`）改名 ⇒ 语音静默失效。⚠️ TtsEngine 不必加，别盲目类推。
- 📁 **桌面交付物用中文应用名**：`Rock阅读-x.y.z-上架.app`（不要 RockReader），否则与旧存档认错包。
- **构建环境 / safe-delete 拦删** ⇒ `reference-signing.md` 末节（含 `cmd //c "scripts\build.cmd"` 的坑）。
- **模拟器点击坐标只取自 `uitest dumpLayout` 的 bounds**（截图目测偏 30px ⇒ 点空被空 onClick 吞）。
  ⚠️ **按钮实际可点区可能小于整行**（私记「日记统计」只覆盖 x≤842，点右侧数字无反应）。
- **鸿蒙桌面图标取 `module.json5` 里 ability 的 `icon`**，不是 `app.json5` —— 换图不生效先查这里。
  ⚠️ **AGC 商店图标是单独上传字段**（216 或 1024、正方形、**不许自己加圆角**、背景禁透明），
  不从包里取；两套口径 ⇒ `reference-icon.md`。
- ⚠️ **记忆台账要进版本库**：Reader 全追踪；Journal 用 `.workbuddy/*` + `!.workbuddy/memory/` ⇒ `git ls-files` 验。

## 六、性能层

详见 `reference-performance.md`。一句话：重活要让帧（`setTimeout(0)`，不是微任务）、点击后先给反馈、
后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 七、发版状态（2026-11-06 23:59）

**在架**：阅读 `1.0.12`、私记 `1.0.11`。

- 🟠 **已提交待审**（2026-11-06 23:59 党哥确认「两个版本都已提交」）：
  阅读 `1.0.14`/`1000015`、私记 `1.0.13`/`1000014`。AGC 图标单独上传 **1024 PNG 方角版**
  （**华为没报错** ⇒ 规格过关；`备用-…圆角` 目录是非必需产物，别当上传件）。
- 🔎 **过审后第一件事**：确认 release 包新图标在设备上真生效（桌面取 ability `icon`
  = `$media:layered_image`，别又退回 `startIcon`）。
- ⭐ **判断「包有没有变」别用 md5**（签名含时间戳）⇒ 解包 `ets/modules.abc` 数符号次数。
- **发 Release / 等审核不盯（2026-10-29）**：只触发不监控，**下个任务开头**再看 `gh run list` / AGC 状态。
- 下一版：阅读 `1.0.15`/`1000016`；私记 `1.0.14`/`1000015`（私记这版要拆门槛）。

## 八、产品对标（对账 ⇒ `reference-roadmap.md`）

**路线链（2026-11-06 十一问定案，全文 ⇒ `reference-roadmap.md`）**：判据「有陌生人在用并留存」
→ 人「鸿蒙普通记录者」（优势是**平台空位**：Day One/Books 无鸿蒙版）→ 分发**只做商店页**
（天花板个位数日新增，接受；阅读分开叙事打长尾）→ 私记**拆门槛**（设备密钥 + 可选界面锁
= 只挡身边人；老数据一次性迁移 + 本机自动备份；必须零 `@kit.*` 纯逻辑测试兜底）
→ 节奏**先传现有包**，审核窗口再改 → 下版主题**写作提醒**。位置标签后置 / PDF 导出不做。
⚠️ 不收集统计 ⇒ 做不了数据驱动，**只做"确定有用"的功能**。⚠️ MD 双向已完成（导入+导出都有）。
B 类（云同步 / 云端 AI）与第一节冲突 ⇒ 主动取舍。**坚决不做**：云同步 / 云端 AI。

## 九、all2md → 台账已迁出

真源 `F:\AI\HarmonyOS\apps\all2md\` 三本台账（`task_plan`/`findings`/`progress`），按阶段组织；
**代码仓是 `F:\AI\HarmonyOS\all2md\`，不同 repo**。⚠️ 包名 `rock.all.2.md`、APP ID
`6917620824955651111` **与 `com.rocktier.*` 不同体系，别顺手统一**。
⭐ 通用打法：**验不了机器就验数据** —— 纯逻辑抽到零 `@kit.*` 内核层，用真实文件喂它。

## 十、ASR（Core Speech Kit）

细节 ⇒ `reference-asr.md`。两条不可协商：键名 **`recognitionMode`**（不是 `recognizeMode`），
值 **0** = 引擎自己开麦 —— 拼错就"引擎起了、界面在听、永远没声且无错误码"；
云测报「语音不生效」既不能当结论也不能当噪音，看 HiLog 有没有 `asr: onResult`。

## 十一、ArkTS 类型三坑

① `null` 与 `undefined` 是两种类型（`x === undefined` 挡不住 null ⇒ 签名写 `T | null | undefined`）；
② 非空断言 `!` 不允许，自写 `isAbsent()` 也不是类型守卫 ⇒ 只能**内联判空**收窄；
③ `arr[k].field !== undefined ? …` 收窄失效 ⇒ 先 `const x = arr[k];`。

## 十二、设计基准：Apple HIG + 鸿蒙 HDS

**唯一基准 <https://developer.apple.com/cn/design/>**（鸿蒙对照 <https://developer.huawei.com/consumer/cn/design/>）。
**UI 类 skill 只起优化作用，不能起决定作用**，冲突一律以 HIG 为准。全家族 + 以后所有应用。
四条硬指标：点击目标 **44pt（绝对最小 28）**、字号 **最小 11fp**、对比度 **4.5:1**、**不许只用颜色传达信息**。
另：不达标**先改 token 不改调用点**；主按钮字色用 `onAccent` 不是 `bg`；说明/slogan 淡化靠留白 +
`muted`，**文案一字不改**；热区 44 让位于「不压邻居」。硬指标表 / 平台分层 ⇒ `reference-hig.md`。
⭐ **渐变只铺空白底层、文字必落不透明面**；阅读跟随系统**照抄 Journal `common/Appearance.ets`**
（禁运行时 `setColorMode`）⇒ `reference-hig.md` 第八节。
