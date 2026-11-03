# ArkUI / 混淆 / 编译 踩坑清单（Rock 家族）

> 从 MEMORY.md 拆出（2026-10-28，因主文件超注入上限）。

## 四、工程铁律（踩过的坑）

- **release 混淆会改名 JSON 落盘字段**（Journal 1.0.2 已带混淆名写盘）：四个开关联合作用，单一白名单拦不住；根治 = 文件级 `-keep` 保护序列化真源，存量 = 读端 fallback 旧名。`-keep` 条目**不能缩进**。
  ⚠️ **新扩展：`-keep` 还要保护「按名反射的跨模块契约」** —— 1.0.6 加了 `-keep ./src/main/ets/data/AsrService.ets`：`RecognitionListener` 五个方法名是**系统 SDK 按名字回调**的，混淆改名 ⇒ 语音功能**静默失效**（能点、能进「在听」、永远等不到文字、零报错）。同类风险 = 一切 SDK 按名调用的接口实现。
- **日期一律本地时区**（todayKey/dateKeyOf/exportDateText），禁用 `toISOString()`（UTC，东八区 00–08 点写成昨天）。CI 有守门单测。
- **编译唯一可用方式**：自带 hvigorw wrapper 已损坏，必须用 DevEco 自带 node 跑 `hvigorw.js`；`DEVECO_SDK_HOME`/`JAVA_HOME` 指向 E 盘 DevEco。debug：`assembleHap --mode module -p product=default -p buildMode=debug`。
- **safe-delete 钩子 vs 构建**：钩子在**单轮删 ≥50 个文件**时拦截（`SAFE_DELETE_BULK_CONFIRM_REQUIRED`）⇒ hvigor 的 `:entry:clean` 失败、报 **00308004 Unable to delete entry\build**。**正解：把 `entry/build`、`.hvigor` 改名让开再构建，不要硬删。** 钩子只拦 **node 进程内**的 fs 删除，bash/PS 的 `rm -rf` 不受限。
- **浮层「点外部关闭」不牢靠**：面板超高时关闭带 layoutWeight 被挤成 0 ⇒ 必须给显式 `×`；关闭带固定高度；固定内容移进 Scroll；Scroll 用 `layoutWeight(1)` 且父链每层高度确定。`constraintSize({maxHeight})` 对 Scroll 无效。
- **@Builder 值参数不随 @State 重跑**（家族级，本族已第 6 次同型坑）：状态变了 UI 不更新 ⇒ ForEach key 带状态后缀 / 拆 if/else / 用**版本号 key 强制重建**（Journal 模板新建区 `addBoxRev`）。同族实例：日历染色 / 收藏星 / 胶囊剧透 / 编辑后列表 / 筛选 chip / **本切换 chip / 模板新建区清空**。
- **⚠️ ArkUI V1 分支条件陷阱（家族级，最重要的发现）**：V1 是「状态变更 → 局部刷新」，**build() 不整体重跑，`if` 的分支条件按首次求值定型**；依赖插桩只认「表达式里直接读 @State」，藏进 getter/方法体里的 @State 访问**追不到**。正解：条件里**就地读 @State**。**@Computed 救不了**（本族是 V1，编译报 `only be used in a 'struct' decorated with '@ComponentV2'`）。「数据变了 UI 不更新」按序查 —— ① ForEach key 少带变化位；② **分支条件藏在 getter/方法里**；③ 组件高度被 layoutWeight 压成 0。
- **UIAbility 基类没有 onConfigurationUpdate**：写 `super.` 能编译但运行时抛错 ⇒ 窗口存在但内容全空（黑屏）。
- **ForEach item 无确定宽度时 `width('100%')` 回退成父级全宽**：item 加 `layoutWeight(1)`。图表数据顺序：左→右 = 过去→现在（newest 压轴），必须体现在单测里。
- **服务卡片（form）三条铁律**（家族级）：① **卡片自定义参数会被系统改键名** ⇒ **按"值"找不按键名找**；② **form 页面禁用 @StorageLink / hilog / onAreaChange**（报 `11706006`），只能用 @LocalStorageProp（dimension 读到的都是默认值）⇒ **form 里做不了按尺寸分支的排版**；③ 卡片页不能打日志，调试只能打在 FormExtensionAbility 里。
- 模拟器 / hdc / 造数 / uitest 全部操作细节 ⇒ 见同目录 **`reference-simulator.md`**（工具手册，别重复抄这里）。
  三个最要命的：① **安全键盘弹出时 screenCap 拍到应用区纯黑**（但 dumpLayout 读得到完整树）⇒ 判据是关掉键盘再截图，别误判成渲染黑屏；
  ② **uitest dumpLayout 会返回旧实例的过期布局** ⇒ 一律以 screenCap 截图为准；
  ③ **`uitest uiInput inputText` 必须三参数** `<x> <y> <text>`，两参数版报「The number of parameters is incorrect」。
- **模拟器上 Rock私记 的主密码是 `123456`**（2026-10-27 设）。

## 五、划词 / 文本选区（2026-11-03 新增，Reader 1.0.10）

- **API 版本真相**（查 SDK 26 `component/text_common.d.ts` 实测）：
  `Text.onTextSelectionChange` **@since 11**、`textSelectable` **@since 12**、`editMenuOptions` **@since 12**；
  只有 **`SelectionContainer` 组件本身** @since 26 ⇒ **做划词不需要升 compileSdk**。
  ⚠️ 「划词必须升 SDK 26」是**误判**，别再照着改工程配置。
- **手势竞争（家族级）**：Text 上挂 `.gesture(LongPressGesture())` 会**抢赢** Text 自带的长按选词
  ⇒ 系统选区**完全不出现**（无手柄、无菜单、UI 树 0 个 TextMenu）。
  ⇒ 要划词就**把长按完整让给系统**，自定义手势挂到别处。
- **`editMenuOptions.onMenuItemClick` 返回值语义**：
  返回 `true` = **完全拦截**系统默认逻辑 ⇒ **系统浮动菜单留在屏幕上**（浮在我们自己的面板上方）。
  返回 `false` = 我们的逻辑先跑、系统默认逻辑照跑（默认逻辑含「收起菜单」）⇒ **要返回 false**。
- **追加的菜单项会落进 ⌄ 溢出菜单**（系统默认项有 4 个：复制/全选/翻译/搜索）⇒ 属正常，别以为没生效。
- **撤选区**：compileSdk 20 的 `UIContext` **没有** `clearFocus`（API 26 才有）；
  切 `textSelectable` **撤不掉已建立的选区**。正解：
  `Text(content, { controller: this.ctrl })`（controller 走**构造第二个参数**，TextAttribute 上没有该方法）
  + `this.ctrl.setTextSelection(0, 0)`（起 ≥ 止 ⇒ 不选任何内容）+ `this.ctrl.closeSelectionMenu()`。
  ⚠️ 残留手柄会**压在抽屉页签上**（正文左上角）⇒ 点页签会重新弹系统菜单 ⇒ 页签点不动。
- **系统长按中文默认只选中 1 个字** ⇒ 任何「少于 N 字就丢弃」的门槛都会把用户点击变成**死路**。
  门槛只能用来「提示用户选区偏短」，**不能用来拦用户的显式操作**。


