# ==============================================================
# 模块加载（zoxide 懒加载；PSCompletions 顶层同步导入；PSFzf 走 OnIdle 懒加载）
# ==============================================================

# zoxide：init 输出全是 global: 函数 + 全局别名，可安全 dot-source，
# 故把生成与加载都延迟到首次 z/zi 调用（有一次性开销，之后命中缓存）。
if ($global:__Tools.ContainsKey('zoxide')) {
    $script:__zoxideCache = "$env:TEMP\zoxide-init-cache.ps1"
    $script:__zoxideReady = $false
    function __Ensure-Zoxide {
        if ($script:__zoxideReady) { return }
        $script:__zoxideReady = $true
        $null = Initialize-CachedInit -Command 'zoxide' -CacheFile $script:__zoxideCache -Arguments @('init','powershell')
        if (Test-Path $script:__zoxideCache) { . $script:__zoxideCache }
    }
    # 占位函数：首次调用触发加载。zoxide init 成功时会注册全局别名 z/zi
    # （别名优先级高于函数），此后 z 不再进到这里；若此时仍解析不到别名，
    # 说明 init 生成失败——必须降级提示，绝不能调用自身（会递归到栈溢出）。
    function __Invoke-ZoxidePlaceholder {
        param([string]$Name)
        __Ensure-Zoxide
        if ((Get-Command -Name $Name -ErrorAction SilentlyContinue).CommandType -ne 'Alias') {
            Write-Host "zoxide 初始化未生效，$Name 暂不可用（新开终端重试；仍无效则检查 zoxide init 输出）" -ForegroundColor Yellow
            return
        }
        & $Name @args
    }
    function z  { __Invoke-ZoxidePlaceholder -Name 'z' @args }
    function zi { __Invoke-ZoxidePlaceholder -Name 'zi' @args }
}

# psc 兜底：模块正常加载时别名 psc 优先，本函数不参与；只在模块缺失时给指引。
# 不要在这里嵌套 Import-Module（官方禁止），正确做法是新开终端。
function psc {
    Write-Host 'PSCompletions 模块未加载：请新开终端（profile 会同步导入）；仍缺失时执行 Install-Module PSCompletions -Scope CurrentUser' -ForegroundColor Yellow
}

# 防止重复订阅（如手动 dot-source profile 时）
Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

# PSCompletions（命令补全）：官方禁止在函数/脚本块/事件动作里嵌套 Import-Module
# （别名缺失、会话锁死），必须在 $PROFILE 顶层同步导入。v7.3.0 起模块自带懒初始化，
# 首次按 Tab 才做重活，勿再自己包一层 OnIdle（AGENTS.md 规则 1 的例外条款）。
# `*> $null` 吞更新横幅——Out-Null 只接得住成功流，警告流照样刷屏。
# PROFILE_NO_COMPLETIONS=1 完全跳过导入（离线/CI 场景）。
if (-not $env:PROFILE_NO_COMPLETIONS) {
    Import-Module PSCompletions -ErrorAction SilentlyContinue *> $null
}

# PSFzf 懒加载（OnIdle）
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
    # 仅执行一次
    Unregister-Event -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue

    # PSFzf：Ctrl+t 查文件、Ctrl+r 搜历史，-GitKeyBindings 挂 git 各子命令的 fzf 选择
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
