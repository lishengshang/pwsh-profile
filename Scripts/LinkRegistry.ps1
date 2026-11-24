# ==============================================================
# 链接注册表读写（setup.ps1 与 Repair-ConfigLinks.ps1 共用）
# %LOCALAPPDATA%\pwsh-profile\linked-targets.json 记录 Target/Source/LinkType
# 三元组。命名 Mutex 串行登记与自愈，更新时在同一目录写临时文件再替换。
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

# 兼容旧的并列数组格式，校验结构后才允许更新登记。
function __ConvertFrom-RegistryJson {
    param([Parameter(Mandatory)][string]$Json)
    $raw = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    if ($null -eq $raw -and $Json -match '^\s*\[\s*\]\s*$') { return @() }

    $entries = @($raw)
    # 5.1 会枚举对象数组的 Target 属性，不能把它误当成旧版的并列字段数组。
    if ($raw -isnot [array] -and $raw -is [pscustomobject] -and $raw.Target -is [array]) {
        if ($raw.Source -isnot [array] -or $raw.LinkType -isnot [array] -or
            $raw.Target.Count -ne $raw.Source.Count -or $raw.Target.Count -ne $raw.LinkType.Count) {
            throw '链接注册表的旧版字段数组长度不一致。'
        }
        $entries = @(for ($i = 0; $i -lt $raw.Target.Count; $i++) {
            [pscustomobject]@{ Target = $raw.Target[$i]; Source = $raw.Source[$i]; LinkType = $raw.LinkType[$i] }
        })
    }
    foreach ($entry in $entries) {
        if ($entry.Target -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Target) -or
            $entry.Source -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Source) -or
            $entry.LinkType -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.LinkType)) {
            throw '链接注册表条目缺少有效的 Target、Source 或 LinkType。'
        }
    }
    return $entries
}

function __Read-LinkRegistryText {
    param([Parameter(Mandatory)][string]$Path)
    $filePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    try { return [IO.File]::ReadAllText($filePath) }
    catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { return $null }
}

function __Read-LinkRegistryEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '读取登记条目集合，复数语义正确')]
    param([Parameter(Mandatory)][string]$Path)
    $json = __Read-LinkRegistryText $Path
    if ($null -eq $json) { return @() }
    return __ConvertFrom-RegistryJson $json
}

function Get-LinkRegistryEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '返回登记条目集合，复数语义正确')]
    param([Parameter(Mandatory)][string]$Path)
    try { return __Read-LinkRegistryEntries $Path }
    catch { return @() }   # 只读探测允许降级，写入必须使用严格读取
}

