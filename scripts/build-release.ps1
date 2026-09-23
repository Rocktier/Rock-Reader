# 打上架用的 .app 包（AGC 提审格式）
#
# 原理：build-profile.json5 里 release signingConfig 的三个口令字段是**占位符**；
# 本脚本从 keys/rockreader-release-password.txt 解析真实值**临时注入**，
# 构建完成后用 git 还原 build-profile.json5 —— **密码永不落盘到任何被跟踪的文件**。
#
# 用法：pwsh scripts/build-release.ps1
# 产物：build/outputs/release/*.app（成功时打印路径与 SHA256）

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)   # 工程根（RockReader）
$keysDir = "f:\AI\HarmonyOS\keys"
$profilePath = Join-Path $root "build-profile.json5"

# ---- 1. 解析密码文件（字段化清单：别名 / 密钥库口令 / 别名口令）----
$map = @{}
Get-Content (Join-Path $keysDir "rockreader-release-password.txt") -Encoding UTF8 | ForEach-Object {
    if ($_ -match "^(.+?)[:：=](.*)$") { $map[$Matches[1].Trim()] = $Matches[2].Trim() }
}
$alias   = ($map.GetEnumerator() | Where-Object { $_.Key -match "alias|别名(?!口令)" } | Select-Object -First 1).Value
$storePw = ($map.GetEnumerator() | Where-Object { $_.Key -match "密钥库口令" } | Select-Object -First 1).Value
$keyPw   = ($map.GetEnumerator() | Where-Object { $_.Key -match "别名口令" } | Select-Object -First 1).Value
if (-not $alias -or -not $storePw -or -not $keyPw) {
    throw "密码文件缺少 别名/密钥库口令/别名口令 之一，无法构建"
}

# ---- 2. 环境（DevEco 自带工具链，与日常调试同一套）----
$ide = "E:\Program Files\Huawei\DevEco Studio"
$env:DEVECO_SDK_HOME = "$ide\sdk"
$env:JAVA_HOME = "$ide\jbr"
$env:PATH = "$ide\tools\node;$ide\tools\ohpm\bin;$ide\jbr\bin;$env:PATH"

# ---- 3. 注入真实密码（仅内存->临时写盘，构建后立即还原）----
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$orig = [IO.File]::ReadAllText($profilePath, [Text.Encoding]::UTF8)
$injected = $orig.Replace("__RELEASE_ALIAS__", $alias) `
                 .Replace("__RELEASE_STORE_PASSWORD__", $storePw) `
                 .Replace("__RELEASE_KEY_PASSWORD__", $keyPw)
if ($injected -eq $orig) { throw "占位符未找到 —— build-profile.json5 里没有 __RELEASE_*__ 占位符" }
[IO.File]::WriteAllText($profilePath, $injected, $utf8NoBom)
"==> 已注入签名材料（口令不入库）"

try {
    Push-Location $root
    # ---- 4. Build App（release 模式；APP = 多 HAP 聚合的上架格式）----
    node "$ide\tools\hvigor\bin\hvigorw.js" assembleApp `
        --mode project -p product=release -p buildMode=release --no-daemon
}
finally {
    Pop-Location
    git -C $root checkout -- build-profile.json5
    "==> build-profile.json5 已还原（占位符版）"
}

# ---- 5. 校验产物 ----
$app = Get-ChildItem (Join-Path $root "build") -Recurse -Filter *.app -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $app) { throw "构建命令结束但未找到 .app 产物 —— 视为失败" }
$sha = (Get-FileHash $app.FullName -Algorithm SHA256).Hash
"==> 产物：$($app.FullName)（$([math]::Round($app.Length/1KB)) KB）"
"==> SHA256：$sha"
