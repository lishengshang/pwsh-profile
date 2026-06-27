# ==============================================================
# 环境初始化
# ==============================================================

# fnm (Node 版本管理) —— 缓存 7 天，原子写入
if (Get-Command fnm -ErrorAction SilentlyContinue) {
    $_fnmCache = "$env:TEMP\fnm-init-cache.ps1"
    if (-not (Test-Path $_fnmCache) -or
        (Get-Item $_fnmCache).LastWriteTime -lt (Get-Date).AddDays(-7)) {
        try {
            $_fnmOut = fnm env --use-on-cd --shell powershell 2>$null | Out-String
            if ($LASTEXITCODE -eq 0 -and $_fnmOut.Trim()) {
                $_tmp = "$_fnmCache.tmp"
                Set-Content -Path $_tmp -Value $_fnmOut -Encoding UTF8
                Move-Item -Path $_tmp -Destination $_fnmCache -Force
            }
        } catch {
            Write-Host "[fnm] 缓存生成失败: $_" -ForegroundColor Yellow
        }
    }
    if (Test-Path $_fnmCache) {
        . $_fnmCache
    }
}

# 默认编辑器：让 git / npm edit / crontab 等所有遵循 EDITOR/VISUAL 的工具统一走 nvim
if (-not $env:EDITOR -and (Get-Command nvim -ErrorAction SilentlyContinue)) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}

# Scoop（PSCompletions 的 scoop hooks 依赖此变量）
if (-not $env:SCOOP -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
    $env:SCOOP = Split-Path (Split-Path (Get-Command scoop).Source)
}
