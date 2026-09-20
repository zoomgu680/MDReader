# ============================================================
# MDReader - dist 同步脚本 (Windows PowerShell)
# 用途：把根目录 index.html 和 resources/ 复制到 dist/
#       Tauri 应用加载的是 dist/ 目录，源文件改动后需同步
# 用法：在项目根目录执行 .\sync-dist.ps1
# ============================================================

param(
    [switch]$Watch  # 可选：监听模式，文件变更后自动同步
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root "dist"
$srcIndex = Join-Path $root "index.html"
$srcRes   = Join-Path $root "resources"

if (-not (Test-Path $dist)) {
    New-Item -ItemType Directory -Path $dist | Out-Null
}
if (-not (Test-Path (Join-Path $dist "resources"))) {
    New-Item -ItemType Directory -Path (Join-Path $dist "resources") | Out-Null
}

function Sync-Dist {
    Write-Host "[Sync] 复制 index.html ..." -ForegroundColor Cyan
    Copy-Item $srcIndex (Join-Path $dist "index.html") -Force

    Write-Host "[Sync] 复制 resources/ ..." -ForegroundColor Cyan
    Copy-Item "$srcRes\*" (Join-Path $dist "resources") -Recurse -Force

    Write-Host "[Sync] 完成 $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Green
}

Sync-Dist

if ($Watch) {
    Write-Host "`n[Watch] 监听文件变更中（按 Ctrl+C 退出）..." -ForegroundColor Yellow
    $watcher = New-Object System.IO.FileSystemWatcher $root
    $watcher.IncludeSubdirectories = $true
    $watcher.NotifyFilter = 'LastWrite,FileName'
    $action = {
        if ($Event.MessageArgs.SourceEventArgs.Name -match '^(index\.html|resources[\\/])') {
            Sync-Dist
        }
    }
    Register-ObjectEvent $watcher 'Changed' -Action $action | Out-Null
    Register-ObjectEvent $watcher 'Created' -Action $action | Out-Null
    Register-ObjectEvent $watcher 'Renamed' -Action $action | Out-Null
    try { while ($true) { Start-Sleep -Seconds 1 } } finally { $watcher.Dispose() }
}
