# Rock 家族长期记忆（2026-11-03 精简版）

> 只记**可执行**知识（命令、路径、判据、禁令）。过程细节进当日日志 `YYYY-MM-DD.md`。
> 范围：Rock阅读（RockReader）+ Rock私记（RockJournal）**两个仓**。
> 深度清单 ⇒ 同目录 reference-*.md：
> `reference-signing.md`（签名出包上传）· `reference-performance.md`（性能铁律）·
> `reference-arkui-pitfalls.md`（ArkUI/混淆/编译坑）· `reference-simulator.md`（hdc 工具）·
> `reference-roadmap.md`（产品对标）。

## 一、产品口径：非主动联网（党哥 2026-10-18 拍板）

「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 用户主动点「下载」→ 联网拉资源 → 之后离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见、失败可重试、无网时明说。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 麦克风（Journal 1.0.6）不算联网 —— 本地传感器。
- **新增任何系统能力前先对照此表。**

## 二、签名与出包

- **每次出包必读 `reference-signing.md`**（命令、闸门、993 排查、验收三步、PowerShell 坑）。
- 关键三条：① 出包 `assembleApp -p product=release -p buildMode=release --no-daemon`；
  ② 上传前必跑 `pwsh scripts/verify-upload.ps1`（不过就 throw）；③ **上传前先确认 AGC 后台当前应用 = 该应用**。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。
  **博客在党哥自己的站上，代码改不到 ⇒ 改动要给党哥「照抄文本」。**
- 双写纪律：博客 `#privacy` 章 == 两仓应用内 `pages/Privacy.ets` == 逐字一致。
- ⚠️ **新增权限 ⇒ 必须同步隐私政策**（1.0.6 踩到：加麦克风后第四节原写「两款应用都不申请任何权限」⇒ 政策与实现不符 = 拒审理由）。
  **纪律：任何新权限/新数据形态 ⇒ 同一提交内改完应用内两仓 + 产出博客待同步文本。**
  ⚠️ **例外：`backgroundModes`（后台模式声明）不是权限、不采集数据** ⇒ 隐私政策无需改（Reader 1.0.8 已过审 = 实证）。

## 四、工程铁律（踩过的坑）

- ⭐ **记忆台账要进版本库**：Reader 仓 `.workbuddy/memory/` 全部被追踪；Journal 仓已改为 `.workbuddy/*` + `!.workbuddy/memory/`。
  ⇒ **改 .gitignore 后记得 `git add -A` 确认日志真的进去了**（`git ls-files .workbuddy` 可验）。
- **release 混淆会改名 JSON 落盘字段** ⇒ 文件级 `-keep` 保护序列化真源（`-keep` 条目**不能缩进**）。
  ⚠️ **`-keep` 还要保护「按名反射的跨模块契约」** —— 1.0.6 加了 `-keep ./src/main/ets/data/AsrService.ets`
  （`RecognitionListener` 五个方法名由系统 SDK 按名字回调，混淆改名 ⇒ 语音功能**静默失效**：能点、能进「在听」、永远等不到文字、零报错）。
  ⚠️ 反例：Reader 仓 TtsEngine **不必**加 -keep（混淆**没**破坏 SDK 按名回调的 `SpeakListener.onStart/onComplete`）。**不要盲目类推**。
- **ArkUI V1 分支条件陷阱（家族级最重要发现）**：V1 是「状态变更 → 局部刷新」，**build() 不整体重跑，`if` 的分支条件按首次求值定型**；
  依赖插桩只认「表达式里直接读 @State」，藏进 getter/方法体里的访问**追不到** ⇒ 条件里**就地读 @State**。**@Computed 救不了**（本族是 V1）。
  「数据变了 UI 不更新」按序查：① ForEach key 少带变化位 ② 分支条件藏在 getter/方法里 ③ 组件高度被 layoutWeight 压成 0。
