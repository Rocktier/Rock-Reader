# RockReader 1.0.7 更新说明（华为应用市场后台上传用）

> 版本：1.0.7（versionCode **1000008**）
> 状态：待党哥过目后粘贴到 AGC 后台上传页
> 对应代码区间：`f9e68e5..HEAD`（1.0.6 上架后的全部用户可见变更）
> 包：`build/outputs/release/RockReader-release-signed.app`（桌面已放 `Rock阅读-1.0.7-上架.app`）
> md5：`E8FA4A771F27D608E1EF0316DFF80702`（2026-10-27 22:29 重新出包，签名时间戳不同故指纹与上一版不同）
> sha256：`495BA3672B85301A65D6ABE35CA591013399410B5C8FCE6B2D416BB7707D926D`
>
> ⚠️ **上传时只传桌面这一个包**。`build\outputs\release\` 下还有一个
> `RockReader-release-unsigned.app`（**没有签名块**）—— 传它 AGC 必报 **993「Profile 文件非法」**。
> 上传前请照桌面 `Rock阅读-1.0.7-上传前自检.txt` 走一遍 7 条自查；
> 完整排查手册见 `docs/AGC-993-排查手册.md`。

---

## 一、AGC 上传页填什么

| 字段 | 填什么 |
|---|---|
| 版本号 | **1.0.7**（后台需**新建版本节点**，别往 1.0.6 里塞） |
| 新特性说明 | 粘贴下方「更新说明正文」 |
| 隐私政策 | `https://www.91hym.cn/devs/756.html#privacy` |
| 用户协议 | `https://www.91hym.cn/devs/756.html#agreement` |
| 数据权利 | `https://www.91hym.cn/devs/756.html#rights` |
| 权限说明 | **无变更，仍是零权限**（`module.json5` 无 `requestPermissions`） |
| 是否含服务卡片 | **是**（2×2 / 2×4 两种规格，与 1.0.6 相同） |

隐私政策**本次无需改动**：新增的搜索是纯本机字符串匹配，导出走的是系统分享面板（文件留在本机、
由用户自己决定发去哪），都没有新增数据外流路径。场景没变，链接不用动。

---

## 二、更新说明正文（直接粘贴这段）

```
【改进】阅读进度终于按真实字数算了
以前进度是按「读到第几章」折算的，章节长短不一样，进度就偏虚高。
现在改成按真正读过的字数算：短章少算一点、长章多算一点，读了多少就是多少。
长短差很多的书实测过，读到第 7 章时显示的数字和实际翻到的位置是对得上的。

【新增】书架搜索
书架顶部多了搜索框，输入书名或作者就能把对应的书筛出来。
搜索的时候「继续阅读」会暂时让位，清空搜索它就回来。

【新增】笔记可以导出
阅读页的标记面板底部多了一个「导出这本书的笔记」：
把这本书的摘录和书签整理成一份文本，从系统分享面板发出去——
存成文件、发给别的应用都行，你自己决定发去哪，全程离线。

【修复】桌面续读卡片点了回不到上次的位置
上一版桌面卡片点一下能打开应用，却回不到上次读到的那一页。
原因是系统会改写卡片自定义参数的键名，老的取法失效了。
现在改成不认键名、只认内容，已经实测：点一下就回到上次读到的那一页。

【隐私】仍然不联网、零权限
本次更新没有新增任何权限。搜索、进度换算、笔记导出全在本机完成，
导出的内容由你自己决定要不要发出去，阅读依然全程离线。
```

正文 5 条 / 约 430 字。

---

## 三、写这段时的五条取舍（给党哥自己看，不上传）

1. **进度口径放第一条**——这是 1.0.6 上架说明里明确「留到 1.0.7」的那一笔，
   也是这一版唯一「兑现旧承诺」的改动，用户最容易感知「数字终于准了」。
2. **不写具体百分比**——内部实测是 21 章长短不均的书、读到第 7 章时
   `progress = 0.88%`（旧口径约 29%）。这两个数字放上去只会被问「怎么只有 0.88%」，
   不如只说「和实际翻到的位置对得上」。
3. **卡片修复写成用户能复述的现象**——「点了回不到上次的位置」，
   而不是「修了个取参 bug」。并说明原因是系统改写键名，把「这是系统的行为、不是我们抽风」
   这层意思交给「系统会改写…老的取法失效了」来承担。
