# ============================================================
# MDReader - Release 发布脚本 (Windows PowerShell)
# 用途：更新版本号 -> 构建双安装包 -> 打 tag -> 创建 GitHub Release
# 用法：
#   .\release.ps1 -Version 0.1.1                        # 发布 0.1.1（含构建）
#   .\release.ps1 -Version 0.1.1 -SkipBuild             # 跳过构建，只发版
#   .\release.ps1 -Version 0.1.1 -Notes "修复了xxx"      # 自定义 release notes
#   .\release.ps1 -Version 0.1.1 -Draft                 # 创建为草稿 release
# ============================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$Version,
    [switch]$SkipBuild,
    [string]$Notes = "",
    [switch]$Draft
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Log-Info  { param($m) Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Log-Ok    { param($m) Write-Host "[OK]    $m" -ForegroundColor Green }
function Log-Warn  { param($m) Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Log-Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }
function Step      { param($m) Write-Host "`n=== $m ===" -ForegroundColor Magenta }

# 校验版本号格式（X.Y.Z）
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Log-Err "版本号格式错误，应为 X.Y.Z（如 0.1.1）"
    exit 1
}

$tag = "v$Version"
$product = "MDReader"

# 检查 git
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log-Err "未找到 git"
    exit 1
}

# 检查 gh CLI
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Log-Err "未找到 gh CLI，请先安装 GitHub CLI 并执行 gh auth login"
    exit 1
}

# 检查 gh 认证状态
$ghAuth = gh auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Log-Err "gh 未认证，请先执行 gh auth login"
    $ghAuth | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}

# 检查工作区是否干净
$status = git status --porcelain
if ($status) {
    Log-Warn "工作区有未提交的变更，建议先用 update.ps1 提交后再发布"
    $confirm = Read-Host "是否继续？(y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { exit 0 }
}

# ============================================================
Step "1/7 更新版本号到 $Version"
# ============================================================

$tauriConf = Join-Path $root "src-tauri\tauri.conf.json"
$cargoToml = Join-Path $root "src-tauri\Cargo.toml"

# tauri.conf.json
$confContent = Get-Content $tauriConf -Raw -Encoding UTF8
$confNew = $confContent -replace '"version":\s*"\d+\.\d+\.\d+"', "`"version`": `"$Version`""
if ($confNew -eq $confContent) {
    Log-Warn "tauri.conf.json 中未找到版本号字段，可能已是 $Version"
} else {
    [System.IO.File]::WriteAllText($tauriConf, $confNew, [System.Text.UTF8Encoding]::new($false))
    Log-Ok "tauri.conf.json 版本已更新为 $Version"
}

