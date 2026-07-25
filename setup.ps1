#Requires -Version 7
<#
.SYNOPSIS
    安装 PowerShell profile 到当前用户的 PowerShell 配置目录。
.DESCRIPTION
    通过符号链接把仓库中的 profile 文件映射到 $PROFILE 所在目录。
    如果符号链接需要管理员权限且当前未开启，则自动回退到复制模式。
#>

$ErrorActionPreference = 'Stop'

$repoDir = $PSScriptRoot
$profileDir = Split-Path $PROFILE
$backupDir = Join-Path $profileDir "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# 需要映射的条目：源文件/目录（在仓库内） -> 目标路径（在 $profileDir 下）
$items = @(
    @{ Source = 'Microsoft.PowerShell_profile.ps1'; Target = $PROFILE }
    @{ Source = 'profile'; Target = Join-Path $profileDir 'profile' }
    @{ Source = 'Scripts'; Target = Join-Path $profileDir 'Scripts' }
    @{ Source = 'powershell.config.json'; Target = Join-Path $profileDir 'powershell.config.json' }
)

function Test-SymlinkAvailable {
    $tmp = [System.IO.Path]::GetTempFileName()
    $link = "$tmp-link"
    try {
        $null = New-Item -ItemType SymbolicLink -Path $link -Target $tmp -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Remove-Item $link -ErrorAction SilentlyContinue
    }
}

$useSymlink = Test-SymlinkAvailable
if (-not $useSymlink) {
    Write-Warning '当前环境不支持创建符号链接（需管理员权限或开启开发者模式），将使用复制模式。'
}

# 备份已存在的目标文件/目录
$needBackup = $items | Where-Object { Test-Path $_.Target }
if ($needBackup) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($item in $needBackup) {
        $name = Split-Path $item.Target -Leaf
        Move-Item -Path $item.Target -Destination (Join-Path $backupDir $name) -Force
        Write-Host "已备份: $($item.Target) -> $backupDir\$name" -ForegroundColor DarkYellow
    }
}

foreach ($item in $items) {
    $src = Join-Path $repoDir $item.Source
    if (-not (Test-Path $src)) {
        Write-Host "跳过（不存在）: $src" -ForegroundColor DarkGray
        continue
    }

    if (Test-Path $item.Target) {
        Remove-Item -Path $item.Target -Recurse -Force
    }

    $parent = Split-Path $item.Target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($useSymlink) {
        $linkType = if ((Get-Item $src).PSIsContainer) { 'SymbolicLink' } else { 'SymbolicLink' }
        $null = New-Item -ItemType $linkType -Path $item.Target -Target $src -Force
        Write-Host "已链接: $($item.Source) -> $($item.Target)" -ForegroundColor Green
    }
    else {
        if ((Get-Item $src).PSIsContainer) {
            Copy-Item -Path $src -Destination $item.Target -Recurse -Force
        }
        else {
            Copy-Item -Path $src -Destination $item.Target -Force
        }
        Write-Host "已复制: $($item.Source) -> $($item.Target)" -ForegroundColor Green
    }
}

Write-Host "`n安装完成。请重新打开 PowerShell 或执行 `. `$PROFILE` 加载配置。" -ForegroundColor Cyan
if ($needBackup) {
    Write-Host "原配置已备份到: $backupDir" -ForegroundColor Cyan
}
