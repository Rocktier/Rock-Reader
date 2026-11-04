# all2md PDF 读入器（2026-11-04 落地，commit 9279309）

> 主文件只留一句指针，细节全在这里。改动 PDF 相关代码前必读。

## 一、最大前提：模拟器没有 PDFKit

```ts
canIUse('SystemCapability.OfficeService.PDFService.Core')   // 模拟器 = false
pdfService  // 运行时 undefined ⇒ new pdfService.PdfDocument() 直接崩
```

**PDF 端到端只能在真机验。** 三层兜底（全部已实现，改动时别拆）：
1. `platform/PdfExtract.ets` 先 `canIUse` 探测 — 只探 syscap 字符串，**不许碰命名空间**
   （`pdfService !== undefined` 会被 ArkTS `arkts-no-ns-as-obj` 编译期拦掉）；
2. `new pdfService.PdfDocument()` 整体包 try/catch（探测过了也可能构造失败）；
3. 「用不了」当一等公民：如实文案「这台设备没有 PDF 解析能力，模拟器通常如此，换真机试试」。

## 二、API 形状（本地 SDK `@hms.officeservice.pdfservice.d.ts` 确认）

- `import { pdfService } from '@kit.PDFKit'`
- `new pdfService.PdfDocument()`；`loadDocument(path, password?, onProgress?): ParseResult`；
  `getPageCount(): number`；`getPage(index): PdfPage`；`page.release()`；`document.releaseDocument()`
- `ParseResult`：`PARSE_SUCCESS=0 / PARSE_ERROR_FILE=1 / PARSE_ERROR_FORMAT=2 / PARSE_ERROR_PASSWORD=3`
- 文本抽取两条路：
  - `page.getTextContent()` — **`@since 6.1.0(23)`**，只给字符串，分栏/页眉/表格列**全糊在一起**
  - `page.getGraphicsObjects()` — `@since 5.0.0(12)`，返回 `TextObject`：
    `text` / `x` / `y`（pt，**原点左下**）/ `textSize` / `charRects` / `charUnicodes`，
    过滤 `GraphicsObjectType.OBJECT_TEXT=1` ⇒ **版式恢复的唯一数据源**
- 错误码：801 能力不支持 / 1800001 文件错 / 1810003 密码错

## 三、⭐ 验证路径：「验不了机器，就验数据」

桌面真实商业 PDF（80 页）⇒ 电脑上 `pypdf` 抽 `(text, x, y, size)` 成 JSON ⇒
**直接喂 `readPdf()`**（内核零 `@kit.*`，node 里能跑）。

这是三个真 bug 的**唯一**发现途径，纯造数据绝对造不出来：
1. 一份表转出 **109 个 `###`**（9pt 占 24.8% 的正文被当标题）
2. **假表格** `|  |  | 1. 电 | 容感 | 应 脚感冲水2.一 |`
3. **间距被抹平**（分栏/表格列糊成一串）

## 四、三条被真实数据逼出来的判据（改之前先看测试）

| 判据 | 规则 | 由来 |
|---|---|---|
| **标题两档** | `≥ 正文×1.5` 直接算标题；`1.15 ~ 1.5` 倍必须**罕见**（占比 ≤ 8%）才算 | 真实样本字号 `7.5pt 74.8% / 9pt 24.8% / 12pt 0.5%`。先试「少数派 ≤ 25%」仍不够（16pt 标题被拒）⇒ 只能两档 |
| **页眉四条件** | 页上下 **8%** 带内 + 字号 ≤ 正文×1.1 + 跨页重复 + 出现页数 ≥ 半数 | 封面 22pt 大标题压在页面顶部被当页眉剔掉（4 条单测同红）。带宽原为 10%，缩到 8% 并加 `RUNNING_MAX_RATIO=1.1` |
| **表格四门槛** | 列数 ≥3、连续 ≥3 行、≥80% 行每列都占到、归类失败 ≤5% | 否则出假表格。不合就当段落 |

**间距即版面语义**：`gap > size * 0.9` 就补空格，**与语言无关**（中文之间也补 —— 那是分栏不是连字）。
`bodySizeOf` 按**字符数加权**算正文基准字号（不是按行数，也不是取众数）。

常量：`RUNNING_BAND=0.08` `RUNNING_MAX_RATIO=1.1` `HEADING_MIN_RATIO=1.15` `MAX_HEADING_LEN=40`
`MIN_TABLE_ROWS=3` `MIN_TABLE_COLS=3` `MAX_TABLE_COLS=12` `TABLE_REJECT_RATIO=0.05` `TABLE_FULL_ROW_RATIO=0.8`

## 五、结构

| 层 | 文件 | 职责 |
|---|---|---|
| 内核 | `core/read/pdf/PdfLayout.ets`（~1050 行）| 行聚类 / 字号判标题 / 行距与缩进切段 / 页眉剔除 / 表格识别，**零 `@kit.*`** |
| 内核 | `core/read/pdf/PdfTextReader.ets` | `readPdf(pages, sourceName)`；三通道 `LAYOUT / PLAIN / NONE` |
| 平台 | `platform/PdfExtract.ets` | PDFKit 读真实文件 → `PdfPageText[]` |
| 分派 | `ConvertService.convertPdf()` + `ConvertRunner` | 真进度「正在读第 N / M 页」|

- `structureInferred` **恒 true**，一路传到 `Archive` 索引 → `Reader` 元信息行 → `Report` 的 `InferredNote()`。
- 扫描件（`getGraphicsObjects` 无文本）**不当空文档**：如实说「可能是扫描件，要 OCR」。
- `MAX_PAGES = 500`，截断时拼「这份 PDF 有 N 页，只转了前 500 页」进 message。
- 页脚页码、纯文本兜底通道（`page.getTextContent()`）都在；兜底时 `hasLayout=false`。

## 六、仍然欠的

- ⚠️ **真机端到端未验**（模拟器无能力）—— 这是唯一硬缺口。
- ⚠️ 系统 picker 选真实文件、另存为保存面板，均未验。
- 真实 PDF 样本**不入库不进包**（客户商业文件）⇒ `.gitignore` 已钉 `test/samples/pdf-preview.pdf`
  与 `entry/src/main/resources/rawfile/sample.pdf`。
- 未做：描边/旋转文本、竖排、表单域、图片内文字（OCR）。
