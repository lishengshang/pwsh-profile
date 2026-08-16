#Requires -Version 7
<#
.SYNOPSIS
    修复被 git / 原子保存编辑器弄断的文件类配置硬链接。
.DESCRIPTION
    git pull/checkout 和多数编辑器的"写临时文件再替换"会以新 inode 替换仓库内
    文件，指向它的硬链接目标成为孤儿副本（目录类 Junction 不受影响）。
    本脚本根据机器本地注册表（%LOCALAPPDATA%\pwsh-profile\linked-targets.txt，
    由 setup.ps1 创建链接时登记）把登记过的文件目标强制重链到仓库文件——
    仓库即事实来源；未登记的目标（用户自有配置）永远不碰。
    setup.ps1 建链后与 psync 拉取成功后自动调用。
#>
$repoDir = Split-Path $PSScriptRoot
$registry = Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.txt'
if (-not (Test-Path $registry)) { return }
$tracked = Get-Content $registry -ErrorAction SilentlyContinue
if (-not $tracked) { return }

foreach ($item in (. (Join-Path $PSScriptRoot 'Get-ConfigLinks.ps1'))) {
    if ($tracked -notcontains $item.Target) { continue }
    $src = Join-Path $repoDir $item.Source
    if (-not (Test-Path $src)) { continue }
    if ((Get-Item $src).PSIsContainer) { continue }   # 目录用 Junction，无此问题

    # fsutil 列出目标文件的全部硬链接名（路径不带盘符），规范化后比对
    $srcNorm = ((Get-Item $src).FullName.TrimEnd('\')) -replace '^[A-Za-z]:', ''
    $links = (fsutil hardlink list $item.Target 2>$null) | ForEach-Object { ($_ -replace '^[A-Za-z]:', '').Trim() }
    if ($links -contains $srcNorm) { continue }

    if (Test-Path $item.Target) { Remove-Item $item.Target -Force }
    $parent = Split-Path $item.Target
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    try {
        $null = New-Item -ItemType HardLink -Path $item.Target -Target $src -ErrorAction Stop
        Write-Host "已修复硬链接: $($item.Target)" -ForegroundColor Green
    }
    catch {
        Copy-Item -Path $src -Destination $item.Target -Force
        Write-Host "已刷新副本（硬链接不可用）: $($item.Target)" -ForegroundColor DarkYellow
    }
}
