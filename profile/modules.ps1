# ==============================================================
# 模块加载（zoxide 懒加载；PSCompletions / PSFzf 通过 OnIdle 懒加载）
# ==============================================================

# zoxide：缓存生成与加载延迟到首次 z/zi 调用（init 输出全部为 global: 函数 +
# 全局别名，可安全按需 dot-source；首次调用有一次性的生成开销，之后命中缓存）
if ($global:__Tools.ContainsKey('zoxide')) {
    $script:__zoxideCache = "$env:TEMP\zoxide-init-cache.ps1"
    $script:__zoxideReady = $false
    function __Ensure-Zoxide {
        if ($script:__zoxideReady) { return }
        $script:__zoxideReady = $true
        $null = Initialize-CachedInit -Command 'zoxide' -CacheFile $script:__zoxideCache -Arguments @('init','powershell')
        if (Test-Path $script:__zoxideCache) { . $script:__zoxideCache }
    }
    # 占位函数：首次调用触发加载；zoxide init 会注册全局别名 z/zi（别名优先于函数）
    function z  { __Ensure-Zoxide; z @args }
    function zi { __Ensure-Zoxide; zi @args }
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

    # PSFzf（Ctrl+t 查文件，Ctrl+r 搜历史；-GitKeyBindings: Ctrl+g, Ctrl+b/f/h/p/s/t
    # 分别对应 git 分支/文件/提交哈希/PR/stash/tag 的 fzf 选择）
    if ($global:__Tools.ContainsKey('fzf')) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
            Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -GitKeyBindings
            # fzf-tab 式 Tab 补全（Tab 弹出 fzf 选择，右侧实时预览）。
            # 若与 PSCompletions 的补全菜单冲突，设 $env:PROFILE_NO_FZF_TAB=1 恢复默认 Tab
            if (-not $env:PROFILE_NO_FZF_TAB) {
                Set-PsFzfOption -TabExpansion -TabCompletionPreviewWindow 'right:60%'
            }
        }
    }
}
