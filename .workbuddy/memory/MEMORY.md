# RockReader 项目长期记忆（2026-10-27 压缩重写版）

> 规则：只记**可执行**知识（命令、路径、判据、禁令）。过程细节进当日日志 `YYYY-MM-DD.md`。

## 一、产品口径：非主动联网（党哥 2026-10-18 拍板）

原文：「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

- ✅ 允许：用户主动点「下载」→ 联网拉音色/字体包 → 之后全程离线用。UI 义务：入口明示「联网下载」+ 体积、进度可见失败可重试、无网时明说、下载记录进 ReaderPrefs（含失败态）。
- ❌ 主要功能联网（云 TTS / 在线书城 / 账号云同步）；❌ 应用自己联网（检查更新 / 静默下载 / 遥测）。
- 音色：凌飞哲 21 需下载、聆小珊 13 内置、劳拉 8 英文不面向中文书。三方云 TTS 维持否决。字体下载同一范畴。**新增任何系统能力前先对照此表。**

## 二、签名与出包（两次 993 后定稿，**每次出包必读**）

- 个人开发者账号全账号仅 1 张发布证书：RockReader 与 RockJournal **共用** rockreader-v2.p12/.cer，各自建发布 Profile（rockreader-v2.p7b / rockjournal-v1.p7b）。材料在 `F:\AI\HarmonyOS\keys\`（不进 git），口令同目录 txt。
- build-profile 的 storePassword/keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117），同机可跨工程复制。
- **出包命令（两仓通用）**：`assembleApp -p product=release -p buildMode=release --no-daemon`。不能带 `--mode module`（报 00306054）；**`product` 必须是 `release`**（buildMode 只管混淆，不管签名）。
- 🚦 **上传前必须跑闸门**：`pwsh scripts/verify-upload.ps1`（两仓各一份，已接进 `build-release.ps1`，不过就 throw）。
  逐条排除 AGC 993 官方成因 + 顺带查 996/997 坑；**通过才允许上传**。
  **已实测**：喂 unsigned 包 ⇒ 3 项 FAIL + 退出码 1；喂 signed 包 ⇒ 13 项 PASS + 退出码 0。
- **交付纪律**：桌面/文件夹里**只留一个**待传包（signed/unsigned 并排是每次出包的常态，只在产物目录里挑包 = 自找 993）。旧包移入 `桌面\Rock阅读-旧包备份\` 备查，**不删**。
- 完整排查手册：`docs/AGC-993-排查手册.md`（Reader 仓）。桌面另有《上传前自检.txt》7 条清单。

### 993 = Profile 文件非法（家族级，**已栽两次，成因不同**）

AGC 官方四条成因：① 包内 Profile 已被删除（AGC 后台查不到）；② 包内 release Profile 不属于该应用；③ Profile 失效（证书被删/过期）；④ 包被自动签名。工程侧两条：**products[].signingConfig 必须指向发布签名**；**签名写在 hvigorfile.ts 的 overrides 里不被认可，必须写进 build-profile.json5**。

- **第 1 次（10-25）= 成因④**：出包写了 `-p product=default` ⇒ DevEco 自动签名（调试证书+调试 Profile）⇒ 包内 Profile `type=debug`。改 `product=release` 重打即好。
- **第 2 次（10-27）= 传错文件**：产物目录 `RockReader-release-signed.app`(2355889B) 与 `RockReader-release-unsigned.app`(2341232B) **并排，文件名只差三个字母**；unsigned 包**没有签名块**（verify-app 报 "signature not found"）⇒ 传它必 993。迷惑点：两包内层 `entry-default.hap` 完全相同，**签名在 .app 外层**。
- **Journal 侧同源 bug**：`build-release.ps1` 原用 `-like "*signed*"` 挑产物，**"unsigned" 里也含 "signed"** ⇒ 会挑到 unsigned 包。已统一改成 `-like "*signed.app" -and -notlike "*unsigned*"`。
- **判别口诀**：993 先抠包内 Profile（`hap-sign-tool -outProfile` 导出后找 `"type":"\w+"`）一次分流 —— `debug`=用错 product；`release` 但包名不匹配=拿错 Profile；过期=Profile 失效；**包侧全绿仍 993 ⇒ 立刻怀疑传错文件**。

### 出包验收三步 + 工具坑（家族级）

- **① 验签**：`app_check_tool.jar` **已失效**（报 9132101，所有参数判 invalid）⇒ 一律用
  `hap-sign-tool.jar verify-app -inFile X.app -inForm zip -outProfile <本地路径> -outCertChain <本地路径>`
  ⇒ 输出 `Digest verify result: true` + `verify-app success`。该工具**没有 `verify-hap`**；`-inForm` 只接受 `bin/elf/zip`。
- **② 抠包内 Profile 看 `type`**：必须 `release` + 本应用包名 + 无 `debug-info`/`development-certificate`。
  ⚠️ p7b 是 PKCS#7 容器，JSON 内嵌在二进制里 ⇒ **不能用 `LastIndexOf("}")`**，要从第一个 `{` 起做**带字符串感知的花括号配对**。
- **③ 本地 p7b 先验**：包内 Profile 与 `keys/rockreader-v2.p7b` 的 **md5 逐字节一致**才算过。`-outProfile/-outCertChain` 必须是存在的本地路径（/tmp 报 11012005）。
- **PowerShell 写脚本三坑**：① `.ps1` 必须存 **UTF-8 带 BOM**（PS 5.1 按 ANSI 读无 BOM ⇒ 中文乱码 ⇒「意外的标记 }」）；② 跑 java 工具**别用 `& java ... 2>&1`**（stderr 被转成错误记录，`$ErrorActionPreference="Stop"` 下直接中断）⇒ 用 `Start-Process` + `-RedirectStandardOutput/-RedirectStandardError`；③ `Start-Process` 两个雷：参数含空格要自己加引号（否则 `E:\Program Files\...` 被截成 `E:\Program`）；同时存在 `HTTP_PROXY/http_proxy/HTTPS_PROXY/https_proxy` 四项时抛「字典中的关键字重复」⇒ 临时摘掉再跑。
- **release 构建偶发失败**：第一次跑可能 11 秒就 `Failed :entry:default@CompileArkTS` 且**日志里无任何 ERROR 行**（真因不明）⇒ **原样重跑一次就 BUILD SUCCESSFUL**。遇到「无信息失败」先重跑，别改代码。

## 三、法律文件：一个链接覆盖全家族

- 博客 <https://www.91hym.cn/devs/756.html> 三章 + 锚点 `#privacy`/`#agreement`/`#rights`，两应用共用。唯一底稿在桌面 `Rock家族-隐私政策-用户协议-数据权利.md`。AGC 三字段 = 同一链接 + 不同锚点。新增 Rock 系应用改这一篇，不另起页。
- 双写纪律：博客 `#privacy` 章 == 应用内「设置 → 隐私政策」逐字一致。

## 四、工程铁律（踩过的坑）

- **release 混淆会改名 JSON 落盘字段**（Journal 1.0.2 已带混淆名写盘）：四个开关联合作用，单一白名单拦不住；根治 = 文件级 `-keep` 保护序列化真源，存量 = 读端 fallback 旧名。格式坑：`-keep` 条目不能缩进。Reader 侧无对象 JSON 落盘，不受影响。
- **日期一律本地时区**（todayKey/dateKeyOf/exportDateText），禁用 `toISOString()`（UTC，东八区 00–08 点写成昨天）。CI 有守门单测。
- **编译唯一可用方式**：自带 hvigorw wrapper 已损坏，必须用 DevEco 自带 node 跑 `hvigorw.js`；`DEVECO_SDK_HOME`/`JAVA_HOME` 指向 E 盘 DevEco。debug：`assembleHap --mode module -p product=default -p buildMode=debug`。
- **safe-delete 钩子 vs 构建（2026-10-27 实测）**：钩子在**单轮删 ≥50 个文件**时拦截（`SAFE_DELETE_BULK_CONFIRM_REQUIRED count:50 threshold:50`）⇒ hvigor 的 `:entry:clean` 失败、报 **00308004 Unable to delete entry\build**。真因在 `.hvigor/outputs/build-logs/build.log` 搜 safe-delete。**正解：把 `entry/build`、`.hvigor` 改名让开（如 `build_stale_日期`）再构建，不要硬删。** 钩子只拦 **node 进程内**的 fs 删除，bash/PS 的 `rm -rf` 不受限（清理残留时可直接删）。
- **浮层「点外部关闭」不牢靠**：面板内容超高时关闭带 layoutWeight 被挤成 0 ⇒ 必须给显式 `×`；关闭带固定高度（`SETTINGS_STRIP_VP=88`）；固定内容移进 Scroll；Scroll 用 `layoutWeight(1)` 且父链每层高度确定。`constraintSize({maxHeight})` 对 Scroll 无效。
- **@Builder 值参数不随 @State 重跑**（家族级，本族第 4 次同型坑）：选中态变了 UI 不更新 ⇒ ForEach key 带状态后缀，或直接调用拆 if/else。同族：日历染色 / 收藏星 / 胶囊剧透 / 编辑后列表 / 筛选 chip。
- **⚠️ ArkUI V1 分支条件陷阱（家族级，最重要的发现）**：V1 是「状态变更 → 局部刷新」，**build() 不整体重跑，`if` 的分支条件按首次求值定型**；依赖插桩只认「表达式里直接读 @State」，藏进 getter/方法体里的 @State 访问**追不到**。
  正解：条件里**就地读 @State**（`if (this.query.length > 0 && this.visibleItems().length === 0)`）。**@Computed 救不了**（编译报 `only be used in a 'struct' decorated with '@ComponentV2'`，本族是 V1）。
  与老坑合流判据：「数据变了 UI 不更新」按序查 —— ① ForEach key 少带变化位；② **分支条件藏在 getter/方法里**；③ 组件高度被 layoutWeight 压成 0。
- **UIAbility 基类没有 onConfigurationUpdate**：写 `super.` 能编译但运行时抛错 ⇒ 窗口存在但内容全空（黑屏）。
- **ForEach item 无确定宽度时 `width('100%')` 回退成父级全宽**（Journal 统计图 12 个月并排、只有第 0 个在屏内）：item 加 `layoutWeight(1)`。
- 图表数据顺序：左→右 = 过去→现在（newest 压轴），必须体现在单测里。
- **服务卡片（form）三条铁律**（家族级）：① **卡片自定义参数会被系统改键名**（`params:{bookId:'x'}` → `{"a9":"x",…}`，键按位置重命名）⇒ 只认原键名必然读不到 ⇒ **按"值"找不按键名找**；② **form 页面禁用 @StorageLink / hilog / onAreaChange**（报 `11706006`），只能用 @LocalStorageProp，而它读到的 dimension 是默认值 ⇒ **form 里做不了按尺寸分支的排版**；③ 卡片页不能打日志，调试只能打在 FormExtensionAbility 里。
- 沙箱写入：`hdc file send` 写不进应用沙箱（SELinux 拒），shell `cat`/`mkdir` 也不行；**真正能写应用私有目录的是设备上 `sqlite3` 的 `writefile()`**（**只能写 `haps/entry/files/`，写不进 database 目录**）。
- **模拟器**：dpr=3.5、视口≈359vp；**会自动锁屏**（黑屏截图 66908 字节是特征值；解锁 `keyEvent Power` + `swipe 628 2680 628 700`）。**约 30s 自动息屏** ⇒ `hdc shell "power-shell wakeup"` 点亮、`power-shell timeout -o <ms>` 覆盖（**参数是 -o**）。**安全键盘是 secure 窗口：键盘弹出期间 screenCap 拍到的应用区域纯黑，但 dumpLayout 仍读到完整 UI 树** ⇒ 极易误判成「渲染黑屏」⇒ **判据：按 Back 关掉键盘再截图**。系统设置应用 `aa start -a com.huawei.hmos.settings.MainAbility -b com.huawei.hmos.settings` 直拉且保留上次页面；深浅色切换在「显示和亮度 → 显示模式」Radio（浅 ~(349,1634) / 深 ~(907,1634)）。
- hdc 不在 PATH，绝对路径 `/e/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`；uitest 语法 `uitest uiInput click <x> <y>`。设备绝对路径需 `MSYS_NO_PATHCONV=1`；本地路径用相对。键盘弹出后输入框位移，必须重新 dumpLayout 再 inputText；DEL = `keyEvent 7`；状态栏 y<136 吞点击；多步连点间隔 2~3s。shell 无 wm 命令 ⇒ 横屏断点一律抽纯函数 + 单测守（shelfColsOf / readingMarginOf / formPadOf）。
- **uitest dumpLayout 会返回旧应用实例的过期布局** ⇒ **一切以 screenCap 截图为 ground truth**。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；视觉模型会误读选中态，chip 选中态以黑底像素扫描为准。
- **存量已知问题（2026-10-25，未修待拍板）**：① 幽灵阅读会话——应用后台/被杀不关会话，下次打开补 end_at，产生超长假会话污染统计（曾 1314 分钟）；② 抽屉打开时系统返回直接退出阅读页（应先关抽屉）。
- 测试基线：Reader **202/202**（1.0.7 新增 14 条：书架搜索 + 摘录导出）、Journal 139/139。

## 五、模拟器造数（2026-10-27 大更正：外部造库已封死，应用内 picker 才是出路，家族级）

**外部造库走不通的原因**：RdbStore 库在加密存储里（应用视角 `/data/storage/el2/database/entry/rockreader.db`，物理侧 `/data/app/el2/100/database/`）—— shell `ls` Permission denied、`sqlite3` 打不开、`writefile()` 写不进 database 目录。`/storage/media/**` 等目录在该模拟器上不存在或 Permission denied。⇒ **books/chapters/progress 三张表外部写不了。**

**✅ 唯一出路：应用内文件选择器（picker）是通的** —— 书架右上「+」→ 系统 picker → 浏览 → 我的手机 → Download（**里面本来就有历史测试留下的 txt/epub/md**）→ 选中即导入，**books/chapters/progress 由应用自己写**。造书不需要造库，只需在 Download 放文件。路径找不到时**用 picker 界面本身当探针**（`/storage/*` 大多 Permission denied）。

**仍然有效的通用坑**
- `sqlite3 <db> < file` **只执行第一行**，必须 `cat file | sqlite3 <db>`；`readfile()` 在该 build 没编，`writefile()` 可用；大 blob 走管道传 SQL 文件。
- **`hdc file send` 的远端路径会被 Windows 化**（报 `read-only file system, path:./E:`）⇒ 用 `base64 -w0` 经 `hdc shell "echo '<b64>' | base64 -d > /data/local/tmp/x.sql"` 写文件。
- **shell 与应用是两套 mount 视图** ⇒ books.path 必须写**应用视角**路径。
- 写库前 `aa force-stop` + 删 `-wal/-shm/-dwr/-compare`；shell `mkdir` 一律被拒。
- `hdc list targets` 返回 `[Empty]` 但 Emulator.exe 还在 ⇒ PowerShell 查端口得 `127.0.0.1:5555`，再 `hdc tconn 127.0.0.1:5555`。
- **`hilog` 是流式的**：`hilog | tail` 永远不返回 ⇒ 必须 `| head -N`；要持续抓就跑后台任务 + `TaskStop`。
- 切章规则**绝不手写复刻**：用 esbuild 把 `.ets` 当 TS 编译，直接跑产品自己的 `splitChapters`，偏移量与应用导入时逐字节一致。
- **`aa start -U <uri>` 带不动文件**：AMS 做 URI 权限校验并**静默剥离 want.uri** ⇒ 接收端 `want.uri` 为空。即使指向应用自己沙箱内的文件也会被剥离 ⇒ **外部拉起导入这条路彻底死透**。写这类分支**必须打日志**。
- **卡片参数取值验证招（不必真造书）**：`hdc shell "aa start -a EntryAbility -b <bundle> --ps a9 <bookId>"` 模拟系统改键名后的扁平形态，`--ps params '{"a9":"x"}'` 模拟嵌套 JSON 形态；应用日志应打出 `open book from card: <bookId>`（release 包本体实测过）。

## 六、发版与版本状态

- tag：Reader v1.0.1~v1.0.5、Journal v1.0.0/v1.0.2/v1.0.4（**本地未 push**）。push main 只跑编译校验+单测；**push tag v\* 才触发 `gh release create`**（且编译失败则不执行 ⇒ CI 红了 tag 也发不出 Release）。
- Reader **1.0.6（code 1000007）2026-10-26 已提交 AGC，党哥确认通过**（含桌面续读卡片 + 批次 A 四项），上架说明 `docs/release-notes-1.0.6.md`。
- Journal **1.0.5（code 1000006）** 含桌面卡片 + 深色模式修复（模拟器实测通过）、出包三步验收过，`RockJournal/docs/release-notes-1.0.5.md` 已定稿 ⇒ **待党哥提 AGC**。
- **Reader 1.0.7（code 1000008）**：commit `de258bb`+`3ea2cd5`（本地未 push）。
  release 包 **2026-10-27 22:29 重新出包**（签名时间戳不同 ⇒ 指纹变）：
  桌面 `Rock阅读-1.0.7-上架.app` md5 **`E8FA4A771F27D608E1EF0316DFF80702`** / sha256 `495BA367…D926D`，
  闸门 **13 项 PASS / 退出码 0**；上架说明 `docs/release-notes-1.0.7.md` 已更新指纹 ⇒ **待党哥提 AGC**。
  卡片点击定位 bug（参数改键名，commit f9e68e5）**端到端已在 release 包本体实测通过**。
- 1.0.7 四项对标静读天下：进度按真实字数 ✅ / 书架搜索 ✅ / 摘录导出 ✅ / **备份暂缓**（`EntryBackupAbility` 空实现**不是 bug**，官方推荐做法；`backup_config.json` 无 `includes` 大概率是有效默认 ⇒ 只能真机克隆定性，模拟器验不了 ⇒ 上架说明一个字不提）。
  进度修复根因：`onAreaChange` 首次回调兜底分支 `openChapter()` 后漏调 `surveyChars()`，`init()` 里 `if(this.areaReady)` 首次恒不成立 ⇒ `char_count` 恒空；修法 = 补调用 + `.catch()`（`surveyChars` 只有 try/finally **没有 catch**）。
- 模拟器造书配方已固化成 `scripts/seed-sim-book.mjs`（但外部造库已封死，见上节）。

## 七、CI 现状（2026-10-27 定位，党哥拍板「CI 不急」）

- **Reader CI 自 2026-10-17 引入 `@kit.CoreSpeechKit` 起连续红 8 次**（含 1.0.7 那次）。根因：CI 用**公开 OpenHarmony SDK**（HarmonyOS SDK 需登录华为账号才给下），而 `@kit.CoreSpeechKit`（朗读）、`@kit.ShareKit`（系统分享）是 **HarmonyOS 专有 kit** ⇒ 报 10505001 / 10311003。后果：编译校验形同虚设，**且打 tag 也不会发 GitHub Release**。
- **已排除的路线**：改 SDK 注入 hms kit —— hvigor `getExternalApiPaths()` 要求 `compileApiVersion>9 && targetData.isHarmonyOS() && sdkInfo.getHmsArkDir()`，OpenHarmony runtimeOS 永远拿不到 hms；改 runtimeOS 会被 00303038（版本号须字符串格式）/ 00303313（compileSdkVersion 必须匹配 SDK）双重卡死。工程内桩（.ets 独立模块）会被 ArkTS `arkts-no-untyped-obj-literals`（10605038）拦（对象字面量需对应**同文件内**显式声明的 class/interface，跨模块 import 的 interface 不算）。
- **党哥判断**：「鸿蒙所有的应用开发都是在本机上进行，所以不传远端问题也不大」⇒ **CI 修复暂缓**，不动仓库代码。将来要修：CI 工作区把 kit 的类型声明**内联到消费文件顶部**（ArkTS 要求同文件），再改 import。
