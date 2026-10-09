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
#>
#Requires -Version 5.1
# 位置须在帮助块之后——放在首位会让 Get-Help / -? 读不到下面的帮助注释块
param(
    # 注册表路径（默认机器本地位置；测试时可指向临时文件）
    [string]$Registry = (Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json')
)

$repoDir = Split-Path $PSScriptRoot

# 注册表读写单源在 LinkRegistry.ps1（原子写）
. (Join-Path $PSScriptRoot 'LinkRegistry.ps1')

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
            'SymbolicLink' {
                # Get-Item -Force 拿断链对象；目录符号链接也必须按原类型恢复。
                $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
                $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\')
                if ($tgt) {
                    # Windows PowerShell 5.1 返回 String[]，取第一个目标再传给 GetFullPath。
                    $tgtTarget = @($tgt.Target) | Select-Object -First 1
                    if ($tgt.LinkType -eq 'SymbolicLink' -and $tgtTarget -and
                        ([System.IO.Path]::GetFullPath([string]$tgtTarget).TrimEnd('\') -ieq $srcFull)) { continue }
                    if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                        Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    }
                    else {
                        Remove-Item -LiteralPath $e.Target -Recurse -Force -ErrorAction Stop
                    }
                }
                try {
                    $null = New-Item -ItemType SymbolicLink -Path $e.Target -Target $src -ErrorAction Stop
                    Write-Host "已修复符号链接: $($e.Target)" -ForegroundColor Green
                }
                catch {
                    # 无权限建符号链接：按源类型降级，并更新注册表
                    if ($srcIsDir) {
                        Copy-Item -Path $src -Destination $e.Target -Recurse -Force -ErrorAction Stop
                        $copyType = 'CopyDirectory'
                    }
                    else {
                        Copy-Item -Path $src -Destination $e.Target -Force -ErrorAction Stop
                        $copyType = 'Copy'
                    }
                    Set-LinkRegistryEntry -Path $Registry -Target $e.Target -Source $src -LinkType $copyType
                    Write-Host "已降级为副本（符号链接不可用）: $($e.Target)" -ForegroundColor DarkYellow
                }
            }
            'Junction' {
                # Junction 只适用于目录；支持目标被删除、断链或指向错误目录时重建。
                if (-not $srcIsDir) {
                    Write-Warning "Junction 源不是目录，跳过: $src"
                    continue
                }
                $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
                $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\')
                if ($tgt) {
                    # Windows PowerShell 5.1 返回 String[]，取第一个目标再传给 GetFullPath。
                    $tgtTarget = @($tgt.Target) | Select-Object -First 1
                    if ($tgt.LinkType -eq 'Junction' -and $tgtTarget -and
                        ([System.IO.Path]::GetFullPath([string]$tgtTarget).TrimEnd('\') -ieq $srcFull)) { continue }
                    if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                        Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    }
                    else {
                        Remove-Item -LiteralPath $e.Target -Recurse -Force -ErrorAction Stop
                    }
                }
                try {
                    $null = New-Item -ItemType Junction -Path $e.Target -Target $src -ErrorAction Stop
                    Write-Host "已修复 Junction: $($e.Target)" -ForegroundColor Green
                }
                catch {
                    # Junction 不可用时降级为目录副本，并记住新类型
                    Copy-Item -Path $src -Destination $e.Target -Recurse -Force -ErrorAction Stop
                    Set-LinkRegistryEntry -Path $Registry -Target $e.Target -Source $src -LinkType 'CopyDirectory'
                    Write-Host "已降级为目录副本（Junction 不可用）: $($e.Target)" -ForegroundColor DarkYellow
                }
            }
            'HardLink' {
                # 已经是本仓库源的硬链接就无需重建
                if (__Test-IsHardLinkOf -Src $src -Target $e.Target) { continue }

                $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
                if ($tgt) {
                    if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                        Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    }
                    else {
                        Remove-Item -LiteralPath $e.Target -Recurse -Force -ErrorAction Stop
                    }
                }
                try {
                    $null = New-Item -ItemType HardLink -Path $e.Target -Target $src -ErrorAction Stop
                    Write-Host "已修复硬链接: $($e.Target)" -ForegroundColor Green
                }
                catch {
                    # 跨卷等场景 HardLink 不可用：降级 Copy 并更新注册表
                    Copy-Item -Path $src -Destination $e.Target -Force -ErrorAction Stop
                    Set-LinkRegistryEntry -Path $Registry -Target $e.Target -Source $src -LinkType 'Copy'
                    Write-Host "已降级为副本（硬链接不可用）: $($e.Target)" -ForegroundColor DarkYellow
                }
            }
            'Copy' {
                # 文件副本：内容有差异才刷新（psync 拉取后同步副本的通道）
                $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
                if ($tgt -and $tgt.LinkType) {
                    Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    $tgt = $null
                }
                elseif ($tgt -and $tgt.PSIsContainer) {
                    Remove-Item -LiteralPath $e.Target -Recurse -Force -ErrorAction Stop
                    $tgt = $null
                }
                if (-not $tgt) {
                    Copy-Item -Path $src -Destination $e.Target -Force -ErrorAction Stop
                    Write-Host "已恢复副本: $($e.Target)" -ForegroundColor Green
                    continue
                }
                if ((Get-FileHash $src -ErrorAction SilentlyContinue).Hash -ne
                    (Get-FileHash $e.Target -ErrorAction SilentlyContinue).Hash) {
                    Copy-Item -Path $src -Destination $e.Target -Force -ErrorAction Stop
                    Write-Host "已刷新副本: $($e.Target)" -ForegroundColor Green
                }
            }
            'CopyDirectory' {
                # 目录副本：先清理错误链接/文件，再用 robocopy /MIR 镜像同步。
                # 目标中源已删除的文件也会被清理；exit code 0-7 均为成功。
                $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
                if ($tgt -and $tgt.LinkType) {
                    Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    $tgt = $null
                }
                elseif ($tgt -and -not $tgt.PSIsContainer) {
                    Remove-Item -LiteralPath $e.Target -Force -ErrorAction Stop
                    $tgt = $null
                }
                if (-not $tgt) {
                    Copy-Item -Path $src -Destination $e.Target -Recurse -Force -ErrorAction Stop
                    Write-Host "已恢复目录副本: $($e.Target)" -ForegroundColor Green
                    continue
                }
                $null = robocopy $src $e.Target /MIR /NJH /NJS /NDL /NFL /NP
                if ($LASTEXITCODE -ge 8) {
                    Write-Warning "目录镜像同步失败（robocopy exit $LASTEXITCODE）: $($e.Target)"
                }
            }
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
