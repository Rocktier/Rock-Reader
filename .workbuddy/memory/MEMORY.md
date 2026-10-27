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
- **模拟器息屏与安全键盘（2026-10-26 新坑，差点误判）**：① 约 30s 自动息屏，息屏后截图整屏纯黑无状态栏 ⇒ `hdc shell "power-shell wakeup"` 点亮，`power-shell timeout -o <ms>` 覆盖息屏时间（**参数是 -o**，`-r` 恢复）；② **安全键盘是 secure 窗口，键盘弹出期间 screenCap 拍到的应用区域是纯黑，而 dumpLayout 仍读到完整 UI 树** ⇒ 极易误判成"渲染黑屏"，**判据：按 Back 关掉键盘再截图**；③ 系统设置应用 `aa start -a com.huawei.hmos.settings.MainAbility -b com.huawei.hmos.settings` 直拉且**保留上次页面**，深浅色切换在「显示和亮度 → 显示模式」的 Radio（浅 ~(349,1634) / 深 ~(907,1634)），「深色模式：全天开启」那行是定时规则不是开关。
- hdc 不在 PATH，绝对路径 `/e/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`；uitest 语法 `uitest uiInput click <x> <y>`。设备绝对路径需 `MSYS_NO_PATHCONV=1`；本地路径用相对（cd `/f/AI/HarmonyOS`）；键盘弹出后输入框位移，必须重新 dumpLayout 再 inputText；DEL = `keyEvent 7`；状态栏 y<136 吞点击；多步连点间隔 2~3s。
- **uitest dumpLayout 会返回旧应用实例的过期布局**（2026-10-25 实测：新 UI 装机后仍报旧 4 按钮菜单）⇒ **一切以 screenCap 截图为 ground truth**。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；视觉模型会误读选中态，chip 选中态以黑底像素扫描为准。
- **服务卡片（form）三条铁律**（2026-10-26 在 Rock私记 上实拍踩出来的，家族级）：
  ① **卡片自定义参数会被系统改键名** —— 卡片写 `params:{bookId:'x'}`，系统拉起 ability 时传的是 `{"a9":"x","params":"{\"a9\":\"x\"}",…}`，**键被重命名成 a0/a1/…（按位置排）** ⇒ 只认原键名必然读不到（症状：点了卡片应用起来了但没反应）⇒ **按"值"找不按键名找**；② **form 页面禁用 @StorageLink / hilog / onAreaChange**（ArkTS 报 `11706006 can't support form application`），只能用 @LocalStorageProp，而它读到的 dimension 在 2×4 实例上是默认值 ⇒ **form 里做不了按尺寸分支的排版，统一布局通吃**；③ 卡片页不能打日志，调试只能打在 FormExtensionAbility 里。
- 沙箱写入（2026-10-27 更正）：`hdc file send` **写不进应用沙箱**（SELinux 拒），shell `cat`/`mkdir` 也不行；**真正能写应用私有目录的是设备上的 `sqlite3` 的 `writefile()`**（权限最高）。**但只能写 `haps/entry/files/`，写不进 database 目录**（见「模拟器造数」一节的更正）。
- 存量已知问题（2026-10-25 发现，未修待拍板）：① 幽灵阅读会话——应用后台/被杀不关会话，下次打开补 end_at，产生超长假会话污染统计（曾 1314 分钟）；建议 flush 加时长上限或生命周期关会话。② 抽屉打开时系统返回直接退出阅读页（应先关抽屉）。
- 测试基线：Reader **202/202**（1.0.7 新增 14 条：书架搜索 + 摘录导出）、Journal 139/139。
- tag：Reader v1.0.1~v1.0.5、Journal v1.0.0/v1.0.2/v1.0.4（**本地未 push**）。
  Reader **1.0.6（code 1000007）已于 2026-10-26 提交 AGC，党哥确认已通过**——含桌面续读卡片 + 批次 A 四项；
  上架说明见 `docs/release-notes-1.0.6.md`。push 会触发 CI 建 GitHub Release，发版时机听党哥。
  Journal **1.0.5（code 1000006）已含桌面卡片 + 深色模式修复，卡片与深色均在模拟器实测通过，
  出包三步验收过，上架说明 `RockJournal/docs/release-notes-1.0.5.md` 已定稿 ⇒ 待党哥提 AGC**。
  Reader **1.0.7（code 1000008）已出 release 包并三步验收过，commit `de258bb`（本地未 push）**，
  桌面 `Rock阅读-1.0.7-上架.app`（md5 `09844eb39bf6e6e40a7f11cafc9b996e`），
  上架说明 `docs/release-notes-1.0.7.md` 已定稿 ⇒ **待党哥提 AGC**。
  Reader 卡片点击定位 bug（参数改键名，commit f9e68e5）**端到端已在 release 包本体实测通过**（2026-10-27）。

## 1.0.7 现状（2026-10-27 晚：**四项全部收口，release 包已出**，代码 commit 未 push）

