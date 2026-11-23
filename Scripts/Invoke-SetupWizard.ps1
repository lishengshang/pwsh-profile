#Requires -Version 5.1
# ==============================================================
# setup.ps1 交互式安装向导（被 setup.ps1 dot-source，不独立执行）
# 简介 → 组件勾选 → 工具预览/剔除 → 确认。仅在无显式组件参数且处于
# 交互终端时被调用（-Wizard 可强制）。
# 工具清单、合法组件与随组件模块的唯一事实来源都是 setup.ps1
# （$wingetTools / $allComponents / $componentModules），本文件只负责展示与交互。
# 输入兜底：Read-Host 在 stdin 被重定向/EOF 时返回空串——所有提示均把空输入
# 视为「接受当前默认继续」，保证意外调用（CI/管道）不会卡死或崩溃。
# ==============================================================

# 组件展示元数据（菜单顺序 = 编号顺序）。Key 必须与 setup.ps1 的 $allComponents 一致。
$script:WizardComponents = @(
    @{ Key = 'core';       Mark = '★ 必选基础'; Desc = 'starship 提示符、eza/zoxide/ripgrep/fd/bat/7-Zip 等基础工具' }
    @{ Key = 'completion'; Mark = '★ 推荐';     Desc = 'fzf 模糊查找（Ctrl+t 文件 / Ctrl+r 历史）+ PSCompletions 命令补全' }
    @{ Key = 'gitui';      Mark = '推荐';       Desc = 'lazygit 终端 Git UI（lg 命令）' }
    @{ Key = 'editor';     Mark = '可选';       Desc = 'Neovim + LazyVim 编辑器（含 treesitter 编译器 WinLibs gcc）' }
    @{ Key = 'files';      Mark = '可选';       Desc = 'yazi 终端文件管理器（y 命令）及预览依赖' }
    @{ Key = 'python';     Mark = '可选';       Desc = 'Miniforge（Python 与 Conda 环境管理）' }
)

# 解析用户输入：按逗号/空白拆分为小写 token（'1 3,core' → '1','3','core'）
function __WizardParseAnswer ([string]$Answer) {
    @($Answer -split '[,\s]+' |
        ForEach-Object { $_.Trim().ToLowerInvariant() } |
        Where-Object { $_ })
}

# 内部：把「编号或名字」token 解析成候选成员并切换勾选。$Indexed 是编号对应的
# 候选清单（编号 = 位置 +1，与展示一致）；$NameProperty 为空表示元素本身就是
# 名字字符串。无法识别的 token 打警告跳过，不阻断其余 token。
function __Toggle-ToggleToken {
    param(
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Indexed,
        [string]$NameProperty,
        [Parameter(Mandatory)][System.Collections.Generic.List[string]]$Toggles,
        [Parameter(Mandatory)][string]$UnknownWarning
    )
    $names = if ($NameProperty) { @($Indexed | ForEach-Object { $_.$NameProperty }) } else { @($Indexed) }
    $idx = 0
    $name = $null
    if ([int]::TryParse($Token, [ref]$idx) -and $idx -ge 1 -and $idx -le $names.Count) {
        $name = $names[$idx - 1]
    }
    elseif ($Token -in $names) { $name = $Token }
    else {
        Write-Warning "${UnknownWarning}: $Token"
        return
    }
    if ($Toggles.Contains($name)) { $Toggles.Remove($name) } else { $null = $Toggles.Add($name) }
}

function Show-WizardIntro {
    Write-Host ''
    Write-Host '════════════ PowerShell Profile 安装向导 ════════════' -ForegroundColor Cyan
    Write-Host @'
模块化 PowerShell 配置（仓库即配置）：提示符、别名、补全与常用工具的接线。

本次安装将做三件事：
  1. 部署 profile 文件到 $PROFILE 目录（已有配置自动备份到 backup-<时间戳>，不会丢）
  2. 安装所选组件的外部工具（winget 静默安装，已装的自动跳过，可随时重跑）
  3. 链接外部配置（starship / lazygit / yazi / nvim，你已有的配置优先，不会被覆盖）

所有工具均为可选依赖：不装也能正常使用，对应功能自动降级或跳过。
'@
    Write-Host '随时可 Ctrl+C 中止；只想部署配置不装工具，可退出后运行 .\setup.ps1 -SkipTools' -ForegroundColor DarkGray
}

# 组件勾选菜单。返回：确认的选择数组（可为空 = 仅部署 profile 本体）；$null = 用户退出。
function Invoke-ComponentMenu {
    param([string[]]$Selected)

    $list  = [System.Collections.Generic.List[string]]@($Selected)
    $keys  = @($script:WizardComponents.Key)
    while ($true) {
        Write-Host ''
        Write-Host '── 1/2 选择要安装的组件 ──' -ForegroundColor Cyan
        for ($i = 0; $i -lt $script:WizardComponents.Count; $i++) {
            $c   = $script:WizardComponents[$i]
            $box = if ($list.Contains($c.Key)) { '[x]' } else { '[ ]' }
            Write-Host ("  {0} {1}) {2,-12} {3} — {4}" -f $box, ($i + 1), $c.Key, $c.Mark, $c.Desc)
        }
        Write-Host '  profile 本体（别名/函数/提示符接线）始终部署；未装的工具运行时自动降级。' -ForegroundColor DarkGray

        $ans    = Read-Host '输入编号或组件名切换勾选（逗号/空格分隔），a=全选，回车=确认，q=退出'
        $tokens = __WizardParseAnswer $ans
        if ($tokens -contains 'q') { return $null }
        if (-not $tokens)          { return @($list) }
        if ($tokens -contains 'a') {
            $list = [System.Collections.Generic.List[string]]$keys
            continue
        }
        foreach ($t in $tokens) {
            __Toggle-ToggleToken -Token $t -Indexed $keys -Toggles $list -UnknownWarning '忽略无法识别的输入'
        }
    }
}

