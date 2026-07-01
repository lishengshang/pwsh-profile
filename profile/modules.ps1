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

# 防止重复订阅（如手动 dot-source profile 时）
Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

# 立即加载：psc 是常用命令，首个 prompt 就可能用
Import-Module PSCompletions -ErrorAction SilentlyContinue

# OnIdle 懒加载（不用 -SupportEvent，避免阻止 exit）
# Action 在主 runspace 同步执行，首个 prompt 后触发一次
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # 仅执行一次
    Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

    # PSFzf（Ctrl+t 查文件，Ctrl+r 搜历史）
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        }
    }
}
