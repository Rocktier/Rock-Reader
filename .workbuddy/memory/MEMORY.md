# Rock 家族长期记忆（v7 · 2026-11-09）

> 只记**可执行**知识（命令、判据、禁令）；过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读 + Rock私记 + all2md。深度分册（同目录 `reference-*.md`）：hig / asr / signing /
> releases / performance / arkui-pitfalls / simulator / clouddebug / roadmap / icon。
> ⚠️ **上限 4000 字符**（超了注入会截断）⇒ 增一条挪一条进分册。

## 一、产品口径：非主动联网（2026-10-18 拍板）

「用户可以自己联网下载字体或音色，但**我们自己不会主动联网，主要功能也不联网**。」

- ✅ 用户点「下载」才联网、之后离线用；入口明示「联网下载」+ 体积/进度/重试/无网提示。
- ❌ 主要功能联网（云 TTS / 书城 / 云同步）；❌ 自发联网（检查更新 / 静默下载 / 遥测）。
  麦克风是本地传感器，不算联网。**新增系统能力前先对照此表。**

## 二、上架说明必写两句（**不许软化**）

1. **隐私完全不出设备、不出互联网** —— 不是"重视隐私"，是**技术上做不到外传**。
2. **一切以更好地让 AI 为人服务为目标** —— 产品是为 AI 备料，不是"又一个转换器"。

## 三、签名与出包（细则 ⇒ `reference-signing.md`）

- `assembleApp -p product=release -p buildMode=release --no-daemon`；上传前
  `pwsh scripts/verify-upload.ps1`，**闸门跑在桌面待传包上**。
- **第 0 步只能靠人**：先确认 AGC 当前应用。**包侧全绿仍 993 ⇒ 问题在包之外**
  （抠 Profile `"type"`：debug = 用错 product；release 但包名不符 = 拿错 Profile）。
- **code = 累计序号，与 versionName 解耦**（name 只是展示值，可跳大版本）。
  **私记两处同改** `app.json5` + `AppMeta.ets`；**阅读只改 `app.json5`**（无 AppMeta）。

## 四、法律文件：一个链接覆盖全家族

<https://www.91hym.cn/devs/756.html> 三章 + `#privacy`/`#agreement`/`#rights`，两应用共用。
博客在党哥自己站上 ⇒ 改动要给他「照抄文本」；双写纪律：博客 == 两仓 `pages/Privacy.ets` 逐字一致。
⚠️ **新增权限 ⇒ 同一提交改完两仓 + 交博客文本**；例外：`backgroundModes` 不是权限，政策不改。

## 五、工程铁律（展开 ⇒ `reference-arkui-pitfalls.md`）

- ⭐ **数据变了 UI 不更新**：V1 `if` 分支按首次求值定型、@Builder 值参数不重跑 ⇒ 条件里就地读 @State、
  表达式内联回 build()；按序查 ① ForEach key ② 条件藏 getter ③ 高度被 layoutWeight 压成 0。
- **超一屏必套 `Scroll`**：标题栏固定，正文 `Scroll{Column{}}.layoutWeight(1)`；
  Scroll 内 Column 禁 `height('100%')`（隐私政策被挤出屏幕且滑不动 = 审核级事故）。
- **回后台 ≠ 用户暂停**：后台停表不改状态、回前台自动续；浮层别同步两套状态 ⇒ 到点才判断；
  按钮多态时「按了会发生什么」必须写在按钮上。
- **日期只用本地时区**、`-keep` 护落盘字段与按名反射契约、`safe-delete` 拦删就改缓存目录名
  ⇒ pitfalls 第四节；锁库三铁律 ⇒ 第八节。
- 📁 桌面包用**中文应用名** `Rock阅读-x.y.z-上架.app`，否则与旧存档认错包。
- **点坐标只取 `dumpLayout` bounds** ⇒ `reference-simulator.md`；**桌面图标取 ability `icon`**、
  **AGC 图标单独上传**（216/1024 方形、禁圆角/透明）⇒ `reference-icon.md`。
