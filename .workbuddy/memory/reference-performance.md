# 性能铁律 + 验证层工具坑（Rock 家族）

> 从 MEMORY.md 拆出（2026-11-03，因主文件超注入上限）。

## 一、AGC「点击操作完成快」检测项口径（官方文档 `performance-delay` 时延章，已查证）

- 全名「应用或元服务内**点击操作完成快**」；与「点击操作**响应**快」（≤100ms）
  是**两项不同检测**。
- 测**墙钟**：手指抬起（ACTION_UP）→ **页面转场 lane 结束**（ABILITY_OR_PAGE_SWITCH 等）。
  ⇒ **转场画不出来 = lane 结束被推后**；「点击后主线程被同步重活堵住」= 直接超标。
- 标准值：鸿蒙应用 ≤900ms（AGC 云测目标线 2400ms）。
- 党哥实测曾报 **2666ms**（日记）⇒ 触发整改（见下）。

## 二、六条家族铁律

1. **任何重活不能与「状态变更」挤在同一个 JS task** —— ArkUI 只在 task 结束后才出帧。
   症状：`LoadingProgress` 写好了却**永远画不出来**，用户看到白屏卡住。
2. **让帧必须用宏任务（`setTimeout(0)`），不能用微任务** —— 微任务在本轮 task 结束前就被清空，
   **不会让出到渲染管线**。这就是 Reader 的 `deferHeavyWork()`。
3. **点击后先给反馈，再干重活** —— 按钮换文案 + 禁用（busy 态）。界面一变，lane 就结束。
4. **后台 O(N) 活必须可取消** —— Reader 的 `surveyChars()` 原先没有取消机制，
   离开阅读页仍在跑、**下一轮开书还在抢 UI 线程**（「改一处慢两处」的典型）。
5. **同步 SDK 调用是秒级嫌疑** —— `cryptoFramework` 的 `generateSecretSync` 官方注释明写
   「block the main thread … advised to invoke synchronous API within a child thread」。
   同族同步 API 都要警惕：`layoutSync`、zip 同步解压、整章正则。
   ⇒ 对照表：私记 `Kdf.generateSecret(spec): Promise`（d.ts:6212）**与同步版共用同一 spec
   ⇒ 派生结果一致**（PBKDF2 100000 轮不变，仅从 Sync 改 await）。
6. **口径不一致 = 白干一次重活** —— Reader 的 `applyPrefsToLayout` 拿全局 `getLevels()` 算签名，
   而 UI 显示的是每书 `effectiveLevels(bookId)` ⇒「没改任何东西」也判定成「变了」⇒ 白白整章重排。

**安全参数的纪律**：PBKDF2 迭代次数是**安全参数，不是性能旋钮**。
性能整改动的是「在哪个线程跑」，不是「算多少次」；真要调低迭代数需安全侧签字 + 老库迁移方案。
⇒ 参数唯一真源放纯逻辑文件（`security/KdfParams.ets`）+ 单测锁死（漂移 = 老用户打不开日记）。

## 三、验证层的四条工具坑

1. **debug 包通过 ≠ release 包通过** —— release 有混淆，**必须单独实测**。
2. **「日志没出现」≠「代码没执行」** —— `hilog` buffer 会被系统日志冲掉
   （3 分钟系统日志就能冲没应用日志）。查应用日志必须**重启应用后立刻抓**，或先 `hilog -r`。
3. **`uitest dumpLayout` 不输出 Image 节点** ⇒ 判断「图标在不在」要**截图**（`uitest screenCap`）。
4. **自动化摸朗读入口要先开菜单**：topBar/bottomBar 都在 `if (this.showMenu)` 浮层里；
   直接点 topBar 坐标会落到正文 ⇒ **触发翻页**（症状极具误导性）。