# Global 命名空间跨会话互斥，不能加锁时宁可推迟登记也不覆盖其他进程的写入。
function __Invoke-WithLinkRegistryLock {
    param(
        [Parameter(Mandatory)][scriptblock]$Body,
        [int]$TimeoutMs = 10000
    )
    $mtx = $null
    $locked = $false
    try {
        try {
            $mtx = [System.Threading.Mutex]::new($false, 'Global\pwsh-profile-linkregistry')
            $locked = $mtx.WaitOne($TimeoutMs)
        }
        catch [System.Threading.AbandonedMutexException] { $locked = $true }
        catch {
            Write-Warning "无法获取链接注册表锁，已跳过写入: $($_.Exception.Message)"
            return
        }
        if (-not $locked) {
            Write-Warning "链接注册表锁等待超时（${TimeoutMs}ms），已跳过写入。"
            return
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

function __Get-ManagedFileIdentity {
    param([Parameter(Mandatory)][string]$Path)

    try {
        # 只打开叶节点本身，以免把指向源的符号链接误判成硬链接。
        if (-not ('PwshProfile.FileIdentity' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace PwshProfile
{
    public static class FileIdentity
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FileIdInfo
        {
            public ulong Volume;
            public ulong Part1;
            public ulong Part2;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern SafeFileHandle CreateFileW(
            string path, uint access, uint share, IntPtr security,
            uint disposition, uint flags, IntPtr template);

        [DllImport("kernel32.dll", ExactSpelling = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle file, int infoClass, out FileIdInfo info, uint size);

        public static string Read(string path)
        {
            const uint ReadAttributes = 0x80;
            const uint ShareReadWriteDelete = 7;
            const uint OpenExisting = 3;
            const uint OpenReparsePoint = 0x00200000;
            const int FileIdInformation = 18;
            using (var file = CreateFileW(path, ReadAttributes, ShareReadWriteDelete,
                IntPtr.Zero, OpenExisting, OpenReparsePoint, IntPtr.Zero))
            {
                FileIdInfo info;
                if (file.IsInvalid ||
                    !GetFileInformationByHandleEx(file, FileIdInformation, out info, (uint)Marshal.SizeOf(typeof(FileIdInfo))) ||
                    (info.Part1 == 0 && info.Part2 == 0))
                {
                    return null;
                }
                return info.Volume.ToString("X16") + info.Part1.ToString("X16") + info.Part2.ToString("X16");
            }
        }
    }
}
'@ -ErrorAction Stop
        }
        $filePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
        [PwshProfile.FileIdentity]::Read($filePath)
    }
    catch {
        Write-Debug "无法读取文件标识：$_"
    }
}

function __Test-IsHardLinkOf {
    param(
        [Parameter(Mandatory)][string]$Src,
        [Parameter(Mandatory)][string]$Target
    )

    $sourceIdentity = __Get-ManagedFileIdentity -Path $Src
    if (-not $sourceIdentity) { return $false }
    return ($sourceIdentity -ceq (__Get-ManagedFileIdentity -Path $Target))
}

# 内部：按磁盘状态严格认领受管链接类型——只认有证据的 SymbolicLink/Junction
# （且指向仓库源）与 HardLink（卷序列号和文件 ID 相同）；普通文件/目录返回 $null 不认领
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

# 损坏的登记只能靠磁盘上的链接重建，普通副本无法证明原来的归属。
function Restore-LinkRegistry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Manifest', Justification = '脚本块内使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepoDir', Justification = '脚本块内使用')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Manifest,
        [Parameter(Mandatory)][string]$RepoDir
    )
    try { return __Read-LinkRegistryEntries $Path }
    catch { Write-Debug "首次读取登记失败: $($_.Exception.Message)" }
    return __Invoke-WithLinkRegistryLock -Body {
        # 锁内重读以识别并发恢复，并将读取失败与内容损坏区分开。
        try { $json = __Read-LinkRegistryText $Path }
        catch {
            Write-Warning "链接注册表读取失败，已跳过恢复: $($_.Exception.Message)"
            return
        }
        if ($null -eq $json) { return }
        try { return __ConvertFrom-RegistryJson $json }
        catch { Write-Debug "锁内解析登记失败: $($_.Exception.Message)" }

        $backup = "$Path.corrupt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        if (Test-Path -LiteralPath $backup) {
            $backup += "-$([guid]::NewGuid().ToString('N'))"
        }
        try { Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction Stop }
        catch {
            Write-Warning "损坏注册表备份失败，已跳过恢复: $($_.Exception.Message)"
            return
        }
        Write-Warning "链接注册表损坏，已备份到 $backup，正按清单与磁盘状态重建"

        try {
            $entries = @(
                foreach ($m in $Manifest) {
                    if (-not $m.Target -or -not $m.Source) { continue }
                    $src = Join-Path $RepoDir $m.Source
                    $type = __Get-ManagedLinkTypeFromDisk -Src $src -Target $m.Target
                    if ($type) {
                        [pscustomobject]@{
                            Target   = (Get-Item -LiteralPath $m.Target -Force -ErrorAction Stop).FullName
                            Source   = $src
                            LinkType = $type
                        }
                    }
                }
            )
            Save-LinkRegistryEntries -Path $Path -Entries $entries
            return $entries
        }
        catch { Write-Warning "链接注册表重建失败: $($_.Exception.Message)" }
    }
}

function Save-LinkRegistryEntries {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '写入登记条目集合，复数语义正确')]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$Entries
    )
    $filePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $tmp = "$filePath.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($filePath))
        # -InputObject 确保单条登记也写成 JSON 数组。临时文件与目标必须在同一目录，才能直接替换。
        $json = ConvertTo-Json -InputObject @($Entries) -Depth 5 -ErrorAction Stop
        [IO.File]::WriteAllText($tmp, $json)
        if ([IO.File]::Exists($filePath)) {
            [IO.File]::Replace($tmp, $filePath, [NullString]::Value)
        }
        else {
            [IO.File]::Move($tmp, $filePath)
        }
    }
    finally {
        if ([IO.File]::Exists($tmp)) { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
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
    __Invoke-WithLinkRegistryLock -Body {
        try {
            $entries = @(__Read-LinkRegistryEntries $Path)
            $matchingEntries = @($entries | Where-Object Target -eq $Target)
            if ($matchingEntries.Count -eq 1 -and $matchingEntries[0].Source -eq $Source -and $matchingEntries[0].LinkType -eq $LinkType) {
                return
            }

            $otherEntries = @($entries | Where-Object Target -ne $Target)
            $entry = [pscustomobject]@{ Target = $Target; Source = $Source; LinkType = $LinkType }
            Save-LinkRegistryEntries -Path $Path -Entries ($otherEntries + $entry)
        }
        catch { Write-Warning "链接注册表登记失败，已跳过 ${Target}: $($_.Exception.Message)" }
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
    # 卷序列号和文件 ID 相同）
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
