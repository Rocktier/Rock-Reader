# 模拟器 / hdc / 造数 工具手册（Rock 家族）

> 从 MEMORY.md 拆出（2026-10-28，因主文件超注入上限）。
> 适用：RockReader + RockJournal 模拟器验证。

- ⭐ **模拟器可以纯命令行起停，不用开 DevEco**（2026-11-05 实测，all2md 用）：
  ```bash
  cd "/e/Program Files/Huawei/DevEco Studio/tools/emulator"
  ./Emulator.exe -start "Pura 90 Pro" -noWindow   # 无窗口后台跑，3 秒内 hdc 可见 127.0.0.1:5555
  ./Emulator.exe -stop  "Pura 90 Pro"
  ```
  实例名取自 `C:/Users/Dang/AppData/Local/Huawei/Emulator/deployed/lists.json`
  （现有：`Pura 90 Pro` 手机 / `MatePad Pro 13` 平板 / `Mate X7` 折叠 / `MateBook Pro` 2in1）。
  `-help` 还有 `-instance <name> -click/-slide/-fill/-screenshot/-power` 等交互子命令。
  ⇒ **以后要验界面不必等党哥开模拟器**，自己起、验完自己 `-stop`。

- ⭐ **沙箱写入（2026-11-07 实测更正，旧口径有害）**：`hdc file send` 写不进应用沙箱（SELinux 拒），
  但 **`hdc shell "cat /data/local/tmp/x.json > /data/app/el2/100/base/<bundle>/haps/entry/files/library/index.json"` 直接重定向可写**
  （all2md 实测 1908 / 27668 字节都成功，shell 对该目录有写权限）。
  ⚠️ `sqlite3 :memory: "select writefile(<私有路径>, readfile('/data/local/tmp/x.json'))"` **返回 0 并把目标截成 0 字节**
  （设备 sqlite3 读不到 `/data/local/tmp/`，readfile 返回 NULL）⇒ **别再用「只能靠 sqlite3 writefile」这条老结论**。
  **造数前必先 `hdc file recv` 备份索引**；出错 `aa force-stop` → `cat 备份 > 目标` → 重启核条目数。
- **模拟器**：dpr=3.5、视口≈359vp；**自动锁屏**（`keyEvent Power` + `swipe 628 2680 628 700`）；**约 30s 自动息屏** ⇒ `power-shell wakeup` 点亮、`power-shell timeout -o <ms>` 覆盖（**参数是 -o**）。**安全键盘是 secure 窗口：键盘弹出期间 screenCap 拍到应用区域纯黑，但 dumpLayout 仍读到完整 UI 树** ⇒ 极易误判成「渲染黑屏」⇒ **判据：关掉键盘再截图**。深浅色在系统设置「显示和亮度 → 显示模式」Radio（浅 ~(349,1634) / 深 ~(907,1634)）。
- hdc 不在 PATH：`/e/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`；uitest 语法 `uitest uiInput click <x> <y>`、**`uitest uiInput inputText <x> <y> <text>`（三参数版！）**，两参数版报「The number of parameters is incorrect」。`uitest dumpLayout` 输出路径每次随机 ⇒ 读 stdout 的 `DumpLayout saved to:/data/local/tmp/layout_xxx.json` 再 `hdc shell cat`（`file recv` 本地路径写相对名）。设备绝对路径需 `MSYS_NO_PATHCONV=1`。DEL = `keyEvent 7`；状态栏 y<136 吞点击；多步连点间隔 2~3s。shell 无 wm 命令 ⇒ 横屏断点抽纯函数 + 单测守。
- **uitest dumpLayout 会返回旧应用实例的过期布局** ⇒ **一切以 screenCap 截图为 ground truth**。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；chip 选中态以黑底像素扫描为准。
- **模拟器上 Rock私记 的主密码是 `123456`**（2026-10-27 设）。解锁：`aa start` → 点输入框 → `inputText <x> <y> 123456` → **Back 关键盘** → 点「用主密码解锁」。
- **模拟器造数（Reader）**：RdbStore 库在加密存储里，shell/sqlite3/`writefile()` 都碰不到 ⇒ **外部造库已封死**（老路「sqlite3 writefile 造库」已作废，别再试）。**唯一出路：应用内 picker** —— 书架右上「+」→ 系统 picker → 浏览 → 我的手机 → Download（模拟器里**本来就有历史 txt/epub/md**，如 `journal-progress-test.txt` / `rock-import-test.txt`）→ 选中即导入，books/chapters/progress 由应用自己写。
  ⚠️ **（2026-11-05 更正）`hdc file send` 能写 `/storage/media/100/local/files/Docs/Download`** ——
  旧记录"往 /storage/media 传报 permission denied"只对**沙箱目录**成立，公共下载目录可写，
  造数不再依赖拖拽。`file recv` 的**本地路径必须写相对名**（绝对路径会被拼成 `cwd+路径`），
  远端路径要 `MSYS_NO_PATHCONV=1`。`hdc install` 的本地路径同样要**先 cd 到产物目录再传相对名**。
  选择器固定路径：`浏览(775,290)`→`下载与接收(600,1977)`→`下载管理器(1014,690)`，
  文件栅格第 1/2/3 行中心 y=876/1382/1886，三列 x=240/630/1014（**最近页签恒空**）。
  通用坑：`sqlite3 <db> < file` **只执行第一行**（须 `cat file | sqlite3 <db>`）；`hdc file send` 远端路径会被 Windows 化 ⇒ 用 `base64 -w0` 经 shell 写；shell 与应用两套 mount 视图；写库前 `aa force-stop` + 删 `-wal/-shm/-dwr/-compare`；shell `mkdir` 被拒；`hdc list targets` 返回 `[Empty]` 时查端口 `127.0.0.1:5555` 再 `tconn`；**`hilog` 流式** ⇒ 必须 `| head -N`。
