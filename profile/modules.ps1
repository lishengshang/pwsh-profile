# ==============================================================
# 模块加载（zoxide 同步缓存；PSCompletions / PSFzf 通过 OnIdle 懒加载）
# ==============================================================

# zoxide（缓存 7 天 + 升级即失效，原子写入）
if (Initialize-CachedInit -Command 'zoxide' -CacheFile "$env:TEMP\zoxide-init-cache.ps1" -Arguments @('init','powershell')) {
    . "$env:TEMP\zoxide-init-cache.ps1"
}

# 防止重复订阅（如手动 dot-source profile 时）
Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

# OnIdle 懒加载（不用 -SupportEvent，避免阻止 exit）
# Action 在主 runspace 同步执行，首个 prompt 后触发一次
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # 仅执行一次
    Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

    # PSCompletions（命令补全，首个 prompt 后加载）
    Import-Module PSCompletions -ErrorAction SilentlyContinue

    # PSFzf（Ctrl+t 查文件，Ctrl+r 搜历史）
    if ($global:__Tools.ContainsKey('fzf')) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
        }
    }
}
