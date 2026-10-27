<#
.SYNOPSIS
    上架包上传 AGC 前的**强制闸门**。任何一项不过，直接非零退出，不产出可上传的包。

.DESCRIPTION
    为什么需要它（家族级教训，两次 993）：
      · 2026-10-25 第一次 993：出包命令写了 `-p product=default` ⇒ 用的是 DevEco 自动签名
        （调试证书 + 调试 Profile）⇒ AGC 拒收（Profile 文件非法）。
      · 2026-10-27 第二次 993：产物目录里 **signed 与 unsigned 两个 .app 并排**，
        文件名只差三个字母 ⇒ 传错文件（unsigned 包根本没有签名块）。
    所以光"验签通过"是不够的 —— 必须逐项把 993 的官方成因逐个排除掉。

    本脚本按 AGC 官方「993 Profile 文件非法」四条成因 + 工程侧成因逐条自查：
      ① 包内 Profile 是发布 Profile（type=release），不是调试/自动签名
      ② 包内 Profile 的 bundle-name == 本应用包名
      ③ 包内 Profile 的证书在有效期内
      ④ 包内 Profile 与本地发布材料逐字节一致（防止拿错 Profile）
      ⑤ 包**有**签名块（排除 unsigned 包）
      ⑥ 包内 pack.info 的 bundleName / versionCode / versionName 正确
      ⑦ 包内 hap 文件名与 pack.info 的 packages[].name 一致（996 高发坑）
      ⑧ 包名与 app.json5 一致（997 高发坑）

.EXAMPLE
    pwsh scripts/verify-upload.ps1
    pwsh scripts/verify-upload.ps1 -AppPath "C:\Users\Dang\Desktop\Rock阅读-1.0.7-上架.app"
