# ==============================================================
# 链接注册表读写（setup.ps1 与 Repair-ConfigLinks.ps1 共用）
# 注册表 %LOCALAPPDATA%\pwsh-profile\linked-targets.json 记录
# Target/Source/LinkType 三元组（LinkType: SymbolicLink / Junction /
# HardLink / Copy / CopyDirectory）。写入原子（tmp + Move），并发 setup 至多
# 丢一次登记、不会产生损坏 JSON。
# ==============================================================

function Get-LinkRegistryEntries {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try {
        $raw = Get-Content $Path -Raw | ConvertFrom-Json
        # Windows PowerShell 5.1 读取顶层 JSON 数组时，可能把每个属性合并成数组，
        # 而不是返回对象数组；这里显式展开，避免 Target/Source/LinkType 变成数组。
        if ($raw -and $raw.Target -is [array]) {
            $items = @()
            $targets = @($raw.Target)
            $sources = @($raw.Source)
            $types = @($raw.LinkType)
            for ($i = 0; $i -lt $targets.Count; $i++) {
                $items += [pscustomobject]@{
                    Target = [string]$targets[$i]
                    Source = [string]$sources[$i]
                    LinkType = [string]$types[$i]
                }
            }
            return $items
        }
        return @($raw)
    }
    catch { return @() }   # 损坏的 JSON 视为空，调用方按未登记处理
}

# 旧版 linked-targets.txt（仅 Target 路径）→ JSON 条目数组的纯转换：
# Source 从 manifest 推断；类型按磁盘实际状态判断——LinkType 属性
# （符号链接/Junction）、fsutil 确认 HardLink 关系，都不是则普通文件按
# Copy、普通目录按 CopyDirectory（宁降级勿误判）。不落盘不删 txt，
# 由调用方决定 Save 与删除时机。
function ConvertFrom-LegacyLinkRegistry {
    param(
        [Parameter(Mandatory)][string]$LegacyTxt,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RepoDir
    )
    $entries = @()
    foreach ($t in (Get-Content $LegacyTxt -ErrorAction SilentlyContinue)) {
        if (-not $t) { continue }
        $m = $Manifest | Where-Object { $_.Target -ieq $t }
        if (-not $m) { continue }   # 清单中已不存在的旧条目，放弃迁移
        $src = Join-Path $RepoDir $m.Source
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
    return $entries
}

function Save-LinkRegistryEntries {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Entries
    )
    try {
        $dir = Split-Path $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $tmp = "$Path.tmp"
        # -InputObject 保证单元素也输出 JSON 数组
        ConvertTo-Json -InputObject @($Entries) -Depth 3 | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Path $tmp -Destination $Path -Force
    }
    catch {
        # 注册表是 Repair 的增强依据，写入失败（权限/磁盘/并发占用）不应中断
        # setup 主流程，只警告；旧注册表保持原样
        Write-Warning "链接注册表写入失败: $($_.Exception.Message)"
    }
}

function Set-LinkRegistryEntry {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$LinkType
    )
    # 同目标先删旧记录再追加，保证最新类型生效（HardLink 降级 Copy 时复写）
    $entries = @(Get-LinkRegistryEntries $Path) | Where-Object { $_.Target -ne $Target }
    $entries = @($entries) + [pscustomobject]@{ Target = $Target; Source = $Source; LinkType = $LinkType }
    Save-LinkRegistryEntries -Path $Path -Entries $entries
}

# 判定目标是否已由本仓库管理（幂等跳过的依据）。返回 @{ IsManaged; LinkType }：
#   SymbolicLink/Junction -> Target 属性指向仓库源
#   HardLink              -> fsutil 同 inode 路径包含仓库源
#   Copy / CopyDirectory  -> 仅当注册表已登记为该类型且 Source 匹配
#                            （普通文件再比哈希；内容恰好相同的独立文件不算——
#                            Hash 相同 ≠ 受本项目管理，避免误跳过建链）
function Get-ManagedLinkState ([string]$src, [string]$target, [string]$RegistryPath) {
    $tgt = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if (-not $tgt) { return @{ IsManaged = $false; LinkType = $null } }
    $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\')
    if ($tgt.LinkType -in 'SymbolicLink', 'Junction') {
        # Windows PowerShell 5.1 返回 String[]，取第一个目标再传给 GetFullPath。
        $tgtTarget = @($tgt.Target) | Select-Object -First 1
        if ($tgtTarget -and ([System.IO.Path]::GetFullPath([string]$tgtTarget).TrimEnd('\') -ieq $srcFull)) {
            return @{ IsManaged = $true; LinkType = $tgt.LinkType }
        }
        return @{ IsManaged = $false; LinkType = $null }
    }
    $entry = @(Get-LinkRegistryEntries $RegistryPath) |
        Where-Object { $_.Target -ieq $target } | Select-Object -First 1
    if ($tgt.PSIsContainer) {
        # 目录仅认可登记过的 CopyDirectory（Junction/SymbolicLink 已在上面处理）
        if ($entry -and $entry.LinkType -eq 'CopyDirectory' -and
            (([System.IO.Path]::GetFullPath($entry.Source).TrimEnd('\')) -ieq $srcFull)) {
            return @{ IsManaged = $true; LinkType = 'CopyDirectory' }
        }
        return @{ IsManaged = $false; LinkType = $null }
    }
    # 文件：先查 HardLink 关系（fsutil 输出同 inode 全部路径，不带盘符）
    $srcNorm = ($srcFull -replace '^[A-Za-z]:', '').ToLowerInvariant()
    $links = (fsutil hardlink list $target 2>$null) |
        ForEach-Object { (($_ -replace '^[A-Za-z]:', '').TrimEnd('\')).ToLowerInvariant() }
    if ($links -contains $srcNorm) { return @{ IsManaged = $true; LinkType = 'HardLink' } }
    # 普通文件：注册表登记为 Copy 且 Source 匹配时，内容一致才算管理
    if ($entry -and $entry.LinkType -eq 'Copy' -and
        (([System.IO.Path]::GetFullPath($entry.Source).TrimEnd('\')) -ieq $srcFull)) {
        if ((Get-FileHash $src -ErrorAction SilentlyContinue).Hash -eq
            (Get-FileHash $target -ErrorAction SilentlyContinue).Hash) {
            return @{ IsManaged = $true; LinkType = 'Copy' }
        }
    }
    return @{ IsManaged = $false; LinkType = $null }
}
