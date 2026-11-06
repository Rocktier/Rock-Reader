# 签名 / 出包 / 上传验收（Rock 家族，每次出包必读）

> 从 MEMORY.md 拆出（2026-11-03，因主文件超注入上限）。

## 一、证书与工程配置

- 个人开发者账号全账号仅 **1 张发布证书**：两应用**共用** `rockreader-v2.p12/.cer`，
  各自建发布 Profile（`rockreader-v2.p7b` / `rockjournal-v1.p7b`）。材料在 `F:\AI\HarmonyOS\keys\`（不进 git）。
- build-profile 的 storePassword / keyPassword **必须是 DevEco 加密串**（明文报 00303116/00303117）。
- **出包命令**：`assembleApp -p product=release -p buildMode=release --no-daemon`。
  - 不能带 `--mode module`（报 00306054）
  - **`product` 必须是 `release`**（buildMode 只管混淆，不管签名）

## 二、🚦 上传前闸门（强制）

- `pwsh scripts/verify-upload.ps1`（两仓各一份，已接进 `build-release.ps1`，不过就 throw）。
- 实测：unsigned 包 ⇒ FAIL + 退出码 1；signed 包 ⇒ 全 PASS + 退出码 0。
- **交付纪律**：桌面/文件夹**只留一个**待传包（signed/unsigned 并排是常态，
  只在产物目录里挑包 = 自找 993）。旧包移入备份文件夹，不删。

## 三、上传纪律（第 0 步，只能靠人）

先确认 **AGC 后台当前应用 = 该应用**（2026-11-06 20:35 党哥从 AGC 应用列表复制的原始口径）：

| 应用 | APP ID | 包名 | 在架 |
|---|---|---|---|
| Rock阅读 | `6917617208943200991` | `com.rocktier.rockreader` | 1.0.12 |
| Rock私记 | `6917617645309338498` | `com.rocktier.rockjournal` | 1.0.11 |
| （all2md） | `6917620824955651111` | `rock.all.2.md` | 未上架 |

- **看 APP ID 比看名称可靠**：两个应用名字只差两个字、后台并排，历史上就传错过栏目（见第四节栽 2）。
- 上传页要核对的是「应用名 + 包名」都对应；上传后若报 993，先回来查这一行对不对，别再翻包。

**包侧全绿也发现不了传错栏目。** 排查手册：`docs/AGC-993-排查手册.md`（两仓各一份）。

## 四、993 = Profile 文件非法（家族级，已栽两次，成因不同）

官方四成因：① Profile 被删；② Profile 不属于该应用；③ Profile 失效；④ 被自动签名。
工程侧两条：
- `products[].signingConfig` 必须指向发布签名；
- **签名写在 hvigorfile.ts 的 overrides 里不被认可，必须写进 build-profile.json5**。

- **栽 1（10-25）= ④**：出包写了 `-p product=default` ⇒ 自动签名 ⇒ Profile `type=debug`。
- **栽 2（10-27）= ②「传到错误的应用栏目下」（真凶）**：把 Rock阅读 的包传到 AGC「Rock私记」栏目下
  ⇒ bundle-name 对不上 ⇒ 993。
  ⚠️ 期间曾误判成「传了 unsigned 包」（诱因是产物目录 signed/unsigned 并排、文件名只差三个字母）。
  **教训：结构上像的诱因 ≠ 真凶**。
- ⭐ **闸门的能力边界（家族铁律）**：闸门只能验**包**，验不了「传到哪个应用下」
  ⇒ **包侧全绿而仍 993 ⇒ 问题在包之外**，先查上传目标应用。
- **Journal 侧同源 bug（已修）**：`build-release.ps1` 曾用 `-like "*signed*"` 挑产物，
  **"unsigned" 里也含 "signed"** ⇒ 会挑到 unsigned 包。已改
  `-like "*signed.app" -and -notlike "*unsigned*"`。

**判别口诀**：抠包内 Profile（`hap-sign-tool -outProfile` 找 `"type":"\w+"`）分流 ——
`debug` = 用错 product；`release` 但包名不匹配 = 拿错 Profile；过期 = Profile 失效；
**包侧全绿仍 993 ⇒ 先查上传目标应用**。

## 五、出包验收三步

1. **验签**：`app_check_tool.jar` **已失效**（报 9132101）⇒ 用
   `hap-sign-tool.jar verify-app -inFile X.app -inForm zip -outProfile <本地路径> -outCertChain <本地路径>`
   ⇒ `Digest verify result: true` + `verify-app success`。
   无 `verify-hap`；`-inForm` 只接受 `bin/elf/zip`。
2. **抠包内 Profile 看 `type`**：必须 `release` + 本应用包名 + 无 `debug-info`/`development-certificate`。
   ⚠️ p7b 是 PKCS#7 容器，JSON 内嵌二进制里 ⇒ **不能用 `LastIndexOf("}")`**，
   要从第一个 `{` 起做**带字符串感知的花括号配对**。
3. **本地 p7b 先验**：包内 Profile 与 `keys/*.p7b` 的 **md5 逐字节一致**。
   `-outProfile/-outCertChain` 必须是**存在的本地路径**（/tmp 报 11012005）。

## 六、PowerShell / 构建工具坑

1. `.ps1` 必须 **UTF-8 带 BOM**（PS 5.1 按 ANSI 读无 BOM ⇒ 中文乱码 ⇒「意外的标记 }」）。
2. 跑 java 工具**别用 `& java ... 2>&1`**（stderr 被转成错误记录，`Stop` 下直接中断）
   ⇒ 用 `Start-Process` + `-RedirectStandardOutput/-RedirectStandardError`。
3. `Start-Process`：参数含空格自己加引号；四项 proxy 同存抛「字典中的关键字重复」⇒ 临时摘掉。
4. ⚠️ **Git Bash 里 `pwsh xxx.ps1` 被安全策略拦** ⇒ 一律用 PowerShell 工具调用。
5. ⚠️ **hvigor 把 WARN 也写到 stderr** ⇒ `$ErrorActionPreference='Stop'` + `2>&1`
   ⇒ 原生命令 stderr 被转成 ErrorRecord ⇒ **当场中断**，表现为「6 秒就 Failed :entry:default@CompileArkTS」，
   看着像编译失败，**其实构建根本没跑完、产物目录还是旧的**。
   ⇒ **修法**：经 `cmd /c` 重定向 + 只看 `$LASTEXITCODE` 判成败（两仓已同步）。
   ⇒ **判据**：出包「几秒就失败且日志无 ERROR 行」时，先看**产物目录时间戳** ——
   没更新就说明构建压根没跑完，别急着重跑。
6. **release 构建偶发失败**：第一次跑可能 11 秒就 `Failed :entry:default@CompileArkTS` 且**日志无任何 ERROR 行**
   （真因不明）⇒ **原样重跑一次就 BUILD SUCCESSFUL**。遇「无信息失败」先重跑，别改代码。
7. **编译唯一可用方式**：自带 hvigorw wrapper 已损坏，必须用 DevEco 自带 node 跑 `hvigorw.js`；
   `DEVECO_SDK_HOME`/`JAVA_HOME` 指向 E 盘 DevEco。
   debug：`assembleHap --mode module -p product=default -p buildMode=debug`。

## 七、⭐ md5 不能当「包有没有变」的判据

`.app` 的 md5 **每次打包都变**（签名块含时间戳）⇒ md5 只适合当**指纹记录**。
要判断两包是否等价 ⇒ **解包逐文件比**：
`unzip X.app` → `entry-default.hap` / `pac.json` / `pack.info` → 再解 hap 比
`module.json` / `ets/modules.abc` / `resources/**` 的 md5。
2026-10-28 实测两包 hap 内内容逐字节相同，差异只在签名块。
（顺带证实：`module.json5` 的注释不进 hap ⇒ 改注释不必重新出包。）

## 构建环境（2026-11 定点）

- `DEVECO_SDK_HOME` 指到 `...\DevEco Studio\sdk`（**根**；指 `sdk\default` 报 00303312）。
- 仓内自带 hvigorw wrapper 已坏 ⇒ 用 DevEco 自带 node 跑 `hvigorw.js`；
  Git Bash 里必须 `cmd //c "scripts\build.cmd ..."`（写 `scripts/build.cmd` 报「'scripts' 不是内部或外部命令」）。
- safe-delete 拦批量删除时，**只把 `entry/build/.../cache/default/default@CompileArkTS` 改名 `.old-1`**
  就够（33 秒构建成功，只丢 ArkTS 一层增量缓存），别一上来动整个 `entry/build`。
