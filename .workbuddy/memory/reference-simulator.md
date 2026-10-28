# 模拟器 / hdc / 造数 工具手册（Rock 家族）

> 从 MEMORY.md 拆出（2026-10-28，因主文件超注入上限）。
> 适用：RockReader + RockJournal 模拟器验证。

- 沙箱写入：`hdc file send` 写不进应用沙箱（SELinux 拒）；**真正能写应用私有目录的是设备上 `sqlite3` 的 `writefile()`**（**只能写 `haps/entry/files/`**）。
- **模拟器**：dpr=3.5、视口≈359vp；**自动锁屏**（`keyEvent Power` + `swipe 628 2680 628 700`）；**约 30s 自动息屏** ⇒ `power-shell wakeup` 点亮、`power-shell timeout -o <ms>` 覆盖（**参数是 -o**）。**安全键盘是 secure 窗口：键盘弹出期间 screenCap 拍到应用区域纯黑，但 dumpLayout 仍读到完整 UI 树** ⇒ 极易误判成「渲染黑屏」⇒ **判据：关掉键盘再截图**。深浅色在系统设置「显示和亮度 → 显示模式」Radio（浅 ~(349,1634) / 深 ~(907,1634)）。
- hdc 不在 PATH：`/e/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe`；uitest 语法 `uitest uiInput click <x> <y>`、**`uitest uiInput inputText <x> <y> <text>`（三参数版！）**，两参数版报「The number of parameters is incorrect」。`uitest dumpLayout` 输出路径每次随机 ⇒ 读 stdout 的 `DumpLayout saved to:/data/local/tmp/layout_xxx.json` 再 `hdc shell cat`（`file recv` 本地路径写相对名）。设备绝对路径需 `MSYS_NO_PATHCONV=1`。DEL = `keyEvent 7`；状态栏 y<136 吞点击；多步连点间隔 2~3s。shell 无 wm 命令 ⇒ 横屏断点抽纯函数 + 单测守。
- **uitest dumpLayout 会返回旧应用实例的过期布局** ⇒ **一切以 screenCap 截图为 ground truth**。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；chip 选中态以黑底像素扫描为准。
- **模拟器上 Rock私记 的主密码是 `123456`**（2026-10-27 设）。解锁：`aa start` → 点输入框 → `inputText <x> <y> 123456` → **Back 关键盘** → 点「用主密码解锁」。
- **模拟器造数（Reader）**：RdbStore 库在加密存储里，shell/sqlite3/`writefile()` 都碰不到 ⇒ **外部造库已封死**（老路「sqlite3 writefile 造库」已作废，别再试）。**唯一出路：应用内 picker** —— 书架右上「+」→ 系统 picker → 浏览 → 我的手机 → Download（模拟器里**本来就有历史 txt/epub/md**，如 `journal-progress-test.txt` / `rock-import-test.txt`）→ 选中即导入，books/chapters/progress 由应用自己写。
  ⚠️ `hdc file send` 到 `/storage/media/...` 报 permission denied（shell 读都不行）；`hdc install` 的本地路径要**先 cd 到产物目录再传相对名**（传绝对路径会被拼成 `cwd + 绝对路径` ⇒ 找不到文件）。
  通用坑：`sqlite3 <db> < file` **只执行第一行**（须 `cat file | sqlite3 <db>`）；`hdc file send` 远端路径会被 Windows 化 ⇒ 用 `base64 -w0` 经 shell 写；shell 与应用两套 mount 视图；写库前 `aa force-stop` + 删 `-wal/-shm/-dwr/-compare`；shell `mkdir` 被拒；`hdc list targets` 返回 `[Empty]` 时查端口 `127.0.0.1:5555` 再 `tconn`；**`hilog` 流式** ⇒ 必须 `| head -N`。
- **⚠️ dumpLayout 的两个坑（2026-10-28 夜踩到）**：① **会返回旧应用实例的过期布局** ⇒ 一切以 screenCap 截图为 ground truth；② **两次 dump 之间的状态可能真的变了**（中间若有别的点击）⇒ **别把「状态变了」误判成「UI 没刷新」**，先排除中间有没有别的操作再下结论（今天差点把对的代码改成错的）。无 PIL 环境用纯 Python PNG 解码（zlib + 手动 unfilter）做像素分析；chip 选中态以黑底像素扫描为准。
- **`aa start -U <uri>` 带不动文件**：AMS 校验 URI 权限并**静默剥离 want.uri** ⇒ 外部拉起导入这条路彻底死透。写这类分支**必须打日志**。
- **卡片参数取值验证招（不必真造书）**：`hdc shell "aa start -a EntryAbility -b <bundle> --ps a9 <bookId>"` 模拟系统改键名后的扁平形态。
- **存量已知问题（2026-10-25，未修待拍板）**：① 幽灵阅读会话——应用后台/被杀不关会话，下次打开补 end_at，污染统计；② 抽屉打开时系统返回直接退出阅读页。
- 测试基线：Reader **202/202**；Journal **226/226**（1.0.6 新增 87 条：ASR 19 / 日记本 / 提示 / 模板）。

