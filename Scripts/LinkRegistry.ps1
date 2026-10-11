# ==============================================================
# 链接注册表读写（setup.ps1 与 Repair-ConfigLinks.ps1 共用）
# %LOCALAPPDATA%\pwsh-profile\linked-targets.json 记录 Target/Source/LinkType
# 三元组。写入原子（tmp + Move）；读改写经命名 Mutex 串行，setup 与 Repair 并发
# 登记不再互相覆盖；JSON 损坏时 Restore-LinkRegistry 备份 .corrupt-<时间戳> 后
# 按清单与磁盘状态重建。
# 下方 __ 前缀函数中，__Test-IsHardLinkOf 与两个路径 helper 也被
# Repair-ConfigLinks.ps1 / Deploy-ConfigLinks.ps1 跨文件调用（片段无独立作用域）。
# ==============================================================

# 内部：路径规范化（GetFullPath + 去尾分隔符）。链接两侧比对统一走这里，
# 保证「去尾反斜杠」规则单点维护。
function __Get-NormalizedFullPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

# 内部：取链接对象的第一个目标路径。Windows PowerShell 5.1 的 .Target 返回
# String[]，直接当字符串用会依赖隐式数组拼接，统一在此取第一个并转 string。
function __Get-PrimaryLinkTarget {
    param([Parameter(Mandatory)][AllowNull()]$Item)
    return [string](@($Item.Target) | Select-Object -First 1)
}

# 内部：注册表 JSON 文本 → 条目数组。解析失败抛异常（调用方决定视为空还是自愈）。
# 5.1 读顶层 JSON 数组会把属性合并成数组而非对象数组，需显式展开。
function __ConvertFrom-RegistryJson {
    param([Parameter(Mandatory)][string]$Json)
    $raw = $Json | ConvertFrom-Json
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

function Get-LinkRegistryEntries {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try { return __ConvertFrom-RegistryJson (Get-Content $Path -Raw) }
    catch { return @() }   # 损坏的 JSON 视为空，按未登记处理（自愈走 Restore-LinkRegistry）
}

# 内部：命名 Mutex 串行化注册表读改写。Global 命名空间跨会话互斥；创建失败或
# 等待超时降级为不加锁继续（注册表只是 Repair 的增强依据，宁丢一次登记不阻塞主流程）。
# AbandonedMutex（持锁进程异常退出）按已获得处理。
function __Invoke-WithLinkRegistryLock {
    param(
        [Parameter(Mandatory)][scriptblock]$Body,
        [int]$TimeoutMs = 10000
    )
    $mtx = $null
    $locked = $false
    try {
        try { $mtx = [System.Threading.Mutex]::new($false, 'Global\pwsh-profile-linkregistry') }
        catch {
            $mtx = $null
            Write-Warning "链接注册表锁创建失败（不加锁继续）: $($_.Exception.Message)"
        }
        if ($mtx) {
            try { $locked = $mtx.WaitOne($TimeoutMs) }
            catch [System.Threading.AbandonedMutexException] { $locked = $true }
            if (-not $locked) {
                Write-Warning "链接注册表锁等待超时（${TimeoutMs}ms），不加锁继续——并发登记可能互相覆盖"
            }
        }
        & $Body
    }
    finally {
        if ($mtx) {
            if ($locked) { $null = $mtx.ReleaseMutex() }
            $mtx.Dispose()
        }
    }
}

# 内部：fsutil 判断两个路径是否指向同一 inode（硬链接）。fsutil 输出的路径不带
# 盘符，两侧统一「去盘符 + 去尾分隔符 + 降大小写」后比对。源路径用 GetFullPath
# 而非 Get-Item——后者在源文件已不存在时会报错，而这里只需要字面路径。
# fsutil 不可用（非 NTFS、权限、目标不存在）时返回 $false，由调用方走降级分支。
function __Test-IsHardLinkOf {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target
    )
    $srcFull = __Get-NormalizedFullPath $Src
    $srcNorm = ($srcFull -replace '^[A-Za-z]:', '').ToLowerInvariant()
    $links = @()
    try {
        $links = @(fsutil hardlink list $Target 2>$null) |
            ForEach-Object { (($_ -replace '^[A-Za-z]:', '').TrimEnd('\')).ToLowerInvariant() }
    }
    catch {
        $links = @()   # 按「无硬链接证据」处理
    }
    return ($links -contains $srcNorm)
}

# 内部：按磁盘状态严格认领受管链接类型——只认有证据的 SymbolicLink/Junction
# （且指向仓库源）与 HardLink（fsutil 同 inode）；普通文件/目录返回 $null 不认领
# （内容相同 ≠ 受本项目管理），交给 setup 下次部署按「未登记」重新接管。
function __Get-ManagedLinkTypeFromDisk {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target
    )
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if (-not $item) { return $null }
    $srcFull = __Get-NormalizedFullPath $Src
    if ($item.LinkType -in 'SymbolicLink', 'Junction') {
        $tgtTarget = __Get-PrimaryLinkTarget $item
        if ($tgtTarget -and (__Get-NormalizedFullPath $tgtTarget) -ieq $srcFull) {
            return $item.LinkType
        }
        return $null
    }
    if ($item.PSIsContainer) { return $null }
    if (__Test-IsHardLinkOf -Src $Src -Target $Target) { return 'HardLink' }
    return $null
}

# 注册表自愈入口（Repair-ConfigLinks.ps1 调用）：正常时原样返回、不落盘；解析失败
# 先备份 .corrupt-<时间戳>，锁内重读仍失败则按清单与磁盘状态重建。重建只认领有磁盘
# 证据的链接，Copy 登记随之丢失、由下次 setup 重新接管，属预期行为。
function Restore-LinkRegistry {
    # 参数在传入 __Invoke-WithLinkRegistryLock 的脚本块内使用，规则不追踪脚本块
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Manifest', Justification = '脚本块内使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepoDir', Justification = '脚本块内使用')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RepoDir
    )
    if (-not (Test-Path $Path)) { return @() }
    try { return __ConvertFrom-RegistryJson (Get-Content $Path -Raw) }
    catch { Write-Debug ("首次解析失败，进入自愈: " + $_.Exception.Message) }
    return __Invoke-WithLinkRegistryLock -Body {
        # 锁内重读：并发进程可能已修复
        try { return __ConvertFrom-RegistryJson (Get-Content $Path -Raw) }
        catch { Write-Debug "锁内重读仍损坏: $($_.Exception.Message)" }
        $corrupt = "$Path.corrupt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $Path -Destination $corrupt -Force
        Write-Warning "链接注册表损坏，已备份到 $corrupt，正按清单与磁盘状态重建"
        $entries = @()
        foreach ($m in $Manifest) {
            if (-not $m.Target -or -not $m.Source) { continue }
            $src = Join-Path $RepoDir $m.Source
            $type = __Get-ManagedLinkTypeFromDisk -Src $src -Target $m.Target
            if ($type) {
                $entries += [pscustomobject]@{
                    Target   = (Get-Item -LiteralPath $m.Target -Force).FullName
                    Source   = $src
                    LinkType = $type
                }
            }
        }
        Save-LinkRegistryEntries -Path $Path -Entries $entries
        return $entries
    }
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
    # 参数在传入 __Invoke-WithLinkRegistryLock 的脚本块内使用，规则不追踪脚本块
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Path', Justification = '脚本块内使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Target', Justification = '脚本块内使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Source', Justification = '脚本块内使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'LinkType', Justification = '脚本块内使用')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$LinkType
    )
    # 读改写全程持锁（setup 与 Repair 并发登记经命名 Mutex 串行，不再互相
    # 覆盖；超时/创建失败降级为不加锁继续）。同目标先删旧记录再追加，
    # 保证最新类型生效（HardLink 降级 Copy 时复写）
    __Invoke-WithLinkRegistryLock -Body {
        $entries = @(Get-LinkRegistryEntries $Path) | Where-Object { $_.Target -ne $Target }
        $entries = @($entries) + [pscustomobject]@{ Target = $Target; Source = $Source; LinkType = $LinkType }
        Save-LinkRegistryEntries -Path $Path -Entries $entries
    }
}

