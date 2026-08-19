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

# psc 兜底：正常情况下模块已由下方同步导入（别名 psc 生效），本函数不参与。
# 仅在模块未加载时给出提示——注意不得在此嵌套调用 Import-Module
# （官方文档明确禁止，嵌套调用会导致模块无法生效），正确做法是新开终端。
function psc {
    Write-Host 'PSCompletions 模块未加载：请新开终端（profile 会同步导入）或运行 .\setup.ps1' -ForegroundColor Yellow
}

# 防止重复订阅（如手动 dot-source profile 时）
Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

# PSCompletions（命令补全）：全局作用域同步加载。
# 官方文档明确要求：不得在函数/脚本块/事件动作中嵌套调用 Import-Module
# （否则模块无法正常生效：别名缺失、$PSCompletions 不完整、会话锁死），
# 必须始终在 $PROFILE 顶层直接导入。因此无法 OnIdle 懒加载，
# 冷启动 +~200ms 为官方设计约束的代价（见 PSCompletions 文档与 #155/#143）。
# `*> $null` 吞掉模块内部版本检查的更新横幅（避免每次启动刷屏）；
# PROFILE_NO_COMPLETIONS=1 完全跳过导入（离线/CI 场景——版本检查有网络请求）。
if (-not $env:PROFILE_NO_COMPLETIONS) {
    Import-Module PSCompletions -ErrorAction SilentlyContinue *> $null
}

# PSFzf 懒加载（OnIdle）
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # 仅执行一次
    Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

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
