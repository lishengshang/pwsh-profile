# ==============================================================
# 模块加载
# ==============================================================

# zoxide（缓存 7 天，带错误处理）
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $_zoxideCache = "$env:TEMP\zoxide-init-cache.ps1"
    if (-not (Test-Path $_zoxideCache) -or
        (Get-Item $_zoxideCache).LastWriteTime -lt (Get-Date).AddDays(-7)) {
        try {
            zoxide init powershell | Set-Content $_zoxideCache -Encoding UTF8
        } catch {
            Write-Host "[zoxide] 缓存生成失败: $_" -ForegroundColor Yellow
        }
    }
    if (Test-Path $_zoxideCache) {
        . $_zoxideCache
    }
}

# PSCompletions
Import-Module PSCompletions -ErrorAction SilentlyContinue

# PSFzf（Ctrl+t 查文件，Ctrl+r 搜历史）
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}