- **@Builder 值参数不随 @State 重跑**（已第 6 次同型）⇒ ForEach key 带状态后缀 / 拆 if/else / 版本号 key 强制重建。
- **safe-delete 钩子**：单轮删 ≥50 文件会拦（报 00308004 Unable to delete entry\build）⇒ **把 `entry/build`、`.hvigor` 改名让开再构建，不要硬删**。
- ⭐ **浮层状态机铁律**：要让「浮层开着时后台行为停」，**不要**在「开浮层时暂停 / 关浮层时恢复」（要在每一处 `showXxx` 赋值点同步两套状态，漏一处就是幽灵 bug）
  ⇒ 改成**到点才判断**（定时器回调里就地判 `if (浮层开着) return;`）：**状态只有一处，没有影子状态**。
  配套：浮层与控件**不能叠在同一位置**；一个按钮覆盖多态时**按了会发生什么必须写在按钮上**
  （OFF→`滚屏`/RUNNING→`停滚屏`/PAUSED→`继续滚屏`）；⚠️ **PAUSED 必须映射到「继续」不能映射到「关掉」**。
- **回后台 ≠ 用户暂停**：后台停表但**不改状态**，回前台自动续上（通勤场景）。用独立的 `suspended` 标志区分「用户主动暂停」。
- **日期一律本地时区**，禁用 `toISOString()`（UTC，东八区 00–08 点写成昨天）。CI 有守门单测。
- ⚠️ **发版纪律：版本号两处一起改** —— `AppScope/app.json5` 与 `entry/src/main/ets/common/AppMeta.ets`（1.0.6 漏改 AppMeta ⇒ smoke 测试红着）。
- ⚠️ **列表里的装饰性竖条不能用 `height('100%')`** ⇒ 吃满整个 ListItem 变成分隔线（1.0.9 摘录色标踩到）⇒ 固定 20vp + alignSelf(Start)。
- ⭐ **划词三条铁律（2026-11-03 实测）**：
  ① **Text 上挂自定义长按手势会抢赢系统选词** ⇒ 要划词就把长按**完整让给系统**（自定义摘录入口挂菜单项，不挂手势）；
  ② `onMenuItemClick` **返回 false**（返回 true = 完全拦截 ⇒ 系统浮动菜单留在屏幕上不收）；
  ③ 撤选区用 `Text(content,{controller})` + `TextController.setTextSelection(0,0)`（compileSdk 20 **无** `clearFocus`，切 `textSelectable` 也撤不掉）。
  ⚠️ **系统长按中文默认只选 1 个字** ⇒ 「少于 N 字就丢弃」的门槛会把用户点击变成**死路**（门槛只能用来提示，不能用来拦显式操作）。
  ⚠️ **划词不需要升 compileSdk**（2026-11-03 推翻 1.0.9 release notes 里的误判）：
  `onTextSelectionChange` @since 11、`textSelectable`/`editMenuOptions` @since 12，compileSdk 20 全都能用；
  只有 `SelectionContainer` 组件 @since 26，而划词根本不需要它。
  ⇒ **别再为了划词去升 compileSdk**（当年就是没回查 SDK 声明才写错的）。
  详细清单 ⇒ `reference-arkui-pitfalls.md` 第五节。
- ⭐ **模拟器点击坐标只能取自 `uitest dumpLayout` 的 bounds**（截图目测会偏 30px ⇒ 点空被 Column 的空 onClick 吞掉，表现为「点了没反应」）。
- ⚠️ **构建时 `DEVECO_SDK_HOME` 要指向 `...\DevEco Studio\sdk`（根目录）** ⇒ 指到 `sdk\default` 报 00303312「找不到对应 SDK 版本」。
- ⭐ **锁库三铁律（Journal 后台即锁，2026-11-03）**：
  ① **先落盘再锁** —— 密钥一清 `encrypt()` 返 null ⇒ 防抖窗口内没落盘的内容**永远存不下来**
  ⇒ 页面 `onPageHide` 立刻落盘 + 锁库延迟 **> 自动保存防抖**；
  ② **只清密钥不够** —— 还要清内存里的**内容预览**（否则回前台屏幕上一屏摘要 = 锁了没锁住）；
  ③ 送回解锁页必须 **router.clear() 再 replaceUrl**（只 replaceUrl 会让返回键翻回已解密页面）。
