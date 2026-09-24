# 打上架用的 .app 包（AGC 提审格式，含发布签名）
#
# 签名配置：build-profile.json5 的 signingConfigs.release
#   - 口令是 **DevEco 加密串**（由 DevEco「文件 > 项目结构 > 签名配置」写入/更新）
#   - ⚠️ 2026-09-24 实证：hvigor 不接受明文口令（无论长度/奇偶，均报 00303116/00303117），
#     明文注入路线已废弃 —— 改口令/换密钥库后必须在 DevEco GUI 里重新应用一次签名配置
#   - 材料在 f:\AI\HarmonyOS\keys\（rockreader-v2.p12/.cer/.p7b，不进任何 git）
#
# 用法：pwsh scripts/build-release.ps1
# 产物：build/outputs/release/RockReader-release-signed.app

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ide = "E:\Program Files\Huawei\DevEco Studio"

$env:DEVECO_SDK_HOME = "$ide\sdk"
$env:JAVA_HOME = "$ide\jbr"
$env:PATH = "$ide\tools\node;$ide\tools\ohpm\bin;$ide\jbr\bin;$env:PATH"

Push-Location $root
node "$ide\tools\hvigor\bin\hvigorw.js" assembleApp --mode project -p product=release -p buildMode=release --no-daemon
Pop-Location

$app = Get-ChildItem (Join-Path $root "build\outputs\release") -Filter *signed.app |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $app) { throw "构建结束但未找到 signed .app 产物 —— 视为失败" }
"==> 产物：$($app.FullName)（$([math]::Round($app.Length/1KB)) KB）"
"==> SHA256：$((Get-FileHash $app.FullName -Algorithm SHA256).Hash)"
