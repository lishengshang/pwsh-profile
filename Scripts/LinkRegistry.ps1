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
    try { return @(Get-Content $Path -Raw | ConvertFrom-Json) }
    catch { return @() }   # 损坏的 JSON 视为空，调用方按未登记处理
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
