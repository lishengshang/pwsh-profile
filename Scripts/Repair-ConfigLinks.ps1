#Requires -Version 5.1
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
    旧版 linked-targets.txt（仅路径）首次运行时自动迁移为 JSON。
    setup.ps1 建链后与 psync 拉取成功后自动调用。
#>
param(
    # 注册表路径（默认机器本地位置；测试时可指向临时文件）
    [string]$Registry = (Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json')
)

$repoDir = Split-Path $PSScriptRoot
$legacyTxt = Join-Path (Split-Path $Registry) 'linked-targets.txt'

# 注册表读写单源在 LinkRegistry.ps1（原子写）
. (Join-Path $PSScriptRoot 'LinkRegistry.ps1')

# ---- 读取注册表（旧 txt 自动迁移） ----
$entries = @(Get-LinkRegistryEntries $Registry)
if (-not $entries -and (Test-Path $legacyTxt)) {
    # 旧格式只有 Target 路径：Source 从清单推断；类型按实际状态判断——
    # LinkType 属性（符号链接/Junction）、fsutil 确认 HardLink 关系，
    # 都不是则普通文件按 Copy、普通目录按 CopyDirectory（宁降级勿误判）
    $manifest = @(. (Join-Path $PSScriptRoot 'Get-ManagedLinks.ps1'))
    foreach ($t in (Get-Content $legacyTxt -ErrorAction SilentlyContinue)) {
        if (-not $t) { continue }
        $m = $manifest | Where-Object { $_.Target -ieq $t }
        if (-not $m) { continue }   # 清单中已不存在的旧条目，放弃迁移
        $src = Join-Path $repoDir $m.Source
        $item = Get-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
        $type = $item.LinkType
        if (-not $type -and $item) {
            if ($item.PSIsContainer) {
                $type = 'CopyDirectory'
            }
            else {
                $srcNorm = ((Get-Item $src).FullName.TrimEnd('\')) -replace '^[A-Za-z]:', ''
                $links = (fsutil hardlink list $t 2>$null) |
                    ForEach-Object { ($_ -replace '^[A-Za-z]:', '').Trim() }
                $type = if ($links -contains $srcNorm) { 'HardLink' } else { 'Copy' }
            }
        }
        $entries += [pscustomobject]@{ Target = $t; Source = $src; LinkType = $type }
    }
    Save-LinkRegistryEntries -Path $Registry -Entries $entries
    Remove-Item $legacyTxt -Force -ErrorAction SilentlyContinue
}
if (-not $entries) { return }

foreach ($e in $entries) {
    $src = $e.Source
    if (-not $src -or -not (Test-Path $src)) { continue }
    $srcIsDir = (Get-Item $src).PSIsContainer

    # 确保目标父目录存在（目标被整目录删除的场景）
    $parent = Split-Path $e.Target
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    switch ($e.LinkType) {
        'SymbolicLink' {
            # Get-Item -Force 拿断链对象；目录符号链接也必须按原类型恢复。
            $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
            $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\')
            if ($tgt) {
                if ($tgt.LinkType -eq 'SymbolicLink' -and $tgt.Target -and
                    ([System.IO.Path]::GetFullPath($tgt.Target).TrimEnd('\') -ieq $srcFull)) { continue }
                if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                    Remove-Item -LiteralPath $e.Target -Force
                }
                else {
                    Remove-Item -LiteralPath $e.Target -Recurse -Force
                }
            }
            try {
                $null = New-Item -ItemType SymbolicLink -Path $e.Target -Target $src -ErrorAction Stop
                Write-Host "已修复符号链接: $($e.Target)" -ForegroundColor Green
            }
            catch {
                # 无权限建符号链接：按源类型降级，并更新注册表
                if ($srcIsDir) {
                    Copy-Item -Path $src -Destination $e.Target -Recurse -Force
                    $copyType = 'CopyDirectory'
                }
                else {
                    Copy-Item -Path $src -Destination $e.Target -Force
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
                if ($tgt.LinkType -eq 'Junction' -and $tgt.Target -and
                    ([System.IO.Path]::GetFullPath($tgt.Target).TrimEnd('\') -ieq $srcFull)) { continue }
                if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                    Remove-Item -LiteralPath $e.Target -Force
                }
                else {
                    Remove-Item -LiteralPath $e.Target -Recurse -Force
                }
            }
            try {
                $null = New-Item -ItemType Junction -Path $e.Target -Target $src -ErrorAction Stop
                Write-Host "已修复 Junction: $($e.Target)" -ForegroundColor Green
            }
            catch {
                # Junction 不可用时降级为目录副本，并记住新类型
                Copy-Item -Path $src -Destination $e.Target -Recurse -Force
                Set-LinkRegistryEntry -Path $Registry -Target $e.Target -Source $src -LinkType 'CopyDirectory'
                Write-Host "已降级为目录副本（Junction 不可用）: $($e.Target)" -ForegroundColor DarkYellow
            }
        }
        'HardLink' {
            # fsutil 列出目标文件的全部硬链接名（路径不带盘符），规范化后比对
            $srcNorm = ((Get-Item $src).FullName.TrimEnd('\')) -replace '^[A-Za-z]:', ''
            $links = (fsutil hardlink list $e.Target 2>$null) |
                ForEach-Object { ($_ -replace '^[A-Za-z]:', '').Trim() }
            if ($links -contains $srcNorm) { continue }

            $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
            if ($tgt) {
                if ($tgt.LinkType -or -not $tgt.PSIsContainer) {
                    Remove-Item -LiteralPath $e.Target -Force
                }
                else {
                    Remove-Item -LiteralPath $e.Target -Recurse -Force
                }
            }
            try {
                $null = New-Item -ItemType HardLink -Path $e.Target -Target $src -ErrorAction Stop
                Write-Host "已修复硬链接: $($e.Target)" -ForegroundColor Green
            }
            catch {
                # 跨卷等场景 HardLink 不可用：降级 Copy 并更新注册表
                Copy-Item -Path $src -Destination $e.Target -Force
                Set-LinkRegistryEntry -Path $Registry -Target $e.Target -Source $src -LinkType 'Copy'
                Write-Host "已降级为副本（硬链接不可用）: $($e.Target)" -ForegroundColor DarkYellow
            }
        }
        'Copy' {
            # 文件副本：内容有差异才刷新（psync 拉取后同步副本的通道）
            $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
            if ($tgt -and $tgt.LinkType) {
                Remove-Item -LiteralPath $e.Target -Force
                $tgt = $null
            }
            elseif ($tgt -and $tgt.PSIsContainer) {
                Remove-Item -LiteralPath $e.Target -Recurse -Force
                $tgt = $null
            }
            if (-not $tgt) {
                Copy-Item -Path $src -Destination $e.Target -Force
                Write-Host "已恢复副本: $($e.Target)" -ForegroundColor Green
                continue
            }
            if ((Get-FileHash $src -ErrorAction SilentlyContinue).Hash -ne
                (Get-FileHash $e.Target -ErrorAction SilentlyContinue).Hash) {
                Copy-Item -Path $src -Destination $e.Target -Force
                Write-Host "已刷新副本: $($e.Target)" -ForegroundColor Green
            }
        }
        'CopyDirectory' {
            # 目录副本：先清理错误链接/文件，再用 robocopy /MIR 镜像同步。
            # 目标中源已删除的文件也会被清理；exit code 0-7 均为成功。
            $tgt = Get-Item -LiteralPath $e.Target -Force -ErrorAction SilentlyContinue
            if ($tgt -and $tgt.LinkType) {
                Remove-Item -LiteralPath $e.Target -Force
                $tgt = $null
            }
            elseif ($tgt -and -not $tgt.PSIsContainer) {
                Remove-Item -LiteralPath $e.Target -Force
                $tgt = $null
            }
            if (-not $tgt) {
                Copy-Item -Path $src -Destination $e.Target -Recurse -Force
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