对标静读天下的四项改进，顺序 3→2→1→4。commit `1aa9249`（三项功能）+ `de258bb`（版本号 + 上架说明）。单测 202/202。
- **第3项 进度按真实字数 ✅**：根因是 `onAreaChange` 首次回调兜底分支 `openChapter()` 后漏调 `surveyChars()`，而 `init()` 里那个 `if(this.areaReady)` 首次进入恒不成立 ⇒ `char_count` 恒空。修法：补调用 + `.catch()`（`surveyChars` 只有 try/finally **没有 catch**）。实测 21 章不均长书：char_count 全量回填（与产品源码算的逐字一致），第 7 章处 progress=0.88%、书架显示 1%，旧按章数口径应为 29%。
- **第2项 书架搜索 ✅**：`normalizeQuery/matchesQuery/filterByQuery`（书名+作者，故意不做拼音，撞"极致小"铁律）+ 搜索框 + 搜索专属空态 + 「继续阅读」卡片随搜索联动。
- **第4项 摘录导出 ✅**：`MarkExport.ets` 纯函数（`exportDateText` 必须本地时区）+ systemShare（`ShareKit`+`utd TEXT`）零权限零联网；标记面板底部「导出这本书的笔记」→ 系统分享面板出《进度测试书》的笔记。
- **第1项 备份：结论反转，暂缓！** `EntryBackupAbility` 空实现**不是 bug**，官方明说就是推荐做法；`backup_config.json` 无 `includes` 也大概率是有效默认。**贸然写 includes 若路径写错反而缩小备份范围** ⇒ 只能真机克隆定性，模拟器验不了；按家族纪律，没实测就在上架说明一个字不提。
- **卡片点击定位 ✅（release 包本体端到端）**：装 release 包 → 应用内 picker 导入一本书 → 打开产生 progress → 桌面加卡片（显示 19% / 书名）→ `aa force-stop` → 点卡片 → **冷启动直接落到那本书的阅读页**。日志：`RouterEvent:call` → `onCreate theme=dark` → `open book from card: b_2cb28274-…` → `char survey done: 3/3 chapters measured` → `card pushed, forms=1`。
- 模拟器造书的完整配方已固化成 `scripts/seed-sim-book.mjs`（**但外部造库这条路已封死，见下节更正**）。

## 出包验收三步（2026-10-27 校正工具用法，家族级）

- **① 验签**：`app_check_tool.jar verify-app` **已失效**（报 9132101，所有参数被判 invalid）。
  正确工具是 **`hap-sign-tool.jar`**：`verify-app -inFile X.app -inForm zip -outProfile <本地路径> -outCertChain <本地路径>`
  ⇒ 输出 `Digest verify result: true` + `verify-app success`。
  ⚠️ `hap-sign-tool.jar` **没有 `verify-hap` 命令**；`-inForm` 只接受 `bin/elf/zip`。
- **② 抠包内 Profile 看 `type`**：用 `verify-app -outProfile` 导出后，python 正则找 `"type":"\w+"`。
  必须 `release` + 本应用包名 + 无 `debug-info`/`development-certificate`。
- **③ 本地 p7b 先验**：比对包内 Profile 与 `keys/rockreader-v2.p7b` 的 md5，**逐字节一致**才算过。
- 复核包内 `module.json` 的 versionCode/versionName/包名。
- **release 构建偶发失败**：第一次跑可能 11 秒就 `Failed :entry:default@CompileArkTS` 且**日志里没有任何 ERROR 行**（真因不明）。
  **原样重跑一次就 BUILD SUCCESSFUL** ⇒ 遇到这种「无信息失败」先重跑，别急着改代码。

## ⚠️ ArkUI V1 分支条件陷阱（家族级，本次最重要的发现）

**症状**：数据变了但某个 `if` 分支不跟着变（本次：搜索过滤掉了书，「没搜到」的空态永远不出现）。
**根因**：ArkUI V1 是「状态变更 → 局部刷新」，**build() 不整体重跑，`if` 的分支条件按首次求值定型**；依赖插桩只认「表达式里直接读 @State」，藏进 getter/方法体里的 @State 访问**追不到**。
**正解**：条件里**就地读 @State**（`if (this.query.length > 0 && this.visibleItems().length === 0)`）。**@Computed 救不了**：编译报 `only be used in a 'struct' decorated with '@ComponentV2'`（本族是 V1 组件）。
**与老坑合流判据**：「数据变了 UI 不更新」按序查 —— ① ForEach key 少带变化位；② **分支条件藏在 getter/方法里**；③ 组件高度被 layoutWeight 压成 0（根 Column 必须给确定高度，否则两个空态一直是隐形的）。

## 模拟器造数（2026-10-27 大更正：外部造库已封死，应用内 picker 才是出路，家族级）

⚠️ **本节 2026-10-27 晚被推翻重写。** 旧结论「导入通道全封、靠 sqlite3 writefile 造库」**只对当时那台设备/那套路径成立，现在不成立**。

