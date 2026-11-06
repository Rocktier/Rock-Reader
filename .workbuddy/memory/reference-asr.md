# ASR（Core Speech Kit）—— 判据与坑

**状态**：Journal 1.0.6 起接入，已上架。**边界**：只有中文普通话、只有离线模型（短 ≤60s / 长 ≤8h）；
**模拟器无离线引擎**（`canIUse` 为 false 或引擎起不来）⇒ **效果只能真机验**；仅中国区 Phone / Tablet。

## 一、两个必记的坑（②是真凶）

① `online` 名与值相反 —— .d.ts 原话「1: offline」⇒ **1 = 离线**。网上教程写 `online: 0` 是错的。

② ⭐⭐ `StartParams.extraParams` 的键是 **`recognitionMode`**（re-cogni-**tion**-Mode），
   **不是** `recognizeMode`。值为 **0** = 引擎自己开麦。
   **不传 / 键名错 ⇒ 默认 1 = 外部 `writeAudio` 喂流** ⇒ 我们从没喂过 ⇒
   **引擎起了、权限有了、界面显示"正在聆听"、但永远没声音没结果，且没有任何错误码**。
   我们写成 `recognizeMode` 整整带了 4 个版本（1.0.6～1.0.9），AGC 自检报「语音转文字不生效」才炸出来。
   ⚠️ 同一个 `createEngine` 里还有 **`recognizerMode`**（'short'/'long'，选模型），是**另一个字段**，别混。
   ⚠️ `vadEnd` 短语音默认 **800ms** ⇒ 长句说到换气处就被判"说完了"，后半句丢；设 **3000ms**。

现在键名收在 `AsrText.asrEngineExtra()` / `asrStartExtra()` 纯函数里，由单测盯拼写（字符串键只能这么守）。

## 二、其它固定套路

- `PermissionRequestResult` 没导出到 `abilityAccessCtrl` ⇒ **靠 `const res = await ...` 推断**类型。
- 监听器 5 方法全必填（先 `const self = this`、字面量落接口变量、方法语法）。
- `createEngine` 用回调版，成功时 **err 是 `undefined` 不是 `null`**。
- 结果累积 = `isFinal` 累加 + 非 final 取最后一条。
- 官方示例 `createEngine` 也带 `extraParams: { locate:'CN', recognizerMode:'short' }`，我们原来完全没给。

## 三、判据：云测「语音不生效」怎么读

**不能直接当结论** —— 自动化机器人不会对着麦克风说话，语音类功能在云测里被判"不生效"有结构性成分。
**但也不能反过来当噪音忽略**（坑② 就是这么漏掉的）。

分辨法：看 HiLog 有没有 `asr: onResult` ——
**有回调没文本** = 音频进来了但识别不出；**一个回调都没有** = 音频压根没进来（就是坑②的样子）。

## 四、「必须真机才能验」的通用打法

1. 纯逻辑抽出来（不引 `@kit.*`）用 node:test 测；
2. 用真 SDK 编译验签名；
3. **「用不了」当一等公民**（UNREADY 状态 + 按钮禁用但保留 + 如实文案）；
4. 按名反射的实现加 `-keep`（`RecognitionListener` 被 SDK 按名回调，改名 ⇒ 语音静默失效）；
5. 上架说明一字不提，直到真机验过。

⚠️ **过审 ≠ 能用**：审核员不对麦克风说话。Journal 1.0.10 带着 ASR 修复上架，真机验证仍是硬缺口。