# Cargo.toml
$cargoContent = Get-Content $cargoToml -Raw -Encoding UTF8
$cargoNew = $cargoContent -replace '^version\s*=\s*"\d+\.\d+\.\d+"', "version = `"$Version`""
if ($cargoNew -eq $cargoContent) {
    Log-Warn "Cargo.toml 中未找到版本号字段，可能已是 $Version"
} else {
    [System.IO.File]::WriteAllText($cargoToml, $cargoNew, [System.Text.UTF8Encoding]::new($false))
    Log-Ok "Cargo.toml 版本已更新为 $Version"
}

# ============================================================
Step "2/7 同步 dist 并提交版本变更"
# ============================================================

$dist = Join-Path $root "dist"
if (-not (Test-Path (Join-Path $dist "resources"))) {
    New-Item -ItemType Directory -Path (Join-Path $dist "resources") | Out-Null
}
Copy-Item (Join-Path $root "index.html") (Join-Path $dist "index.html") -Force
Copy-Item (Join-Path $root "resources\*") (Join-Path $dist "resources") -Recurse -Force
Log-Ok "dist 同步完成"

git add --all
git commit -m "Bump version to $Version" | Out-Null
Log-Ok "版本变更已提交: $(git log --oneline -1)"

# ============================================================
Step "3/7 创建并推送 tag $tag"
# ============================================================

# 检查 tag 是否已存在
$tagExists = git tag -l $tag
if ($tagExists) {
    Log-Warn "tag $tag 已存在，是否删除后重建？(y/N)"
    $confirm = Read-Host
    if ($confirm -ne 'y' -and $confirm -ne 'Y') { exit 0 }
    git tag -d $tag | Out-Null
    git push origin ":refs/tags/$tag" 2>$null
}

$tagMsg = "$product $tag`n`n版本说明见 Release 页面。`n`n版权所有 (C) $(Get-Date -Format yyyy) 中国邮政集团有限公司浙江省信息技术中心"
git tag -a $tag -m $tagMsg
Log-Ok "本地 tag $tag 已创建"

git push origin $tag 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Log-Err "tag 推送失败"
    exit 1
}
git push origin main 2>&1 | Out-Null
Log-Ok "tag 与 main 已推送"

# ============================================================
Step "4/7 构建离线安装包 (offlineInstaller)"
# ============================================================

$bundleDir = Join-Path $root "src-tauri\target\release\bundle\nsis"
$offlineExe = Join-Path $bundleDir "MDReader_${Version}_x64-offline_setup.exe"
$onlineExe  = Join-Path $bundleDir "MDReader_${Version}_x64-online_setup.exe"

# 切到 offlineInstaller
$confContent = Get-Content $tauriConf -Raw -Encoding UTF8
$confContent = $confContent -replace '"type":\s*"downloadBootstrapper"', '"type": "offlineInstaller"'
[System.IO.File]::WriteAllText($tauriConf, $confContent, [System.Text.UTF8Encoding]::new($false))

if ($SkipBuild) {
    Log-Warn "跳过构建 (-SkipBuild)"
} else {
    Log-Info "构建中（首次约 3-5 分钟）..."
    Set-Location (Join-Path $root "src-tauri")
    cargo tauri build --bundles nsis 2>&1 | Select-Object -Last 5 | ForEach-Object { Write-Host "        $_" -ForegroundColor Gray }
    Set-Location $root
    if ($LASTEXITCODE -ne 0) { Log-Err "离线包构建失败"; exit 1 }
}

# 重命名
$builtExe = Join-Path $bundleDir "MDReader_${Version}_x64-setup.exe"
if (Test-Path $builtExe) {
    if (Test-Path $offlineExe) { Remove-Item $offlineExe -Force }
    Rename-Item $builtExe "MDReader_${Version}_x64-offline_setup.exe"
}
if (Test-Path $offlineExe) {
    $size = [math]::Round((Get-Item $offlineExe).Length / 1MB, 2)
    Log-Ok "离线安装包: MDReader_${Version}_x64-offline_setup.exe ($size MB)"
} else {
    Log-Err "未找到离线安装包"
    exit 1
}

# ============================================================
Step "5/7 构建在线安装包 (downloadBootstrapper)"
# ============================================================

$confContent = Get-Content $tauriConf -Raw -Encoding UTF8
$confContent = $confContent -replace '"type":\s*"offlineInstaller"', '"type": "downloadBootstrapper"'
[System.IO.File]::WriteAllText($tauriConf, $confContent, [System.Text.UTF8Encoding]::new($false))

if (-not $SkipBuild) {
    Log-Info "构建中..."
    Set-Location (Join-Path $root "src-tauri")
    cargo tauri build --bundles nsis 2>&1 | Select-Object -Last 5 | ForEach-Object { Write-Host "        $_" -ForegroundColor Gray }
    Set-Location $root
    if ($LASTEXITCODE -ne 0) { Log-Err "在线包构建失败"; exit 1 }
}

$builtExe = Join-Path $bundleDir "MDReader_${Version}_x64-setup.exe"
if (Test-Path $builtExe) {
    if (Test-Path $onlineExe) { Remove-Item $onlineExe -Force }
    Rename-Item $builtExe "MDReader_${Version}_x64-online_setup.exe"
}
if (Test-Path $onlineExe) {
    $size = [math]::Round((Get-Item $onlineExe).Length / 1MB, 2)
    Log-Ok "在线安装包: MDReader_${Version}_x64-online_setup.exe ($size MB)"
} else {
    Log-Err "未找到在线安装包"
    exit 1
}

# 恢复默认配置为 offlineInstaller
$confContent = Get-Content $tauriConf -Raw -Encoding UTF8
$confContent = $confContent -replace '"type":\s*"downloadBootstrapper"', '"type": "offlineInstaller"'
[System.IO.File]::WriteAllText($tauriConf, $confContent, [System.Text.UTF8Encoding]::new($false))

# ============================================================
Step "6/7 生成 Release Notes"
# ============================================================

if ([string]::IsNullOrWhiteSpace($Notes)) {
    $notesPath = Join-Path $env:TEMP "mdreader-release-notes-$Version.md"
    @"
# $product $tag

MDReader Markdown 阅读器新版本发布。

## 安装包

| 文件 | 大小 | 说明 |
|---|---|---|
| \`MDReader_${Version}_x64-offline_setup.exe\` | ~209 MB | 含 WebView2 Runtime，离线可装 |
| \`MDReader_${Version}_x64-online_setup.exe\` | ~3 MB | 不含 WebView2，安装时联网下载 |

## 系统要求

- Windows 10 及以上
- （macOS 包需在 macOS 环境构建）

## 许可证

MIT / Apache-2.0 双协议

版权所有 (C) $(Get-Date -Format yyyy) 中国邮政集团有限公司浙江省信息技术中心
(China Post Group Co., Ltd. Zhejiang IT Center)
"@ | Set-Content $notesPath -Encoding UTF8
    $Notes = $notesPath
    Log-Ok "已生成默认 Release Notes"
}

# ============================================================
Step "7/7 创建 GitHub Release 并上传安装包"
# ============================================================

$releaseArgs = @("release", "create", $tag,
    $offlineExe, $onlineExe,
    "--title", "$product $tag",
    "--notes-file", $Notes)
if ($Draft) { $releaseArgs += "--draft" } else { $releaseArgs += "--latest" }

Log-Info "执行: gh $($releaseArgs -join ' ')"
gh @releaseArgs 2>&1 | ForEach-Object { Write-Host "        $_" -ForegroundColor Gray }
if ($LASTEXITCODE -ne 0) {
    Log-Err "创建 Release 失败"
    exit 1
}
Log-Ok "Release $tag 发布成功！"

# 清理临时 notes
if (Test-Path $Notes) { Remove-Item $Notes -Force -ErrorAction SilentlyContinue }

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  发布完成: $product $tag" -ForegroundColor Green
Write-Host "  仓库: https://github.com/zoomgu680/MDReader" -ForegroundColor Green
Write-Host "  Release: https://github.com/zoomgu680/MDReader/releases/tag/$tag" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