**为什么外部造库走不通了**
- RdbStore 的库在**加密存储**里：应用视角 `/data/storage/el2/database/entry/rockreader.db`
  （从 hilog 的 `recovered N frames from WAL file /dat***/sto***/e**/database/ent***/r**/roc***der.db-wal` 反推），
  物理侧落在 **`/data/app/el2/100/database/`**——该目录 shell `ls` 直接 **Permission denied**。
- `sqlite3` 也打不开它（`unable to open database file`），`writefile()` 只能写 `haps/entry/files/`，写不进 database 目录。
  ⇒ **books/chapters/progress 三张表外部写不了**。
- `/storage/media/**`、`/storage/emulated/0`、`/storage/users/currentUser` 在这台模拟器上**根本不存在**；
  `/storage/media/100/local/files` 存在但 Permission denied，`writefile` 也写不进去。

**✅ 真正的出路：应用内文件选择器（picker）是通的**
书架右上「+」→ 系统 picker → **浏览 → 我的手机 → Download** —— 里面**已经有历史测试留下的
txt / epub / md / html 文件**（`rock-import-test.txt`、`journal-test.txt`、`暗恋.epub`…）。
选中即导入，**books/chapters/progress 由应用自己写**（应用会把书复制进自己 `files/` 并按自己的切章规则建表）。
⇒ 造书**不需要造库**，只需要在 Download 放一个文件；而 Download 里本来就有。
- picker 的「最近」页是空的、「我的手机」根目录有 `Rock私记.dbak` 之类的历史文件。
- 路径找不到时不要硬猜：`/storage/*` 大多 Permission denied，**用 picker 界面本身当探针**。

**仍然有效的通用坑**
- `sqlite3 <db> < file` **不生效**（只执行第一行），必须 `cat file | sqlite3 <db>`；`readfile()` 在该 build 里没编（返回 NULL），`writefile()` 可用；大 blob 走管道传 SQL 文件（452KB 一次成），走命令行传 64KB hex 会被 Windows 拒（Argument list too long）。
- **`hdc file send` 的远端路径会被 Windows 化**（`/data/local/tmp/x` 被解析成本地盘符路径，报 `read-only file system, path:./E:`）。
  稳妥做法：`base64 -w0` 后经 `hdc shell "echo '<b64>' | base64 -d > /data/local/tmp/x.sql"` 写文件，再 `hdc shell "cat /data/local/tmp/x.sql | sqlite3 :memory:"`。
  `hdc file recv` 拉设备文件可用（相对路径或 `MSYS_NO_PATHCONV=1`）。
- **shell 与应用是两套 mount 视图**：shell 看不到 `/data/storage/**`，应用也看不到 `/data/app/**` ⇒ books.path 必须写**应用视角**路径。
- 写库前 `aa force-stop` + 删 `-wal/-shm/-dwr/-compare`；shell `mkdir` 一律被拒（没有 add_dir 权限）。
- `hdc list targets` 返回 `[Empty]` 但 Emulator.exe 还在 ⇒ PowerShell 查监听端口得 `127.0.0.1:5555`，再 `hdc tconn 127.0.0.1:5555`。
- **`hilog` 是流式的**：`hilog | tail` 永远不返回（被 timeout SIGTERM），必须 `| head -N`；要持续抓就跑后台任务 + `TaskStop`。
- 切章规则**绝不手写复刻**：用 esbuild 把 `.ets` 当 TS 编译，直接跑产品自己的 `splitChapters`，偏移量与应用导入时逐字节一致。

## 模拟器导入通道的两条铁律（家族级）

- **`aa start -U <uri>` 带不动文件**：AMS 会做 URI 权限校验并在无授权时**静默剥离 want.uri** ⇒ 接收端 `want.uri` 为空。若这段判空 return 又不打日志（参见 `takeIncomingUri` 旧版），现象就是"导入跑了但没书"且日志干净 ⇒ **写这类分支必须打日志**。
- **`toISOString()` 家族禁令再确认**：导出的日期文本也一律本地时区（`exportDateText`），否则东八区 00–08 点会写成昨天。
- **③ 补充（2026-10-27）**：即使 `aa start -U` 指向**应用自己沙箱内**的文件（`file:///data/storage/el2/base/haps/entry/files/x.txt`），
  URI 仍会被 AMS 剥离 ⇒ **外部拉起导入这条路彻底死透**；唯一可行的是**应用内 picker**（用户手动选）。
- **④ 卡片参数取值的验证招（模拟器上可复现，不必真造书）**：
  `hdc shell "aa start -a EntryAbility -b <bundle> --ps a9 <bookId>"` 可模拟系统改键名后的**扁平形态**，
  应用日志应打出 `open book from card: <bookId>`；`--ps params '{"a9":"x"}'` 可模拟**嵌套 JSON 形态**。
  这招能在**没有任何书**的设备上验证 `pickBookId` 的两条分支是否都work（release 包本体实测过：成功）。
- **`toISOString()` 家族禁令再确认**：导出的日期文本也一律本地时区（`exportDateText`），否则东八区 00–08 点会写成昨天。