# 安装预览：列出所选组件将装的工具（带用途，可按编号剔除/恢复单个工具）、
# 随组件的模块与外部配置链接。编号在「所选组件全集」内稳定分配，与剔除状态无关。
# 返回：'confirm'（开始安装）/ 'back'（返回组件选择）/ $null（用户退出）。
function Invoke-InstallPreview {
    param(
        [string[]]$Components,
        [object[]]$Tools,
        [System.Collections.IDictionary]$ComponentModules,
        [object[]]$ManagedLinks,
        [System.Collections.Generic.List[string]]$Excluded
    )

    while ($true) {
        Write-Host ''
        Write-Host '── 2/2 安装预览 ──' -ForegroundColor Cyan
        Write-Host '  （已安装的工具会自动跳过，全程幂等，可随时重跑）' -ForegroundColor DarkGray

        $flat = [System.Collections.Generic.List[object]]::new()
        $n    = 0
        foreach ($cg in @($script:WizardComponents | Where-Object { $Components -contains $_.Key })) {
            Write-Host ''
            Write-Host ("  {0}  {1}" -f $cg.Mark, $cg.Key) -ForegroundColor Yellow
            foreach ($t in @($Tools | Where-Object { $_.Component -eq $cg.Key })) {
                $n++
                $null = $flat.Add($t)
                $mark = if ($Excluded.Contains($t.Name)) { '×' } else { ' ' }
                $note = if ($Excluded.Contains($t.Name)) { '  [已剔除]' }
                        elseif ($t.Optional)             { '（纯增强，可剔除）' }
                        else                             { '' }
                Write-Host ("    {0}{1,2}) {2,-12} {3}{4}" -f $mark, $n, $t.Name, $t.Desc, $note)
            }
        }
        if (-not $Components) {
            Write-Host ''
            Write-Host '  （未选择任何组件：仅部署 profile 本体，不安装任何工具）' -ForegroundColor DarkYellow
        }

        # 随组件走、不可单独剔除的内容
        $mods = @($ComponentModules.Keys |
            Where-Object { $Components -contains $_ } |
            ForEach-Object { $ComponentModules[$_] })
        if ($mods) {
            Write-Host ''
            Write-Host '  随组件安装的 PowerShell 模块:' -ForegroundColor Yellow
            foreach ($m in $mods) { Write-Host "    · $m" }
        }
        $links = @($ManagedLinks | Where-Object { $Components -contains $_.Component })
        if ($links) {
            Write-Host ''
            Write-Host '  外部配置链接（你已有的配置优先，不会被覆盖）:' -ForegroundColor Yellow
            foreach ($l in $links) {
                $tgt = $l.Target `
                    -replace [regex]::Escape($env:APPDATA), '%APPDATA%' `
                    -replace [regex]::Escape($env:LOCALAPPDATA), '%LOCALAPPDATA%' `
                    -replace [regex]::Escape($HOME), '~'
                Write-Host ("    · {0} → {1}" -f $l.Source, $tgt)
            }
        }

        Write-Host ''
        $ans    = Read-Host '回车=开始安装 | 输入编号剔除/恢复单个工具（逗号分隔） | b=返回组件选择 | q=退出'
        $tokens = __WizardParseAnswer $ans
        if ($tokens -contains 'q') { return $null }
        if ($tokens -contains 'b') { return 'back' }
        if (-not $tokens)          { return 'confirm' }
        foreach ($t in $tokens) {
            __Toggle-ToggleToken -Token $t -Indexed @($flat) -NameProperty 'Name' -Toggles $Excluded -UnknownWarning '忽略无法识别的编号'
        }
    }
}

# 向导入口。返回 @{ Components; ExcludeTools }；$null 表示用户退出（调用方应中止安装）。
function Invoke-SetupWizard {
    param(
        [object[]]$Tools,
        [string[]]$DefaultComponents,
        [System.Collections.IDictionary]$ComponentModules
    )

    Show-WizardIntro

    # 外部配置清单（展示用；事实来源 Get-ManagedLinks.ps1）。
    # 仅在本函数内产生并向预览函数传递参数，不用 script 级变量（数据流单一路径）
    $managedLinks = @(. (Join-Path $PSScriptRoot 'Get-ManagedLinks.ps1') |
        Where-Object { -not $_.Core })

    $selected = @($DefaultComponents)
    $excluded = [System.Collections.Generic.List[string]]::new()
    while ($true) {
        $selected = Invoke-ComponentMenu -Selected $selected
        if ($null -eq $selected) { return $null }

        # 组件变更后，剔除名单里已不属于任何所选组件的条目清理掉
        $validNames = @($Tools |
            Where-Object { $selected -contains $_.Component } |
            ForEach-Object Name)
        for ($i = $excluded.Count - 1; $i -ge 0; $i--) {
            if ($excluded[$i] -notin $validNames) { $excluded.RemoveAt($i) }
        }

        while ($true) {
            $r = Invoke-InstallPreview -Components $selected -Tools $Tools -Excluded $excluded -ComponentModules $ComponentModules -ManagedLinks $managedLinks
            if ($null -eq $r)     { return $null }
            if ($r -eq 'confirm') { return @{ Components = @($selected); ExcludeTools = @($excluded) } }
            if ($r -eq 'back')    { break }   # 返回组件选择，保留已勾选状态
        }
    }
}
