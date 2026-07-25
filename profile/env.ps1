# ==============================================================
# 环境初始化
# ==============================================================

# fnm (Node 版本管理) —— 缓存 7 天，原子写入
if ($global:__Tools.ContainsKey('fnm')) {
    $_fnmCache = "$env:TEMP\fnm-init-cache.ps1"
    $_item = Get-Item $_fnmCache -ErrorAction SilentlyContinue
    if (-not $_item -or $_item.LastWriteTime -lt (Get-Date).AddDays(-7)) {
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
if (-not $env:EDITOR -and $global:__Tools.ContainsKey('nvim')) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}