4. **导出不写成「导出到微信/邮件」**——它走的是系统分享面板，落到哪儿由用户和
   系统决定，夸大成「一键发到任何地方」会被当成新增联网能力。
5. **备份/恢复一个字没提**——`EntryBackupAbility` 是空实现，
   但官方文档明说空实现就是推荐做法，`backup_config.json` 不写 `includes` 大概率也是有效默认。
   **模拟器验不了备份恢复**（克隆只在真机之间发生），所以按家族纪律「没实测就不写」，
   免得提审时说不清。

---

## 四、技术备注（留存，不上传）

**1.0.7 的三项新能力（都已实测通过）**

- **进度按真实字数**（第 3 项）
  - 根因：`Reader.ets` 的 `onAreaChange` 首次回调兜底分支里 `openChapter()` 之后直接 return，
    漏调 `surveyChars()`；而 `init()` 里 `if (this.areaReady)` 首次进入恒不成立
    ⇒ `chapters.char_count` 恒空 ⇒ 进度退回「按章数」的虚高口径。
  - 修法：补调 `surveyChars()` 并加 `.catch()`（该函数只有 `try/finally`，没有 `catch`）。
  - 实测：模拟器 21 章不均长书，`char survey done: 21/21 chapters measured`，
    第 7 章处 `progress = 0.88%`（旧口径应为 28.6%）。
- **书架搜索**（第 2 项）
  - `ShelfRules.ets` 新增 `normalizeQuery / matchesQuery / filterByQuery`（书名 + 作者，大小写无关）。
  - 刻意**不做拼音**——撞「极致小」铁律，加拼音索引会让应用体积和复杂度上一个台阶。
  - UI：搜索框 + 搜索专属空态（「没搜到这本书」），「继续阅读」卡片随搜索联动。
- **摘录导出**（第 4 项）
  - `engine/marks/MarkExport.ets` 纯函数；`exportDateText()` 一律本地时区（禁 `toISOString()`）。
  - 走 `systemShare`（`ShareKit` + `utd.UniformDataType.TEXT`），零权限零联网。

**⚠️ ArkUI V1 分支条件陷阱（家族级，本次踩到）**
- 症状：搜索过滤掉了书，但「没搜到」的空态永远不出现。
- 根因：ArkUI V1 是「状态变更 → 局部刷新」，`build()` 不整体重跑，
  `if` 的分支条件按首次求值定型；依赖插桩只认「表达式里直接读 @State」，
  藏进 getter / 方法体里的 `@State` 访问**追不到**。
- 正解：条件里**就地读 @State**。`@Computed` 救不了（只支持 `@ComponentV2`，本项目是 V1）。
- 附带：根 Column 必须补 `.height('100%')`，否则两个空态的 `layoutWeight(1)` 被压成 0。

**卡片点击定位 bug 的修复与端到端验证（本次重点）**
- 根因：卡片里写 `params: { bookId: 'xxx' }`，系统拉起 ability 时传的是
  `{"a9":"xxx","params":"{\"a9\":\"xxx\"}",...}` —— **自定义键被重命名成 a0/a1/…（按位置排）**，
  `params['bookId']` 永远读不到 ⇒ 表现为「点了卡片应用起来了，但没跳到那本书」。
- 修法（`EntryAbility.pickBookId`）：解析系统塞回来的 `params` 字段（**只含卡片自定义参数**的
  JSON 字符串），取最后一个非空字符串值；再兜底扫 `a0..a31`。
  ⚠️ 将来卡片要加第二个自定义参数时，必须改成「按值域特征挑」而不是「取末位」。
- **端到端实测（release 包本体，2026-10-27）**：
  1. 模拟器装 `RockReader-release-signed.app`（签名与 debug 包不同，需先卸载）
  2. 应用内导入一本书 → 打开阅读（产生 progress 记录）
  3. 桌面编辑 → 卡片 → Rock阅读 → 添加到桌面（卡片显示 19% / rock-import-test）
  4. `aa force-stop` 后点桌面卡片 → **冷启动直接落到那本书的阅读页**，不是停在书架
  5. 日志铁证：
     ```
     form_mgr.cpp: [RouterEvent:603]call
     RockReader: onCreate theme=dark
     RockReader: open book from card: b_2cb28274-bfc8-420f-99c3-0c1118c53a77
     RockReader: char survey done: 3/3 chapters measured
     RockReader: card pushed, forms=1
     ```
  - 另在 debug 包上用 21 章长书复测过一次：点卡片 → 冷启动 → 第 6 章「长章」1/17 页，与手动打开位置一致。
