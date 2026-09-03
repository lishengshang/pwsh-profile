#Requires -Version 5.1
# ==============================================================
# 配置链接部署（从 setup.ps1 提取的可测试单元）
# 依赖 LinkRegistry.ps1 已先行加载（Get-LinkRegistryEntries /
# Set-LinkRegistryEntry / Get-ManagedLinkState）。
# -NoSymlink 供测试注入：强制走无符号链接权限的回退链
# （Junction / HardLink / Copy），覆盖非管理员环境的部署路径。
# ==============================================================

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

function Invoke-ConfigLinkDeployment {
    param(
        # Get-ManagedLinks 条目（调用方已按组件过滤）
        [Parameter(Mandatory)]$Items,
        [Parameter(Mandatory)][string]$RepoDir,
        # 链接注册表 JSON 路径
        [Parameter(Mandatory)][string]$RegistryPath,
        # 备份目录根（backup-<时间戳> 创建在这里）
        [Parameter(Mandatory)][string]$BackupRoot,
        # 测试注入：强制视为无符号链接权限（输出原有警告并走回退链）
        [switch]$NoSymlink
    )

    $useSymlink = -not $NoSymlink -and (Test-SymlinkAvailable)
    if (-not $useSymlink) {
        Write-Warning '当前环境不支持符号链接（需管理员权限或开发者模式），目录将回退 Junction、文件回退 HardLink，仍失败才复制。'
    }

    $backupDir = Join-Path $BackupRoot "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    $backupCreated = $false
    $copyDeployed = $false
    foreach ($item in $Items) {
        $src = Join-Path $RepoDir $item.Source
        if (-not (Test-Path $src)) {
            Write-Host "跳过（不存在）: $src" -ForegroundColor DarkGray
            continue
        }

        # 幂等：目标已是受管链接/副本时跳过，并补登记（注册表丢失/手工建的正确
        # 链接也能恢复 Repair 的修复能力）
        $state = Get-ManagedLinkState $src $item.Target $RegistryPath
        if ($state.IsManaged) {
            Write-Host "已是正确链接，跳过: $($item.Target)" -ForegroundColor DarkGray
            Set-LinkRegistryEntry -Path $RegistryPath -Target $item.Target -Source $src -LinkType $state.LinkType
            continue
        }

        # Get-Item -Force 能拿到断链对象（指向已不存在目标的符号链接/Junction，
        # Test-Path 对断链文件返回 False 但对象仍占用路径，不清理则 New-Item 失败）
        $existing = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
        if ($existing) {
            if ($item.SkipIfExists) {
                Write-Host "已存在，跳过: $($item.Target)" -ForegroundColor DarkGray
                continue
            }
            $isBrokenLink = $existing.LinkType -and -not (Test-Path -LiteralPath $item.Target)
            if ($isBrokenLink) {
                # 断链对象不含用户可读数据，直接清理后重建
                Remove-Item -LiteralPath $item.Target -Force
                Write-Host "已清理失效链接: $($item.Target)" -ForegroundColor DarkGray
            }
            else {
                # 普通文件/目录，或指向别处的有效链接：均视为用户现有配置，先备份
                if (-not $backupCreated) {
                    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                    $backupCreated = $true
                }
                $name = Split-Path $item.Target -Leaf
                Move-Item -LiteralPath $item.Target -Destination (Join-Path $backupDir $name) -Force
                Write-Host "已备份: $($item.Target) -> $backupDir\$name" -ForegroundColor DarkYellow
            }
        }

        $parent = Split-Path $item.Target
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        if ($useSymlink) {
            $null = New-Item -ItemType SymbolicLink -Path $item.Target -Target $src -Force
            Write-Host "已链接: $($item.Source) -> $($item.Target)" -ForegroundColor Green
            Set-LinkRegistryEntry -Path $RegistryPath -Target $item.Target -Source $src -LinkType 'SymbolicLink'
        }
        else {
            # 无符号链接权限时的回退：目录用 Junction、文件用 HardLink（均无需特权，
            # 且和符号链接一样「仓库即实体」，保证改仓库文件即刻生效、不产生两份副本）
            $isDir = (Get-Item $src).PSIsContainer
            $linked = $false
            if ($isDir) {
                try {
                    $null = New-Item -ItemType Junction -Path $item.Target -Target $src -ErrorAction Stop
                    $linked = $true
                } catch { }
            }
            else {
                try {
                    $null = New-Item -ItemType HardLink -Path $item.Target -Target $src -ErrorAction Stop
                    $linked = $true
                } catch { }
            }
            if ($linked) {
                $linkType = if ($isDir) { 'Junction' } else { 'HardLink' }
                Write-Host "已链接($($(if ($isDir) {'junction'} else {'hardlink'}))): $($item.Source) -> $($item.Target)" -ForegroundColor Green
                Set-LinkRegistryEntry -Path $RegistryPath -Target $item.Target -Source $src -LinkType $linkType
                continue
            }
            # 最终回退：Copy 模式（不实时同步；文件由 Repair 按哈希刷新、
            # 目录由 Repair 用 robocopy 镜像同步，psync 拉取后自动对齐）
            if ((Get-Item $src).PSIsContainer) {
                Copy-Item -Path $src -Destination $item.Target -Recurse -Force
                Set-LinkRegistryEntry -Path $RegistryPath -Target $item.Target -Source $src -LinkType 'CopyDirectory'
            }
            else {
                Copy-Item -Path $src -Destination $item.Target -Force
                Set-LinkRegistryEntry -Path $RegistryPath -Target $item.Target -Source $src -LinkType 'Copy'
            }
            $copyDeployed = $true
            Write-Host "已复制: $($item.Source) -> $($item.Target)" -ForegroundColor Green
        }
    }

    return @{
        BackupCreated = $backupCreated
        CopyDeployed  = $copyDeployed
        BackupDir     = $backupDir
    }
}
