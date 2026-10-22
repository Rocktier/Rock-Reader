# RockReader 项目长期记忆

## 产品口径：非主动联网（党哥 2026-10-18 拍板）

**原文口径**：「用户可以选择自己联网下载某些字体或音色，但是我们自己不会主动联网，主要的功能也不联网。」

边界（后续所有功能的设计前提）：

| 行为 | 判定 |
|---|---|
| 用户主动点「下载」→ 联网拉音色包/字体包 → 之后全程离线使用 | ✅ 允许 |
| 主要功能联网（云 TTS 每次朗读联网合成、在线书城、账号云同步） | ❌ 不允许 |
| 应用自己发起联网（启动检查更新、静默下载、遥测上报） | ❌ 不允许 |

UI 义务（凡是联网下载功能都要做到）：
1. 入口明示「联网下载」+ 资源大小，不拿「下载」二字含糊过去；
2. 下载进度可见、失败可重试、失败原因说人话；
3. 无网络时明确提示「此功能需要联网」，禁止静默失败；
4. 下载记录进 ReaderPrefs（含失败态），恢复网络后不重复下载已有资源。

当前适用范围：
- **音色**：凌飞哲（person 21）downloadVoice 归入允许范畴，需做下载 UI；
  聆小珊（13）内置无需下载；劳拉（8）英文音色不面向中文书。
- **字体**：设置面板「字体下载」入口同一范畴，同样要明示联网。
- **三方云 TTS**（Azure/讯飞等）：维持否决——那是主要功能联网，性质不同。

## 华为上架签名（两应用共用，2026-10-20 坐实）

- **个人开发者账号全账号只有 1 张发布证书** → 第二个应用（Rock私记）不另申请证书，
  复用 rockreader-v2 的 p12/cer，只为该包名单建发布 Profile（p7b）。
- 材料落位 `F:\AI\HarmonyOS\keys\`：rockreader-v2.p12/.cer（共用）、
  rockjournal-v1.p7b（Rock私记专属）；p12 口令在同目录 rockreader-v2-password.txt。
- build-profile 的 storePassword/keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117）；
  同机同钥匙的加密串可跨工程复制。
- 验签：`hap-sign-tool.jar verify-app -inFile X.app -inForm zip`（.app 内嵌的是 unsigned hap，
  签名在 .app 层，属正常）。

## 法律文件口径：一个链接覆盖全家族（2026-10-20 定）

- 博客 <https://www.91hym.cn/devs/756.html> 已扩为 **《Rock 家族 隐私政策、用户协议与
  数据权利》**，一篇三章 + 三个锚点 `#privacy` / `#agreement` / `#rights`，
  **Rock阅读 与 Rock私记 共用这一个链接**（原文那句「适用范围：Rock 家族全部应用」
  就是为此预留的）。今后新增 Rock 系应用，改这一篇即可，不要另起新页。
- AGC 三字段 = 同一链接 + 不同锚点。
- 唯一底稿在桌面 `Rock家族-隐私政策-用户协议-数据权利.md`；
  **同一份法律文件只留一个底稿**，多一份就多一处「政策与应用内不一致」的拒审风险。
- 双写纪律：博客 `#privacy` 章 == 各应用内「设置 → 隐私政策」全文，逐字一致。
- **Rock阅读 1.0.3 已于 2026-10-20 审核上架**（链接填的就是 756.html#privacy）。
  RockReader 应用内 Privacy.ets 同日同步为家族版（commit 41bb5cd，版本号未动），
  等下一个版本（1.0.4+）带出；在那之前应用内与网页有短暂不一致，但已上架应用
  一般不复查，风险可接受。

## 其他长期事实

- 官方 Core Speech Kit textToSpeech 音色库总共 **3 个**（SDK 声明 + 官网双源坐实）：
  聆小珊 13（内置）、凌飞哲 21（需下载）、劳拉 8（英文，需下载）。
- 官方无公开试听网页；RockReader 自身即试听器（同引擎最真实）。
- 模拟器实测有 TTS 能力（findings §15 坑 2 作废，§16 留证）；
  凌飞哲在模拟器缺音色包（码 1002300005），真机才能验证下载链路。

## 命令行编译唯一可用方式（2026-10-22 实证）

项目自带 `hvigorw` wrapper **已损坏**（反复 Hvigor cleaning/installing 后静默退出）。
唯一可用命令（bash）：

```bash
export DEVECO_SDK_HOME="E:/Program Files/Huawei/DevEco Studio/sdk"
export JAVA_HOME="E:/Program Files/Huawei/DevEco Studio/jbr"
"/e/Program Files/Huawei/DevEco Studio/tools/node/node.exe" \
  "/e/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js" \
  assembleHap --mode module -p product=default -p buildMode=debug --no-daemon
```

（DevEco 装在 E 盘；NODE_HOME 指向 DevEco node 才有效，/c/Program Files 下没有 Huawei。）

## 世界百佳评审整改（2026-10-22 完成，commit 见 git log "review:"）

- 22 项 = 5×P0 + 9×P1 + 8×P2：代码层全部落地（真做或决策记录）。
- 决策记录收口的：索引增量写（>5MB/p95>50ms 触发）、字体下载联网（四步触发，
  牵动 INTERNET 权限+隐私政策+AGC 标签+商店文案，必须随版本走）、导入 taskpool、
  书架排序切换、导入文案诚实化（NOT_SUPPORTED 撤下 MOBI/AZW3 + PARSE_CRASHED/MOBI_TOO_NEW）。
- **模拟器统一验证清单（未做）**：动效（pageTransition/脉冲/浮现）、三件套
  （书签/摘录/搜索）、语速生效、朗读定时停止、自定义心情、备份提醒三态、
  图片删除、平板断点（书架 3/4/6 列 + 版心封顶）。
- **混淆白名单遗留**：RockJournal 已加 -keep-property-whitelist（26 字段）；
  ⚠️ 待模拟器拉真实 index.json 验证已上架 1.0.2 是否已带混淆名写盘——
  若是，下版必须带「旧混淆名→明文名」迁移映射，否则升级丢日记元数据。
  RockReader 无对象 JSON 落盘，无需白名单（例外预警写在 obfuscation-rules.txt）。
- tag：RockReader v1.0.1/v1.0.2/v1.0.3 早已存在（指向正确）；RockJournal 本次补
  v1.0.0/v1.0.2（1.0.1 跳号既成事实不伪造）。**均为本地 tag 未 push**——
  push tag 会触发 CI 建 GitHub Release，发版时机由党哥下令。
- 测试基线：RockReader 177/177、RockJournal 119/119（npm test，esbuild 管道）。