- 附带发现：`pushCardUpdate` 在「本应用还没有任何卡片实例」时会报
  `{"code":16500100}` / `GetPublishedFormInfos fail 2293765`——**无害**（外层已 catch），
  只是日志噪音，知道是「没有卡片」不是「推送失败」即可。

**模拟器造数的新解法（本次打通，家族级）**
- 旧结论「导入通道全封」**只对 `aa start -U file://` 与隐式 viewData 成立**，
  **应用内文件选择器（picker）是通的**：
  picker → 浏览 → 我的手机 → Download → 里面已经有历史测试留下的 txt/epub/md 文件，
  选中即导入，**books/chapters/progress 三张表由应用自己写**（不必外部造库）。
- **数据库文件在加密存储里，shell / sqlite3 都碰不到**：
  应用视角 `/data/storage/el2/database/entry/rockreader.db`，
  物理侧对应 `/data/app/el2/100/database/`（该目录 shell `ls` 直接 Permission denied）。
  `sqlite3` 的 `writefile()` 只能写 `haps/entry/files/`，写不进 database 目录。
  ⇒ **外部造库这条路在当前模拟器镜像上已经彻底封死**，不要再花时间试。
- `sqlite3` 的 `writefile()` 仍可用于往应用 `files/` 目录投文件（权限比 `hdc file send` 高）。
- `hdc file send` 的**远端路径会被 Windows 化**（`/data/local/tmp/x` 被解析成本地盘符路径），
  稳妥做法：`base64` 后经 `hdc shell "echo '<b64>' | base64 -d > /data/local/tmp/x.sql"`。

**出包与验收（本轮全过）**
- 命令：`assembleApp -p product=release -p buildMode=release --no-daemon`
  （`product` 必须是 `release`，不能带 `--mode module`）。
  ⚠️ 首次执行可能**偶发** `Failed :entry:default@CompileArkTS`（11 秒就挂、日志无 ERROR 行），
  **原样重跑一次就 BUILD SUCCESSFUL**——遇到这种「无错误信息的失败」先重跑，别急着改代码。
- 验收三步：
  1. `hap-sign-tool.jar verify-app -inFile <.app> -inForm zip -outProfile ... -outCertChain ...`
     → `Digest verify result: true` / `verify-app success`。
     ⚠️ `app_check_tool.jar` 的 `verify-app` 已失效（报 9132101，所有参数被判 invalid）；
     `hap-sign-tool.jar` 的 `verify-hap` 命令不存在；`-inForm` 只接受 `bin/elf/zip`。
  2. 抠包内 Profile 看 `type`：`"type":"release"` + `"bundle-name":"com.rocktier.rockreader"`，
     **无** `debug-info` / `development-certificate`。
  3. 本地 `keys/rockreader-v2.p7b` 先验：包内 Profile 的 md5 与本地 **逐字节一致**
     （`045ffcc9283902df8ce78f887d27bbcf`）。
- 包内 `module.json` 复核：`versionCode 1000008` / `versionName 1.0.7` / 包名正确。
- 真机安装：`hdc uninstall` 旧 debug 包 → `hdc install RockReader-release-signed.app`
  → `install bundle successfully`（装得上就是签名 + Profile 有效），从零启动走隐私弹窗，无黑屏。

**测试基线**：单测 202/202（1.0.7 新增 14 条：书架搜索 10 + 摘录导出 4）。

**已知未完成（未提审、待后续版本）**
- 备份/恢复：`EntryBackupAbility` 空实现是官方推荐做法，未改；模拟器验不了，需要真机克隆测试。
- B2 智慧搜索：做不了（索引 API 不给三方 App），建议永久划掉。
- 商店截图建议补一张桌面带卡片的（现有 8 张全是应用内页，体现不了桌面续读卡片）。

**发版纪律**
- 1.0.6 = code 1000007 / name 1.0.6；**1.0.7 = code 1000008 / name 1.0.7**（已 bump 并复核包内 module.json）。
- `push` 会触发 CI 建 GitHub Release ＝ 发版动作，**须党哥拍板后再推**。