- ⭐ **ArkTS 类型三坑（all2md 2026-11-03，单测/编译才发现）**：
  ① **`null` 与 `undefined` 是两种类型，`x === undefined` 挡不住 `null`**（TS 不互兼容）
  ⇒ 函数签名写成 `T | null | undefined`，判空写 `x === null || x === undefined`；
  ② **非空断言 `!` 不允许**，且**自定义 `isAbsent()` 不是类型守卫**（TS 不据此收窄）
  ⇒ 不能「先判空再用 `!`」，只能**内联判断**让类型自然收窄；
  ③ **`arr[k].field !== undefined ? arr[k].field : ''` 收窄失效**（两次下标是不同表达式）
  ⇒ 必须先取局部变量 `const x = arr[k];` 再判。


## 五、性能与验证层

- **详见 `reference-performance.md`**：AGC「点击操作完成快」检测口径 + 六条铁律 + 验证层四坑。
- 一句话：重活要让帧（`setTimeout(0)`，不能微任务）、点击后先给反馈、后台 O(N) 活必须可取消、同步 SDK 调用是秒级嫌疑。

## 六、发版与版本状态

- **Reader 1.0.10（code 1000011）** —— 划词「加入摘录」全链路 + 阅读页屏幕亮度 6 档/常亮。
  包 `C:\Users\Dang\Desktop\Rock阅读-1.0.10-上架.app`，2,385,809 字节，
  md5 `49268A7881C9C6431300ECCDCD48125E`，sha256 `9D473446B7826084D2DA0ACB8176940C235AADA846C6C22BBAD9FD6C7EDC10E5`；
  闸门 13 项全 PASS（桌面包 + 产物目录各跑一次）；commit `af56528`，tag `v1.0.10` 已 push。
  模拟器实测：长按→系统选区→系统菜单「加入摘录」→面板预填选中句→落库→标记页签可见「转」；
  亮度从 0.15 起循环、UI 标签同步刷新、重启后持久；常亮被系统 WMS 确认、离页还原 ×2。
  ⚠️ 桌面同时有 `Rock私记-1.0.8-上架.app`（331,461 字节，另一个应用）—— **别拿错**。
  ⚠️ **1.0.10 有 2 项未在真机实测**（真机划词手感 / 真机深色环境亮度观感）。
- **Journal 1.0.8（code 1000009）** —— 删单篇日记入口 + 后台即锁。
  包 `C:\Users\Dang\Desktop\Rock私记-1.0.8-上架.app`，331,461 字节，
  md5 `4A80C127972228C45A7717D25BD47708`，sha256 `764B92FB1ED99AF6A064290F844982151C55498E195098E198A7B84475F45726`；
  闸门全 PASS；commit `1e952db`，tag `v1.0.8` 已 push。
  模拟器实测：删后时间轴「共 0 篇 / 还没有日记」；后台即锁时序 `onBackground → 15ms 内 save ok=true → 2s 后 locked`；
  回前台落解锁页，重新解锁后 `LockTest…` 一字未丢。
  ⚠️ 1.0.8 未在真机实测 ⇒ 装新包需回归 4 件事：老库主密码解锁 / legacy 兼容 / 首次建库 / 生物解锁。
- **旧版存档**：Reader 1.0.9（code 1000010，md5 `501DB7B…`）、Journal 1.0.7（code 1000008，md5 `AFDDB74C…`）
  —— 已被 1.0.10 / 1.0.8 取代，桌面已无旧包。
- **测试基线**：Reader **297/297**；Journal **240/240**（含 KDF 参数守门 6 条）。
- **2026-11-03 两仓同日出包**：1.0.10 与 1.0.8 均已 push main + tag。
  出包命令 `assembleApp -p product=release -p buildMode=release`；
  闸门**要跑在桌面待传包上**（不是产物目录那份）。
- **tag 规则**：push main 只跑编译校验+单测；**push tag v\* 才触发 `gh release create`**（编译失败则不执行）。
- ⚠️ Reader 的 `fonts-v1` 本地与远端指向不同 commit ⇒ `git push --tags` 会被拒，**这是正常的**（字体包 tag 与版本发布无关，别动它）。

## 七、CI 现状（党哥拍板「CI 不急」）

