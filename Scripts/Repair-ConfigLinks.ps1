<#
.SYNOPSIS
    修复被 git / 原子保存编辑器弄断的配置链接，并刷新 Copy 降级副本。
.DESCRIPTION
    git pull/checkout 和多数编辑器的"写临时文件再替换"会以新 inode 替换仓库内
    文件，指向它的硬链接目标成为孤儿副本（目录类 Junction 不受影响）。
    注册表 %LOCALAPPDATA%\pwsh-profile\linked-targets.json 由 setup.ps1 建链时
    登记（Target/Source/LinkType 三元组），本脚本按登记的类型把目标恢复到仓库
    最新状态——SymbolicLink 重建符号链接、HardLink 重链、Copy 比较哈希后刷新
    副本、CopyDirectory 用 robocopy /MIR 镜像同步；未登记的目标（用户自有配置）
    永远不碰。修复类型不可用时降级为 Copy 并更新注册表（下次不再徒劳重试）。
    注册表 JSON 损坏时自动备份 .corrupt-<时间戳> 并按清单与磁盘状态重建。
    setup.ps1 建链后与 psync 拉取成功后自动调用。
    历史登记遇到普通目录或指向别处的有效链接时保留目标并告警；替换内容不同的
    普通文件前在同目录保留 .conflict-<时间戳>-<随机标识> 副本，备份失败则跳过该项。
#>
#Requires -Version 5.1
# 位置须在帮助块之后——放在首位会让 Get-Help / -? 读不到下面的帮助注释块
param(
    # 注册表路径（默认机器本地位置；测试时可指向临时文件）
    [string]$Registry = (Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json')
)

$repoDir = Split-Path $PSScriptRoot

# 注册表读写单源在 LinkRegistry.ps1（原子写；路径规范化的两个 helper 也在此）
. (Join-Path $PSScriptRoot 'LinkRegistry.ps1')

# 登记只能证明过去受管，不能证明后来放在同路径的个人配置仍属于仓库。
# 普通文件又可能是 git 原子替换留下的失联硬链接，先保留旧内容再重建。
function __Save-RepairConflict {
    param([Parameter(Mandatory)][string]$Target)
    $backup = "$Target.conflict-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N'))"
    Copy-Item -LiteralPath $Target -Destination $backup -ErrorAction Stop
    Write-Warning "原文件已保留到 $backup；确认内容后可手动归档或删除备份。"
}

function __Clear-RepairTarget {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Src
    )
    if ($Item.LinkType -in 'SymbolicLink', 'Junction') {
        $linkTarget = __Get-PrimaryLinkTarget $Item
        if ($linkTarget -and -not [IO.Path]::IsPathRooted($linkTarget)) {
            $linkTarget = Join-Path (Split-Path $Target) $linkTarget
        }
        if (-not $linkTarget -or ((Test-Path -LiteralPath $linkTarget) -and
            (__Get-NormalizedFullPath $linkTarget) -ine (__Get-NormalizedFullPath $Src))) {
            Write-Warning "保留配置冲突（有效链接指向别处或目标无法确认）: $Target。请先手动备份并移走目标，再重试修复。"
            return $false
        }
    }
    elseif ($Item.PSIsContainer) {
        Write-Warning "保留配置冲突（原链接已被普通目录替代）: $Target。请先手动备份并移走目录，再重试修复。"
        return $false
    }
    else {
        $sameContent = (Test-Path -LiteralPath $Src -PathType Leaf) -and
            (Get-FileHash -LiteralPath $Src -ErrorAction Stop).Hash -eq
            (Get-FileHash -LiteralPath $Target -ErrorAction Stop).Hash
        if (-not $sameContent) { __Save-RepairConflict -Target $Target }
    }
    Remove-Item -LiteralPath $Target -Force -ErrorAction Stop
    return $true
}

# 内部：刷新已登记的副本（Copy/CopyDirectory）。类型冲突先走保护分支，
# 目标丢失则按源类型恢复；仍在的目录用 robocopy /MIR 镜像
# （源已删除的文件也会被清理；exit code 0-7 均为成功），文件哈希有差异才刷新
# （psync 拉取后同步副本的通道）。
# 注：switch 的 case 条件写数组（'Copy','CopyDirectory'）不产生「任一匹配」
# 语义，实测永不命中——两类共用逻辑必须走函数调用，不能合进同一个 case 块。
function __Refresh-CopyEntry {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][ValidateSet('Copy', 'CopyDirectory')][string]$LinkType
    )
    $isDir = $LinkType -eq 'CopyDirectory'
    $tgt = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($tgt -and ($tgt.LinkType -or $tgt.PSIsContainer -ne $isDir)) {
        if (-not (__Clear-RepairTarget -Target $Target -Item $tgt -Src $Src)) { return }
        $tgt = $null
    }
    if (-not $tgt) {
        if ($isDir) {
            Copy-Item -Path $Src -Destination $Target -Recurse -Force -ErrorAction Stop
            Write-Host "已恢复目录副本: $Target" -ForegroundColor Green
        }
        else {
            Copy-Item -Path $Src -Destination $Target -Force -ErrorAction Stop
            Write-Host "已恢复副本: $Target" -ForegroundColor Green
        }
        return
    }
    if ($isDir) {
        $null = robocopy $Src $Target /MIR /NJH /NJS /NDL /NFL /NP
        if ($LASTEXITCODE -ge 8) {
            Write-Warning "目录镜像同步失败（robocopy exit $LASTEXITCODE）: $Target"
        }
    }
    elseif ((Get-FileHash -LiteralPath $Src -ErrorAction Stop).Hash -ne
        (Get-FileHash -LiteralPath $Target -ErrorAction Stop).Hash) {
        __Save-RepairConflict -Target $Target
        Copy-Item -Path $Src -Destination $Target -Force -ErrorAction Stop
        Write-Host "已刷新副本: $Target" -ForegroundColor Green
    }
}

