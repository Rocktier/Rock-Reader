# Rock-Reader（Rock阅读）

鸿蒙（HarmonyOS）上的**纯本地、零联网**电子书阅读器。属于 Rocktier 「Rock」软件家族。

- 中文名：Rock阅读 ｜ 英文名：RockReader ｜ 包名规划：`com.rocktier.rockreader`
- 首版格式：**TXT**，跑通后再上 **EPUB**；不做 PDF。
- 目标系统：**HarmonyOS 6+（单框架）**，`compatibleSdkVersion = 20` / `targetSdkVersion = 24`。HarmonyOS 4 及更早已放弃（存量 <1%），单包发布。

## 设计铁律（家族统一）

1. **极致快** — 冷启动 ≤1s；主线程不干活；大文件走字节偏移索引 + 随机读，只缓存当前 ±2 页
2. **极致小** — HAP ≤5MB；不引多余三方库；渲染用 ArkUI `Text`/`Span` 自绘分页，不用 Web 组件
3. **极致离线** — **不申请 `ohos.permission.INTERNET`**；无账号、无云同步、无埋点、无广告、无后台常驻；数据全在沙箱

## 为什么不做书源

安卓开源阅读器「阅读」（Legado）的核心是自定义书源抓网页，本质是联网抓取，其原仓库已因侵权被删除。
本项目**只对标它的阅读体验**（排版、翻页、书架、目录、净化），**不碰书源生态**，绝不内置或分发任何第三方书源。

## 目录

| 文件 | 作用 |
|---|---|
| `task_plan.md` | 阶段计划、关键问题、决策表 |
| `findings.md` | 产品边界、API 对照、设计要点、spike 结果 |
| `progress.md` | 每次会话做了什么 |

当前状态：**立项中**，等环境与三个技术 spike（文本测量分页 / GBK 解码 / zip 解压）。

## 构建

所有构建在 GitHub Actions（Linux + `hvigorw`）完成，签名证书走 Secrets。
推送节奏：攒到一个完整的大版本才推，且打 tag → 发 Release。
