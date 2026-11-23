# ==============================================================
# 模块加载（zoxide 跳转与目录记录；PSCompletions 顶层同步导入；PSFzf 走 OnIdle 懒加载）
# ==============================================================

# z/zi 仍依赖上游别名，但目录记录独立启用，避免上游覆盖当前提示符。
if ($global:__Tools.ContainsKey('zoxide')) {
    $script:__zoxideCache = "$env:TEMP\zoxide-init-cache.ps1"
    $script:__zoxideReady = $false
    function __Ensure-Zoxide {
        if ($script:__zoxideReady) { return }
        $script:__zoxideReady = $true
        $init = __Get-CachedInitScript -Command 'zoxide' -CacheFile $script:__zoxideCache -Arguments @('init', 'powershell', '--hook', 'none')
        if ($null -ne $init) { . $init }
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

# PowerShell 7 用位置回调覆盖 cmdlet、跳转命令和目录栈，5.1 在绘制提示符时检测。
function __Enable-ZoxideHistory {
    param([switch]$DefaultPrompt)

    $commands = $ExecutionContext.InvokeCommand
    if ($commands.PSObject.Properties['LocationChangedAction']) {
        $previousAction = Get-Variable __zoxideLocationAction -Scope Script -ValueOnly -ErrorAction Ignore
        $script:__zoxideLocationAction = [EventHandler[System.Management.Automation.LocationChangedEventArgs]] {
            $change = $args[1]

            if ($change.NewPath.Provider.Name -eq 'FileSystem' -and
                ($change.OldPath.Provider.Name -ne 'FileSystem' -or $change.NewPath.ProviderPath -ne $change.OldPath.ProviderPath)) {
                __Add-ZoxideLocation -Path $change.NewPath.ProviderPath
            }
        }
        $otherActions = [Delegate]::Remove($commands.LocationChangedAction, $previousAction)
        $commands.LocationChangedAction = [Delegate]::Combine($otherActions, $script:__zoxideLocationAction)
        return
    }

    $script:__zoxidePromptLocation = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath }
    if ($DefaultPrompt) {
        function global:prompt {
            __Update-ZoxidePromptLocation
            'PS> '
        }
        return
    }

    # Starship 会在调用预提示符函数前捕获状态，无需包裹它的 prompt。
    $preCommand = Get-Item -LiteralPath Function:\Invoke-Starship-PreCommand -ErrorAction Ignore
    $registered = Get-Variable __zoxidePreCommand -Scope Script -ValueOnly -ErrorAction Ignore
    if ($preCommand -and [object]::ReferenceEquals($preCommand.ScriptBlock, $registered)) { return }
    $script:__zoxidePriorPreCommand = if ($preCommand) { $preCommand.ScriptBlock }
    function global:Invoke-Starship-PreCommand {
        try {
            if ($script:__zoxidePriorPreCommand) { & $script:__zoxidePriorPreCommand }
        }
        finally {
            __Update-ZoxidePromptLocation
        }
    }
    $script:__zoxidePreCommand = (Get-Item -LiteralPath Function:\Invoke-Starship-PreCommand).ScriptBlock
}

function __Update-ZoxidePromptLocation {
    $path = if ($PWD.Provider.Name -eq 'FileSystem') { $PWD.ProviderPath }
    if ($path -and $path -ne $script:__zoxidePromptLocation) { __Add-ZoxideLocation -Path $path }
    $script:__zoxidePromptLocation = $path
}

function __Add-ZoxideLocation {
    param([string]$Path)

    $tool = $global:__Tools['zoxide']
    if (-not $tool) { return }
    $previousExitCode = Get-Variable LASTEXITCODE -Scope Global -ValueOnly -ErrorAction Ignore
    try {
        $null = & $tool.Source add -- $Path 2>$null
    }
    catch {
        Write-Debug "zoxide 目录记录失败：$_"
    }
    finally {
        $global:LASTEXITCODE = $previousExitCode
    }
}

# psc 兜底：模块正常加载时别名 psc 优先，本函数不参与；只在模块缺失时给指引。
# 不要在这里嵌套 Import-Module（官方禁止），正确做法是新开终端。
function psc {
    Write-Host 'PSCompletions 模块未加载：请新开终端（profile 会同步导入）；仍缺失时执行 Install-Module PSCompletions -Scope CurrentUser' -ForegroundColor Yellow
}

# PSCompletions（命令补全）：官方禁止在函数/脚本块/事件动作里嵌套 Import-Module
# （别名缺失、会话锁死），必须在 $PROFILE 顶层同步导入。v7.3.0 起模块自带懒初始化，
# 首次按 Tab 才做重活，勿再自己包一层 OnIdle（AGENTS.md 规则 1 的例外条款）。
# `*> $null` 吞更新横幅——Out-Null 只接得住成功流，警告流照样刷屏。
# PROFILE_NO_COMPLETIONS=1 完全跳过导入（离线/CI 场景）。
if (-not $env:PROFILE_NO_COMPLETIONS) {
    Import-Module PSCompletions -ErrorAction SilentlyContinue *> $null
}

# PowerShell.OnIdle 是共享事件，重载时只撤销本 profile 登记的订阅。
if ($script:__psFzfIdleJob) {
    Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue |
        Where-Object { $_.Action -and $_.Action.Id -eq $script:__psFzfIdleJob.Id } |
        ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction Ignore }
    $script:__psFzfIdleJob = $null
}

if ($global:__Tools.ContainsKey('fzf')) {
    $script:__psFzfIdleJob = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        if ($global:__Tools.ContainsKey('fzf')) {
            Import-Module PSFzf -ErrorAction SilentlyContinue
            if (Get-Command Set-PsFzfOption -ErrorAction SilentlyContinue) {
                Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -GitKeyBindings
                if ($env:PROFILE_FZF_TAB) {
                    Set-PsFzfOption -TabExpansion -TabCompletionPreviewWindow 'right:60%'
                }
            }
        }
    }
}