# 内部：按登记类型重建链接。SymbolicLink/Junction/HardLink 的「已是正确链接则跳过
# → 处理目标冲突 → 重建 → 失败按源类型降级 Copy 并回写注册表」结构完全一致，
# 参数化单点维护——同一处逻辑写三遍，任何一处漏改都会造成类型间行为漂移。
# Junction 只适用于目录、HardLink 只适用于文件，降级 Copy/CopyDirectory 由源
# 类型天然决定，三分支得以共用同一段降级代码。
function __Repair-LinkOfType {
    param(
        [Parameter(Mandatory)][ValidateSet('SymbolicLink', 'Junction', 'HardLink')][string]$ItemType,
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Registry,
        [Parameter(Mandatory)][bool]$SrcIsDir
    )
    # Junction 源不是目录是登记数据异常，跳过不碰（不计入失败）
    if ($ItemType -eq 'Junction' -and -not $SrcIsDir) {
        Write-Warning "Junction 源不是目录，跳过: $Src"
        return
    }
    if ($ItemType -eq 'HardLink' -and (Test-Path -LiteralPath $Target) -and
        (__Test-IsHardLinkOf -Src $Src -Target $Target)) { return }

    $tgt = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if ($tgt) {
        # 已是本仓库源的同类型链接：无需重建
        if ($ItemType -in 'SymbolicLink', 'Junction') {
            $srcFull = __Get-NormalizedFullPath $Src
            $tgtTarget = __Get-PrimaryLinkTarget $tgt
            if ($tgt.LinkType -eq $ItemType -and $tgtTarget -and
                (__Get-NormalizedFullPath $tgtTarget) -ieq $srcFull) { return }
        }
        if (-not (__Clear-RepairTarget -Target $Target -Item $tgt -Src $Src)) { return }
    }
    try {
        $null = New-Item -ItemType $ItemType -Path $Target -Target $Src -ErrorAction Stop
        $labels = @{ SymbolicLink = '符号链接'; Junction = 'Junction'; HardLink = '硬链接' }
        Write-Host "已修复$($labels[$ItemType]): $Target" -ForegroundColor Green
    }
    catch {
        # 重建失败（无权限建符号链接、跨卷建硬链接等）：按源类型降级为副本并
        # 回写注册表，下次不再徒劳重试
        if ($SrcIsDir) {
            Copy-Item -Path $Src -Destination $Target -Recurse -Force -ErrorAction Stop
            $copyType = 'CopyDirectory'
        }
        else {
            Copy-Item -Path $Src -Destination $Target -Force -ErrorAction Stop
            $copyType = 'Copy'
        }
        Set-LinkRegistryEntry -Path $Registry -Target $Target -Source $Src -LinkType $copyType
        Write-Host "已降级为副本（$ItemType 不可用）: $Target" -ForegroundColor DarkYellow
    }
}

# ---- 读取注册表（损坏时备份重建） ----
# Restore-LinkRegistry：解析失败先备份 .corrupt-<时间戳>，再按清单与磁盘
# 状态重建（只认领有磁盘证据的符号链接/Junction/硬链接；Copy 类登记随损坏
# 丢失，由下次 setup 按未登记目标重新接管升级为链接，属预期行为）
$manifest = @(. (Join-Path $PSScriptRoot 'Get-ManagedLinks.ps1'))
$entries = @(Restore-LinkRegistry -Path $Registry -Manifest $manifest -RepoDir $repoDir)
if (-not $entries) { return }

$failed = @()
foreach ($e in $entries) {
    $src = $e.Source
    if (-not $src -or -not (Test-Path $src)) { continue }

    # 逐条隔离失败：调用方 setup.ps1 设了 $ErrorActionPreference = Stop 并以 &
    # 调用本脚本，此处任一 Remove/Copy 失败若不被捕获，会终止整个修复循环并连带
    # 中断 setup，留下"半修复"状态。变更类操作一律显式 -ErrorAction Stop，
    # 使失败在本条 catch 落下、其余条目照常处理。
    try {
        $srcIsDir = (Get-Item $src).PSIsContainer

        # 确保目标父目录存在（目标被整目录删除的场景）
        $parent = Split-Path $e.Target
        if ($parent -and -not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop | Out-Null
        }

        switch ($e.LinkType) {
            'SymbolicLink' { __Repair-LinkOfType -ItemType SymbolicLink -Src $src -Target $e.Target -Registry $Registry -SrcIsDir $srcIsDir }
            'Junction'     { __Repair-LinkOfType -ItemType Junction     -Src $src -Target $e.Target -Registry $Registry -SrcIsDir $srcIsDir }
            'HardLink'     { __Repair-LinkOfType -ItemType HardLink     -Src $src -Target $e.Target -Registry $Registry -SrcIsDir $srcIsDir }
            'Copy'          { __Refresh-CopyEntry -Src $src -Target $e.Target -LinkType 'Copy' }
            'CopyDirectory' { __Refresh-CopyEntry -Src $src -Target $e.Target -LinkType 'CopyDirectory' }
            default { continue }   # 未知类型不碰
        }
    }
    catch {
        $failed += $e.Target
        Write-Warning "链接修复失败（跳过该项，下次 setup/psync 重试）: $($e.Target) —— $($_.Exception.Message)"
    }
}

# 失败汇总：不改变退出语义（降级路径本就允许修复类型不可用），只保证
# 单条失败不再中断其余条目与调用方，同时把未修复项显式报出来
if ($failed.Count) {
    Write-Warning "本轮 $($entries.Count) 项中有 $($failed.Count) 项未能修复: $($failed -join '; ')"
}
