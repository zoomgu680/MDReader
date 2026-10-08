# ============================================================
# MDReader - 源码更新脚本 (Windows PowerShell)
# 用途：同步 dist -> 提交变更 -> 推送到 GitHub
# 用法：
#   .\update.ps1                          # 自动生成提交信息
#   .\update.ps1 -Message "修复xxx"        # 指定提交信息
#   .\update.ps1 -NoPush                  # 只提交不推送
#   .\update.ps1 -NoSync                  # 跳过 dist 同步
# ============================================================

param(
    [string]$Message = "",
    [switch]$NoPush,
    [switch]$NoSync
)

# 注意：不能用 Stop——PS 5.1 下 git/cargo 的 stderr 输出会被当作异常中断脚本；
# 关键步骤均通过 $LASTEXITCODE 或远程状态校验兜底
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Log-Info  { param($m) Write-Host "[INFO]  $m" -ForegroundColor Cyan }
function Log-Ok    { param($m) Write-Host "[OK]    $m" -ForegroundColor Green }
function Log-Warn  { param($m) Write-Host "[WARN]  $m" -ForegroundColor Yellow }
function Log-Err   { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

# 1. 检查 git 是否可用
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Log-Err "未找到 git，请先安装 Git for Windows"
    exit 1
}

# 2. 同步 dist
if (-not $NoSync) {
    Log-Info "同步 dist 目录..."
    $dist = Join-Path $root "dist"
    if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist | Out-Null }
    if (-not (Test-Path (Join-Path $dist "resources"))) {
        New-Item -ItemType Directory -Path (Join-Path $dist "resources") | Out-Null
    }
    Copy-Item (Join-Path $root "index.html") (Join-Path $dist "index.html") -Force
    Copy-Item (Join-Path $root "resources\*") (Join-Path $dist "resources") -Recurse -Force
    Log-Ok "dist 同步完成"
} else {
    Log-Warn "跳过 dist 同步"
}

# 3. 检查 git 状态
$status = git status --porcelain
if (-not $status) {
    Log-Ok "工作区干净，无变更需要提交"
    exit 0
}

$changed = ($status | Measure-Object -Line).Lines
Log-Info "检测到 $changed 个变更文件："
$status | ForEach-Object { Write-Host "        $_" -ForegroundColor Gray }

# 4. 暂存
Log-Info "暂存所有变更..."
git add --all
if ($LASTEXITCODE -ne 0) { Log-Err "git add 失败"; exit 1 }

# 5. 生成提交信息
if ([string]::IsNullOrWhiteSpace($Message)) {
    $files = ($status | Where-Object { $_ -match '^\s*[AM]' } | ForEach-Object {
        ($_ -replace '^\s*[AM]\s+', '') -replace '\s+', ' '
    }) -join ', '
    if ($files.Length -gt 80) { $files = $files.Substring(0, 77) + "..." }
    $Message = "更新: $files"
}
Log-Info "提交信息: $Message"

# 6. 提交
$commitResult = git commit -m $Message 2>&1
if ($LASTEXITCODE -ne 0) {
    Log-Err "git commit 失败:"
    $commitResult | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
$lastCommit = git log --oneline -1
Log-Ok "提交成功: $lastCommit"

# 7. 推送
if ($NoPush) {
    Log-Warn "跳过推送（-NoPush）"
    exit 0
}

Log-Info "推送到 origin/main..."
$pushResult = git push origin main 2>&1
# 注意：push 可能因沙箱拦截 ~/.gitconfig 写入返回非零但实际成功，
# 因此用远程状态校验代替 exit code 判断
$localHead = (git rev-parse HEAD).Trim()
$remoteMain = (git ls-remote origin refs/heads/main) -replace '\s.*$',''
if ($localHead -eq $remoteMain) {
    Log-Ok "推送成功"
} else {
    Log-Err "推送失败（远程为 $remoteMain，本地为 $localHead）:"
    $pushResult | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    exit 1
}