- **⚠️ dumpLayout 的两个坑（2026-10-28 夜踩到）**：① **会返回旧应用实例的过期布局** ⇒ 一切以 screenCap 截图为 ground truth；② **两次 dump 之间的状态可能真的变了**（中间若有别的点击）⇒ **别把「状态变了」误判成「UI 没刷新」**，先排除中间有没有别的操作再下结论（今天差点把对的代码改成错的）。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；chip 选中态以黑底像素扫描为准。
- **`aa start -U <uri>` 带不动文件**：AMS 校验 URI 权限并**静默剥离 want.uri** ⇒ 外部拉起导入这条路彻底死透。写这类分支**必须打日志**。
- **卡片参数取值验证招（不必真造书）**：`hdc shell "aa start -a EntryAbility -b <bundle> --ps a9 <bookId>"` 模拟系统改键名后的扁平形态。
- **存量已知问题（2026-10-25，未修待拍板）**：① 幽灵阅读会话——应用后台/被杀不关会话，下次打开补 end_at，污染统计；② 抽屉打开时系统返回直接退出阅读页。
- **构建命令（2026-11-03 复核，可用）**：
  `DEVECO_SDK_HOME="E:\Program Files\Huawei\DevEco Studio\sdk"`（**根目录，不是 sdk\default**）+
  `JAVA_HOME="...\jbr"` + DevEco 自带 node 跑 `hvigorw.js --mode module -p product=default -p buildMode=debug assembleHap --no-daemon`。
  ⚠️ 指到 `sdk\default` 会报 **00303312「找不到对应 SDK 版本」**（本机只装 API 26 一套 SDK，靠 compileSdkVersion 回落）。
  Start-Process 的参数含空格要自己加引号；四项 proxy 同存抛「字典中的关键字重复」⇒ 临时摘掉。
- **点击坐标必须取自 dumpLayout（2026-11-03）**：缩放截图上目测坐标会**偏 30px** ⇒ 点在按钮上方的空隙里
  ⇒ 被 Column 的空 onClick 吞掉，表现为「点了没反应」（日志里 ClickRecognizer 命中链只有 Column、没有 Text）。
  ⇒ `uitest dumpLayout` → 读节点 `bounds` → 点中心。
- **`hdc install -r` 保留数据**（换签名才报 9568332 ⇒ 先 `uninstall`）⇒ 改代码重装机不用重走导入/建库流程。
- **模拟器造数（picker）**：`浏览 → 下载与接收 → 下载管理器` 有 **12 个历史测试书**
  （`minibook.txt` 是中文测试书，含 前言/第1章 開篇/第2章 中段/第3章 結尾）；
  单击文件即导入并自动关闭 picker。⚠️ 搜索框 `uitest uiInput inputText` 不生效（secure 键盘）。
- **系统 picker 多选（all2md 11-07 实测，1256×2760，一次选 7 份）**：
  `选择文件(628,1139)` → `浏览(765,290)` → `下载与接收(628,1982)` → `下载管理器(1014,690)`
  → 右上九宫格 `[906,224][1039,357]`（中心 `972,290`）弹出菜单 → 第一项「多选」
  `[269,399][1025,567]`（中心 `647,483`）→ 每个文件右下角出现 `Checkbox`
  （4 行 × 3 列：x=`325/712/1099`，y=`789/1295/1800/2306`）→ 右上 ✓ `[1067,224][1200,357]` 完成。
  ⚠️ 单选时点文件即导入并自动关闭 picker；**多选必须走「完成」**。
  ⚠️ 菜单第二组「图标/列表」「名称/类型/时间/大小」是视图与排序，不是多选开关。
- 测试基线：Reader **297/297**；Journal **240/240**（2026-11-03）。