- **Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红**。根因：CI 用**公开 OpenHarmony SDK**，
  而 `@kit.CoreSpeechKit`、`@kit.ShareKit` 是 **HarmonyOS 专有 kit** ⇒ 报 10505001 / 10311003。
  后果：编译校验形同虚设，**打 tag 也不会发 GitHub Release**。
- 已排除：注入 hms kit；改 runtimeOS（被 00303038/00303313 卡死）；工程内桩（被 `arkts-no-untyped-obj-literals` 10605038 拦）。
- 将来要修：CI 工作区把 kit 的类型声明**内联到消费文件顶部**（ArkTS 要求同文件），再改 import。
- ⭐ **发 Release 不盯（党哥 2026-10-29 定）**：push tag 后**只推不监控**。**隔一段时间、等下一个任务开始时**再回头看那批 run 成功没有（`gh run list`）。⇒ 做完「推 tag」即可收工。

## 八、产品对标与迭代方向

⭐ **家族第 9 个应用：`all2md`（2026-11-03 立项 + 当日搭工程并完成内核）**
定位 **AI first —— 把手机上的杂乱文件转成 AI 读得懂的 Markdown + 对标 Typora 的阅读器**。
参照 `microsoft/markitdown`（MIT）。文档：`all2md/docs/整体规划-2026-11-03.md`、`docs/ui-mockup-v1.html`、
`docs/AGC-应用信息-2026-11-03.md`（**配置真源**）。
- ⚠️ **包名 `rock.all.2.md`**、APP ID `6917620824955651111` —— 与家族 `com.rocktier.*` **不是同一体系，
  别顺手统一**（AGC 建了改不了）。支持设备 phone/tablet/2in1，**零权限**。
- `compatibleSdkVersion "6.1.0(23)"`（PDF 文本抽取 `getTextContent()` 是 API 23 才有）/ `targetSdkVersion "26.0.0"`。
- ⚠️ **build-profile 版本字段两坑**：① `runtimeOS: HarmonyOS` 下必须写**字符串**（写数字报 00303038）；
  ② `"26.0.0(26)"` 报 **00308018** —— 26 代 API 号本身是三段式，正确写法是**不带括号的 `"26.0.0"`**。
  版本名↔API 映射表在 `DevEco/tools/hvigor/.../hos-sdkmanager-common/build/res/hos-config.json`。
- 三条硬结论：① **PDF 文本抽取要 API 23**；② **DOCX/XLSX/PPTX 与 Markdown 渲染鸿蒙都没有官方能力** ⇒ 自研，占 80% 工作量；
  ③ **Pandoc 是 GPL-2.0，一行代码都不能碰**（只对标格式矩阵）。
- 内核已完成（`core/` 下零 `@kit.*`）：AST / MarkdownWriter / 体检 A1–A7 / 段落重排 / TXT / CSV /
  **XML 解析器 + DOCX 读入器**，**单测 238/238**，ArkTS 编译通过。
  ⚠️ 仓库**只在本地**（`git init` 无 remote，党哥要求「代码先全放本地」）。
- ⭐ **DOCX 与 PDF 的根本差别：`structureInferred`**。DOCX 的标题来自 `w:pStyle`/`w:outlineLvl`，
  是作者声明的（`false`）；PDF 只能启发式猜（`true`）。**这个标记必须一路传到体检报告**，
  否则用户分不清「这个 `##` 是真的还是猜的」。⇒ 先做 DOCX，PDF 排后面。
- ⭐ **合并单元格只能降级，不能补全**：GFM 没有合并语法 ⇒ `gridSpan` 展宽补空、`vMerge` 延续格留空
  （行列数与视觉网格一致）。**「按视觉补全内容」更糟 —— AI 会读到重复信息。**
- 领域铁律（测试逼出来的）：**页码判断要排在列表判断之前**（`- 12 -` 会被当列表项）；
  **列表项遇句末标点即结束**（否则吞掉后面整段正文）；**中文单空格不能无脑删**（`第二条 结算周期`）；
  **只含图片的段落不能产出空段落块**（否则 A7 假警报盖住「图片没 alt」这个真问题）。