#>
[CmdletBinding()]
param(
    # 待校验的 .app 包；默认取 build/outputs/release 下最新的 *signed.app
    [string]$AppPath,
    # 本地发布 Profile（用于逐字节比对）
    [string]$ProfilePath = "F:\AI\HarmonyOS\keys\rockreader-v2.p7b",
    # 期望的应用包名（997 高发坑：与 AGC 上的包名必须一致）
    [string]$ExpectBundle = "com.rocktier.rockreader",
    # 期望的 versionCode / versionName
    [int]$ExpectVersionCode = 0,
    [string]$ExpectVersionName = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$ide = "E:\Program Files\Huawei\DevEco Studio"
$signTool = "$ide\sdk\default\openharmony\toolchains\lib\hap-sign-tool.jar"

$fail = @()
function Step { param($msg) Write-Host "==> $msg" -ForegroundColor Cyan }
function Pass { param($msg) Write-Host "    [PASS] $msg" -ForegroundColor Green }
function Fail { param($msg) Write-Host "    [FAIL] $msg" -ForegroundColor Red; $script:fail += $msg }

# 从 PKCS#7 二进制里抠出内嵌 JSON：找第一个 '{'，然后做带字符串感知的花括号配对
function Extract-Json {
    param([string]$raw)
    $start = $raw.IndexOf("{")
    if ($start -lt 0) { return $null }
    $depth = 0
    $inStr = $false
    $esc = $false
    for ($i = $start; $i -lt $raw.Length; $i++) {
        $c = $raw[$i]
        if ($inStr) {
            if ($esc) { $esc = $false }
            elseif ($c -eq "\") { $esc = $true }
            elseif ($c -eq '"') { $inStr = $false }
            continue
        }
        if ($c -eq '"') { $inStr = $true; continue }
        if ($c -eq "{") { $depth++ }
        elseif ($c -eq "}") {
            $depth--
            if ($depth -eq 0) { return $raw.Substring($start, $i - $start + 1) }
        }
    }
    return $null
}

# ---------------------------------------------------------------- 0. 定位包
Step "定位待校验的 .app"
if (-not $AppPath) {
    $dir = Join-Path $root "build\outputs\release"
    if (-not (Test-Path $dir)) { throw "找不到产物目录 $dir —— 请先出包" }
    $cands = Get-ChildItem $dir -Filter *.app | Sort-Object LastWriteTime -Descending
    if (-not $cands) { throw "产物目录里没有 .app" }
    # ⚠️ 有 unsigned.app 时必须显式挑 signed，绝不"取第一个"
    $signed = $cands | Where-Object { $_.Name -like "*signed.app" -and $_.Name -notlike "*unsigned*" }
    if (-not $signed) { throw "产物目录里没有 *signed.app（只有 unsigned —— 上传它必报 993）" }
    $AppPath = $signed[0].FullName
}
if (-not (Test-Path $AppPath)) { throw "包不存在：$AppPath" }
$AppPath = (Resolve-Path $AppPath).Path
$appName = Split-Path -Leaf $AppPath
Write-Host "    包：$appName"

# ⚠️ 上传错文件是 993 的头号现实成因：文件名含 unsigned 一律拒绝
if ($appName -match "unsigned") {
    Fail "文件名含 'unsigned' —— 无签名块，上传必然 993（Profile 文件非法）。请改用 *signed.app"
}

# ---------------------------------------------------------------- 1. 验签 + 导出 Profile
Step "验签并导出包内 Profile（hap-sign-tool verify-app）"
$tmp = Join-Path $root ".tmp\verify-upload"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$outProfile = Join-Path $tmp "profile.p7b"
$outChain = Join-Path $tmp "chain.cer"
Remove-Item $outProfile, $outChain -ErrorAction SilentlyContinue

# ⚠️ 不能直接 `& java ... 2>&1`：java 把日志写 stderr，PowerShell 会把它转成
#    错误记录，在 $ErrorActionPreference="Stop" 下直接中断脚本 ⇒ 改用
#    Start-Process 把 stdout/stderr 分流到文件再读。
# ⚠️ Start-Process 复制环境变量时，若同时存在大小写不同的同名 proxy 变量
#    （本机 HTTP_PROXY/http_proxy/HTTPS_PROXY/https_proxy 四项全有），
#    会抛"字典中的关键字重复" ⇒ 临时摘掉全部 proxy 变量，跑完再还回去。
$proxyNames = @("http_proxy", "HTTP_PROXY", "https_proxy", "HTTPS_PROXY")
$savedProxy = @{}
foreach ($pn in $proxyNames) {
    $v = [Environment]::GetEnvironmentVariable($pn, "Process")
    if ($null -ne $v) { $savedProxy[$pn] = $v }
    Remove-Item "Env:$pn" -ErrorAction SilentlyContinue
}

$logOut = Join-Path $tmp "verify.out.txt"
$logErr = Join-Path $tmp "verify.err.txt"
Remove-Item $logOut, $logErr -ErrorAction SilentlyContinue
try {
    # ⚠️ Start-Process 的 ArgumentList 不自动处理空格 ⇒ 含空格的路径要自己加引号，
    #    否则 "E:\Program Files\..." 会被截成 "E:\Program"（Unable to access jarfile）。
    $javaArgs = @("-jar", "`"$signTool`"", "verify-app",
        "-inFile", "`"$AppPath`"", "-inForm", "zip",
        "-outProfile", "`"$outProfile`"", "-outCertChain", "`"$outChain`"")
    $proc = Start-Process -FilePath "$ide\jbr\bin\java" `
        -ArgumentList $javaArgs `
        -NoNewWindow -Wait -PassThru `
        -RedirectStandardOutput $logOut -RedirectStandardError $logErr
} finally {
    foreach ($pn in $proxyNames) {
        if ($savedProxy.ContainsKey($pn)) {
            [Environment]::SetEnvironmentVariable($pn, $savedProxy[$pn], "Process")
        }
    }
}
$verifyLog = ((Get-Content $logOut -Raw -ErrorAction SilentlyContinue) + "`n" +
              (Get-Content $logErr -Raw -ErrorAction SilentlyContinue))
if (-not $verifyLog) { $verifyLog = "java 退出码 $($proc.ExitCode)（无输出）" }
Write-Host ($verifyLog.Trim() -split "`n" | ForEach-Object { "    $_" })

if ($verifyLog -match "signature not found") {
    Fail "包内没有签名块 —— 这是 unsigned 包，上传必报 993"
} elseif ($verifyLog -match "verify-app success") {
    Pass "验签通过（verify-app success）"
} else {
    Fail "验签未通过"
}

# ---------------------------------------------------------------- 2. 抠包内 Profile 判 type
Step "解析包内 Profile"
if (-not (Test-Path $outProfile)) {
    Fail "未能导出包内 Profile（包可能根本没签名）"
} else {
    $raw = [System.IO.File]::ReadAllText($outProfile, [System.Text.Encoding]::GetEncoding("ISO-8859-1"))
    function JGet($obj, $path) {
        $cur = $obj
        foreach ($seg in $path.Split(".")) {
            if ($null -eq $cur) { return $null }
            $cur = $cur.$seg
        }
        return $cur
    }
    # ⚠️ .p7b 是 PKCS#7 容器，JSON 内嵌在八位组串里 ⇒ 不能用 LastIndexOf("}")，
    #    那样会抓到二进制里的括号。必须从第一个 '{' 起做**带字符串感知**的花括号配对。
    $json = Extract-Json $raw
    if (-not $json) {
        Fail "包内 Profile 里没找到 JSON"
        $prof = $null
    } else {
        try {
            $prof = $json | ConvertFrom-Json
        } catch {
            Fail "包内 Profile JSON 解析失败：$($_.Exception.Message)"
            $prof = $null
        }
    }

    if ($prof) {
    # ① type 必须是 release（首次 993 的根因：自动签名 => type=debug）
    if ($prof.type -eq "release") { Pass "Profile type = release（用的是发布签名，非自动签名）" }
    else { Fail "Profile type = '$($prof.type)' —— 不是 release！AGC 必报 993（官方成因四：包被自动签名）" }

    # ② bundle-name 必须匹配本应用（官方成因二：Profile 不属于该应用）
    $pBundle = JGet $prof "bundle-info.bundle-name"
    if ($pBundle -eq $ExpectBundle) { Pass "Profile bundle-name = $pBundle" }
    else { Fail "Profile bundle-name = '$pBundle'，期望 '$ExpectBundle'" }

    # ③ 证书有效期（官方成因三：证书被删/过期 ⇒ Profile 失效）
    $notBefore = [int64](JGet $prof "validity.not-before")
    $notAfter = [int64](JGet $prof "validity.not-after")
    $nb = [DateTimeOffset]::FromUnixTimeSeconds($notBefore).LocalDateTime
    $na = [DateTimeOffset]::FromUnixTimeSeconds($notAfter).LocalDateTime
    Write-Host "    Profile 有效期：$nb ~ $na"
    if ($na -gt (Get-Date)) { Pass "证书未过期" }
    else { Fail "证书已过期（$na）" }

    # ④ 与本地发布材料逐字节一致（防止拿错 Profile / 拿成 Journal 的）
    if (Test-Path $ProfilePath) {
        $h1 = (Get-FileHash $outProfile -Algorithm MD5).Hash
        $h2 = (Get-FileHash $ProfilePath -Algorithm MD5).Hash
        if ($h1 -eq $h2) { Pass "包内 Profile 与本地发布材料逐字节一致（md5 $($h1.Substring(0,8))…）" }
        else { Fail "包内 Profile 与本地 $ProfilePath 不一致（md5 $h1 vs $h2）—— 可能拿错了 Profile" }
    } else {
        Fail "本地发布 Profile 不存在：$ProfilePath"
    }

    # 附带的 debug 痕迹（自动签名的标志）
    if ($raw -match "debug-info" -or $raw -match "development-certificate") {
        Fail "Profile 里含 debug-info / development-certificate —— 是调试 Profile"
    } else {
        Pass "无 debug-info / development-certificate"
    }
    }  # end if ($prof)
}  # end else (包内 Profile 存在)

# ---------------------------------------------------------------- 3. pack.info 复核
Step "复核包内 pack.info"
$unzipDir = Join-Path $tmp "unzip"
Remove-Item $unzipDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $unzipDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($AppPath, $unzipDir)
$packInfoPath = Get-ChildItem $unzipDir -Filter pack.info -Recurse | Select-Object -First 1
if (-not $packInfoPath) {
    Fail "包内没有 pack.info"
} else {
    $pi = Get-Content $packInfoPath.FullName -Raw | ConvertFrom-Json
    $s = $pi.summary.app
    if ($s.bundleName -eq $ExpectBundle) { Pass "pack.info bundleName = $($s.bundleName)" }
    else { Fail "pack.info bundleName = '$($s.bundleName)'，期望 '$ExpectBundle'（AGC 会报 997）" }

    $vc = [int64]$s.version.code
    $vn = $s.version.name
    if ($ExpectVersionCode -gt 0 -and $vc -ne $ExpectVersionCode) {
        Fail "pack.info versionCode = $vc，期望 $ExpectVersionCode"
    } elseif ($ExpectVersionCode -gt 0) {
        Pass "pack.info versionCode = $vc"
    } else {
        Write-Host "    pack.info versionCode = $vc（未设期望值，仅记录）"
    }
    if ($ExpectVersionName -and $vn -ne $ExpectVersionName) {
        Fail "pack.info versionName = '$vn'，期望 '$ExpectVersionName'"
    } elseif ($ExpectVersionName) {
        Pass "pack.info versionName = $vn"
    } else {
        Write-Host "    pack.info versionName = $vn（未设期望值，仅记录）"
    }

    # ⑦ hap 文件名必须与 packages[].name 一致（996 高发坑）
    foreach ($pkg in $pi.packages) {
        $need = "$($pkg.name).hap"
        $exists = Get-ChildItem $unzipDir -Filter $need -Recurse -ErrorAction SilentlyContinue
        if ($exists) { Pass "hap 文件名与 pack.info packages[].name 一致（$need）" }
        else { Fail "包内找不到 $($pkg.name).hap（AGC 报 996：包名与 pack.info 不一致）" }
    }
}

# ---------------------------------------------------------------- 4. 与 app.json5 对照
Step "与工程配置对照"
$appJsonPath = Join-Path $root "AppScope\app.json5"
if (Test-Path $appJsonPath) {
    $aj = (Get-Content $appJsonPath -Raw) -replace "//.*", ""
    $aj = $aj | ConvertFrom-Json
    if ($aj.app.bundleName -eq $ExpectBundle) { Pass "app.json5 bundleName = $($aj.app.bundleName)" }
    else { Fail "app.json5 bundleName = '$($aj.app.bundleName)'，期望 '$ExpectBundle'" }
    Write-Host "    app.json5 版本：$($aj.app.versionName) (code $($aj.app.versionCode))"
} else {
    Fail "找不到 AppScope/app.json5"
}

# ---------------------------------------------------------------- 结论
Write-Host ""
Write-Host "================ 上传前闸门结论 ================" -ForegroundColor Cyan
if ($fail.Count -eq 0) {
    Write-Host "  全部通过 —— 这个包可以上传 AGC。" -ForegroundColor Green
    Write-Host "  上传路径：$AppPath"
    Write-Host "  md5：$((Get-FileHash $AppPath -Algorithm MD5).Hash)"
    Write-Host "  sha256：$((Get-FileHash $AppPath -Algorithm SHA256).Hash)"
    exit 0
} else {
    Write-Host "  有 $($fail.Count) 项不通过 —— **不要上传这个包**，会报 993：" -ForegroundColor Red
    foreach ($f in $fail) { Write-Host "    - $f" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  排查顺序（AGC 官方 993 排查）：" -ForegroundColor Yellow
    Write-Host "   1. 抠包内 Profile 看 type —— 必须是 release（不能用 -p product=default）"
    Write-Host "   2. bundle-name 必须 == AGC 上的包名"
    Write-Host "   3. AGC 证书/Profile 页看该 Profile 是否失效（证书被删/过期）"
    Write-Host "   4. 确认传的是 *signed.app，不是 *unsigned.app"
    exit 1
}
