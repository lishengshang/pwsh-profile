# ==============================================================
# 模块加载（zoxide 同步缓存；PSCompletions / PSFzf 通过 OnIdle 懒加载）
# ==============================================================

# zoxide（缓存 7 天，原子写入）
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $_zoxideCache = "$env:TEMP\zoxide-init-cache.ps1"
    if (-not (Test-Path $_zoxideCache) -or
        (Get-Item $_zoxideCache).LastWriteTime -lt (Get-Date).AddDays(-7)) {
        try {
            $_zoxideOut = zoxide init powershell 2>$null | Out-String
            if ($LASTEXITCODE -eq 0 -and $_zoxideOut.Trim()) {
                $_tmp = "$_zoxideCache.tmp"
                Set-Content -Path $_tmp -Value $_zoxideOut -Encoding UTF8
                Move-Item -Path $_tmp -Destination $_zoxideCache -Force
            }
        } catch {
            Write-Host "[zoxide] 缓存生成失败: $_" -ForegroundColor Yellow
        }
    }
    if (Test-Path $_zoxideCache) {
        . $_zoxideCache
    }
}

# 注册 OnIdle 事件，在第一次空闲（通常是首个 prompt 渲染后）懒加载重量级模块
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -SupportEvent -Action {
    # 仅执行一次
    Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

    # PSCompletions
    Import-Module PSCompletions -ErrorAction SilentlyContinue

    # PSFzf（Ctrl+t 查文件，Ctrl+r 搜历史）
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        }
    }
}