# 判定目标是否已由本仓库管理（幂等跳过的依据），返回 @{ IsManaged; LinkType }：
# 先认磁盘证据，再退到登记过的副本。
function Get-ManagedLinkState {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RegistryPath
    )
    # 磁盘证据优先，判定单源在 __Get-ManagedLinkTypeFromDisk（符号链接指向仓库源、
    # fsutil 同 inode）
    $diskType = __Get-ManagedLinkTypeFromDisk -Src $Src -Target $Target
    if ($diskType) { return @{ IsManaged = $true; LinkType = $diskType } }
    $tgt = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
    if (-not $tgt) { return @{ IsManaged = $false; LinkType = $null } }
    # 有链接属性却不指向仓库源 = 用户自己的链接，绝不按登记信息接管
    if ($tgt.LinkType -in 'SymbolicLink', 'Junction') { return @{ IsManaged = $false; LinkType = $null } }
    $srcFull = __Get-NormalizedFullPath $Src
    $entry = @(Get-LinkRegistryEntries $RegistryPath) |
        Where-Object { $_.Target -ieq $Target } | Select-Object -First 1
    # 无链接关系时只认登记过的副本：目录 CopyDirectory；文件 Copy 还要求内容一致
    # （哈希相同 ≠ 受管理，必须登记过才算，否则会误跳过建链）
    if ($entry -and (__Get-NormalizedFullPath $entry.Source) -ieq $srcFull) {
        if ($tgt.PSIsContainer) {
            if ($entry.LinkType -eq 'CopyDirectory') { return @{ IsManaged = $true; LinkType = 'CopyDirectory' } }
        }
        elseif ($entry.LinkType -eq 'Copy') {
            if ((Get-FileHash $Src -ErrorAction SilentlyContinue).Hash -eq
                (Get-FileHash $Target -ErrorAction SilentlyContinue).Hash) {
                return @{ IsManaged = $true; LinkType = 'Copy' }
            }
        }
    }
    return @{ IsManaged = $false; LinkType = $null }
}