- ⚠️ **记忆台账进版本库**：Reader 全追踪；Journal `.workbuddy/*` + `!.workbuddy/memory/` ⇒ `git ls-files` 验。

## 六、性能层（⇒ `reference-performance.md`）

重活让帧（`setTimeout(0)`，非微任务）、点击后先给反馈、后台 O(N) 可取消、同步 SDK 调用是秒级嫌疑。

## 七、发版状态（2026-11-09 20:16）

**在架**：阅读 `1.0.14`/`1000015`、私记 `1.0.13`/`1000014`（11-06 提交，党哥 20:16 确认过审）。
**2.0.0/1000016 已备未传**：桌面 `Rock阅读-2.0.0-上架/`，闸门全绿 ⇒ **阻塞解除，可提交**；
上传只能党哥在 AGC 操作，旧商店图在后台替换。指纹 ⇒ `reference-releases.md`。

- 🔎 过审后确认新图标在设备生效（ability `icon` = `$media:layered_image`）。
- ⭐ **判断包变没变别用 md5**（签名含时间戳）⇒ 解包 `ets/modules.abc` 数符号次数。
- **发 Release / 等审核不盯**：只触发不监控，下个任务开头再看 `gh run list` / AGC。
- 下版私记 `1.0.14`/`1000015`（拆门槛独占）；两仓 code 独立累计，同号不冲突。

## 八、产品对标（全文 ⇒ `reference-roadmap.md`）

11-06 十一问定案：判据「有陌生人在用并留存」→ 鸿蒙普通记录者 → **只做商店页**（阅读打长尾）
→ 私记拆门槛（设备密钥 + 可选界面锁 + 本机自动备份，零 `@kit.*` 测试兜底）→ 先传现有包、
审核窗口再改 → 下版主题**写作提醒**。位置标签后置 / PDF 导出不做。
⚠️ 不收集统计 ⇒ **只做"确定有用"的功能**；MD 双向已完成。**坚决不做**：云同步 / 云端 AI。

## 九、all2md → 台账已迁出

台账真源 `F:\AI\HarmonyOS\apps\all2md\`（`task_plan`/`findings`/`progress`）；
**代码仓 `F:\AI\HarmonyOS\all2md\` 是不同 repo**。⚠️ 包名 `rock.all.2.md`、APP ID
`6917620824955651111` **与 `com.rocktier.*` 不同体系，别顺手统一**。
⭐ **验不了机器就验数据**：纯逻辑抽到零 `@kit.*` 内核层，用真实文件喂它。

## 十、ASR（Core Speech Kit）

细节 ⇒ `reference-asr.md`。两条不可协商：键名 **`recognitionMode`**（不是 `recognizeMode`），
值 **0** = 引擎自己开麦 —— 拼错就"引擎起了、界面在听、永远没声且无错误码"；
云测报「语音不生效」看 HiLog 有无 `asr: onResult`，不能当结论也不能当噪音。

## 十一、ArkTS 类型三坑

`null`≠`undefined`（签名写 `T | null | undefined`）、禁 `!` 且自写守卫不收窄（只能内联判空）、
`arr[k].field` 收窄失效（先 `const x = arr[k]`）⇒ 详见 pitfalls 第九节。

## 十二、设计基准：Apple HIG + 鸿蒙 HDS

**唯一基准 <https://developer.apple.com/cn/design/>**；鸿蒙 HDS 只作平台对照（`reference-hig.md`）。
**UI 类 skill 只起优化作用不能起决定作用**，冲突以 HIG 为准。全家族 + 以后所有应用。
四条硬指标：点击目标 **44pt（绝对最小 28）**、字号 **最小 11fp**、对比度 **4.5:1**、**不许只用颜色传达信息**。
不达标**先改 token 不改调用点**；主按钮字色 `onAccent` 不是 `bg`；说明/slogan 靠留白 + `muted`，
**文案一字不改**；热区 44 让位于「不压邻居」。
⭐ **渐变只铺空白底层、文字必落不透明面**；跟随系统照抄 Journal `common/Appearance.ets`
（禁运行时 `setColorMode`）⇒ `reference-hig.md` 第八节。