- ✅ **调试签名已打通（2026-11-03 22:15）**：DevEco 自动签名生成
  `~/.ohos/config/default_all2md__*.{p12,cer,csr,p7b}`，已装模拟器跑通。
  ⭐ **华为调试证书所有应用共用一张**（`0D:AA:8A:96:…:71:80`），按 profile 里的 bundleName 区分
  ⇒ Reader / Journal / all2md 三个仓的调试证书指纹**完全一样**（别指望靠指纹区分应用）。
- ⭐ **`signingConfigs` 写了 ≠ 生效**：DevEco 自动签名**只写数组、不在 product 里引用** ⇒
  只报一行 `WARN: No signingConfig found for product default`，**BUILD SUCCESSFUL 照样绿**，
  产物是 `*-unsigned.hap`。⇒ `app.products[0]` 必须写 `"signingConfig": "default"`。
  **判据：看产物文件名有没有 `-signed`；`SignHap` 跑过 ≈2.3 s，没跑是 2 ms。**
- ⬜ 仍欠**正式上架证书**（`.p12`/`.cer`/`.p7b` 三件套，AGC 里建），出正式包时再弄。
细节 ⇒ 当日日志第 6、7、8、9 节。

主标杆 **Day One**（Journal）/ **Apple Books·Kindle·静读天下**（Reader）。完整对账表 ⇒ `reference-roadmap.md`。
文档：`RockReader/docs/生态融入与对标改进方案-2026-10-25.md`（第七节 = 当前真实差距，已按 10-29 实测修订）。

- **A 类·本地零联网（优先做）**：① 语音转文字 ✅1.0.6 ② 位置标签 ⬜ ③ 写作提醒 ⬜ ④ Markdown 双向 ⬜
  ⑤ 自定义模板 ✅1.0.6 ⑥ 多日记本 ✅1.0.6 ⑦ PDF 导出 ⬜ ⑧ 每日提示 ✅1.0.6
- **B 类·需联网**（云同步 / 云端 AI / IFTTT）—— 与第一节口径冲突，**主动取舍，不是落后**。
- **C 类·我们领先（卖点）**：全量本地加密、时间胶囊硬封存、完全离线、不绑云账号。
- **坚决不做**：云同步 / 云端 AI。

## 九、ASR（Core Speech Kit）家族知识

**能力边界**：只有**中文普通话**、只有**离线模型**（短 ≤60s / 长 ≤8h）；**模拟器没有离线引擎 ⇒ 识别效果必须真机验**；仅中国区 Phone/Tablet。

**三个必踩的坑**
1. **`online` 名与值相反**：.d.ts 原话 _"**1**: offline"_ ⇒ **1 = 离线**（0 = 联网，未支持）。网上教程写 `online: 0` 表示离线是错的。
2. **`StartParams.extraParams['recognizeMode']` 必须显式给 0**：0 = **引擎自己开麦**（只要 MICROPHONE 权限，不必自己 AudioCapturer 喂 PCM）；**省略会默认走 1（外部 writeAudio）⇒ 起了引擎却没声音进来**。⚠️ 键名是字符串，编译器查不出。
3. **权限结果类型写不出名字**：`PermissionRequestResult` **没有导出到 `abilityAccessCtrl` 命名空间** ⇒ **靠 `const res = await ...` 推断拿它**。

**固定套路**：监听器 5 个方法全必填（先 `const self=this`、字面量落接口变量、方法语法）；`createEngine` 用**回调版**，成功时 **err 是 undefined 不是 null**；结果累积 = **isFinal 累加 + 非 final 取最后一条**。留纯逻辑层，真机若发现是累计全文，改 `collectFinalText` 一行即可。

**没真机时的验证策略（可复用到任何"必须真机"的能力）**
1. 纯逻辑抽出（不引 @kit）⇒ esbuild + node:test 单测；
2. **用真 SDK 编译**（`-p product=default`）验 API 签名 —— CI 的 OpenHarmony SDK 验不了；
3. **"用不了"当一等公民**：引擎起不来 ⇒ UNREADY + 按钮**禁用但保留** + 如实文案；
4. **按名反射的接口实现加 `-keep`**（混淆改名 ⇒ 静默失效）；
5. 上架说明一个字不提，直到真机验过。
