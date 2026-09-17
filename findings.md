# Findings — Rock阅读（RockReader）

> 应用级技术台账。家族铁律与工程约定在 `..\planning\findings.md`（harmony-docs 仓库）。

## 产品边界（已定）
- **纯本地离线**：导入本地电子书阅读，零联网。
- **不做书源、不抓网、不申请 `INTERNET`**（家族铁律 3）。
- 对标安卓「阅读」的**阅读体验**（排版 / 翻页 / 书架 / 目录 / 净化），**不碰**它的书源生态（原项目因侵权已删库，见家族 findings §6）。
- 格式：首版 **TXT**，随后 **EPUB**；PDF 不做。

## 关键能力对照（ArkTS Kit，版本可用性待实测）
| 需求 | 候选 API | 备注 |
|---|---|---|
| 选书导入 | `@ohos.file.picker`（DocumentViewPicker） | 拿 URI，授权可能是临时的 |
| 文件读写 | `@ohos.file.fs` | 支持按 offset 随机读，适合大文件 |
| 沙箱路径 | `context.filesDir` / `cacheDir` | 书籍拷进 `filesDir/books/` |
| 解压 EPUB | `@ohos.zlib` | ⚠️ 需验证是否支持 zip 归档（可能只有 raw deflate） |
| 解析 OPF/NCX | `@ohos.xml`（XmlPullParser） | EPUB 目录与元数据 |
| 文本测量/分页 | `@ohos.measure`（measureText） | ⚠️ 需验证 API 版本与能力 |
| 编码解码 | `util.TextDecoder` | ⚠️ 需验证是否支持 GBK（中文 TXT 大头） |
| 目录/进度存储 | `@ohos.data.relationalStore` | 章节索引、阅读进度 |
| 轻量配置 | `@ohos.data.preferences` | 字号、主题等设置 |
| 并发 | `@ohos.taskpool` / `@ohos.worker` | 导入、解析、分页丢后台 |
| 自定义字体 | `@ohos.font`（registerFont） | 用户导入字体 |

## 设计要点（对齐三条铁律）
**快**
- 大 TXT 绝不整体读入内存；导入时扫描一次建"章节/页 → 字节偏移"索引落库，之后按 offset `fs.read` 随机访问。
- 只缓存当前 ±2 页；导入/解析/分页全走 `taskpool`，UI 线程只渲染。

**小**
- 渲染用 ArkUI `Text`/`Span` 自绘分页，**不用 Web 组件**。
- EPUB 若 `@ohos.zlib` 不支持 zip 归档，自己写最小 zip 中央目录解析 + raw inflate（约 200~400 行），优先于引三方库。
- 图标用矢量；so 只留 `arm64-v8a`；开混淆与资源压缩。HAP 预算 **≤5MB**。

**离线**
- `module.json5` 不声明 `ohos.permission.INTERNET`。
- 无账号、无云同步、无埋点统计、无广告、无后台常驻。
- 全部数据只在应用沙箱，支持导出与彻底删除。

## 三个待验证 spike（按风险排序）
> ⚠️ **本机没有鸿蒙开发环境，无法本地实测**。策略：先查官方文档，再**按最坏情况设计**，实测等首次 CI 构建 / 真机到位后回填。

1. **zip / EPUB 解压**：`@ohos.zlib` 能否直接处理 zip 容器
   - 最坏假设：不支持 zip 归档（只有 raw deflate）→ **自己写最小 zip 中央目录解析 + raw inflate**（约 200~400 行，符合"不引三方库"）
2. **GBK 解码**：`util.TextDecoder` 是否支持 GBK / GB18030
   - 最坏假设：不支持 → 首版先支持 UTF-8（含 BOM 识别）+ **编码手动选择**，GBK 映射后续自实现或按需加
3. **文本测量与分页**：`measureText` 可用性与精度
   - 最坏假设：能力有限 → 代码留兜底：测量失败退化为"按字符数估算分页"，保证能读，排版精度后调

> 这三个 spike 的结果直接写回本文件的「spike 结果」章节。

## spike 结果
| 项 | 结论 | 验证方式 | 日期 |
|---|---|---|---|
| zip 解压 | 待验证 | | |
| GBK 解码 | 待验证 | | |
| 文本测量分页 | 待验证 | | |

## Technical Decisions
| Decision | Rationale |
|----------|-----------|
| 首版只做 TXT | 链路短，最快跑通"导入→解析→分页→阅读→进度"全链路 |
| 自绘分页而非 Web 组件 | 小 + 快 |
| 字节偏移索引 + 随机读 | 大文件秒开、低内存 |

## Resources
- 华为开发者文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/
- 家族 findings（版本/环境/CI）：`..\planning\findings.md`
