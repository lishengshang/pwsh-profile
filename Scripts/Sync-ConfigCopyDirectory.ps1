# ==============================================================
# 目录副本按上次写入的文件哈希同步，目标侧从未写入过的内容不纳入管理。
# ==============================================================

function __Get-CopyItemAttribute {
    param([string]$Path)

    try { [IO.File]::GetAttributes($Path) }
    catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { return }
}

function __Get-CopyPathAttribute {
    param([string]$Root, [string]$RelativePath)

    $rootAttributes = __Get-CopyItemAttribute $Root
    if (-not ($rootAttributes -band [IO.FileAttributes]::Directory) -or
        ($rootAttributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "目录副本的根目录已变化: $Root"
    }

    $path = $Root
    $parts = $RelativePath.Split('/')
    for ($i = 0; $i -lt $parts.Length; $i++) {
        $path = [IO.Path]::Combine($path, $parts[$i])
        $attributes = __Get-CopyItemAttribute $path
        if ($null -eq $attributes) { return }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or
            ($i -lt ($parts.Length - 1) -and -not ($attributes -band [IO.FileAttributes]::Directory))) {
            throw "路径包含重解析点或非目录的上级: $path"
        }
    }
    $attributes
}

function __Get-CopySourcePaths {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = '返回相对路径集合')]
    param([string]$Directory, [string]$Prefix = '')

    foreach ($path in [IO.Directory]::GetFileSystemEntries($Directory)) {
        $relative = $Prefix + [IO.Path]::GetFileName($path)
        $attributes = [IO.File]::GetAttributes($path)
        $relative
        if (($attributes -band [IO.FileAttributes]::Directory) -and
            -not ($attributes -band [IO.FileAttributes]::ReparsePoint)) {
            __Get-CopySourcePaths -Directory $path -Prefix "$relative/"
        }
    }
}

function __Read-CopyFileBaseline {
    param($Entry)

    $baseline = @{}
    if ($null -eq $Entry -or -not $Entry.PSObject.Properties['CopyFiles']) { return $baseline }
    if ($Entry.CopyFiles -isnot [array]) { throw '目录副本的文件清单格式无效。' }
    foreach ($file in $Entry.CopyFiles) {
        if ($file.Path -isnot [string] -or $file.Hash -isnot [string] -or $file.Hash -notmatch '^[A-Fa-f0-9]{64}$') {
            throw '目录副本的文件清单条目无效。'
        }
        foreach ($part in $file.Path.Split('/')) {
            if ($part -notmatch '^[^\\/:*?"<>|\x00-\x1F]+$' -or $part -match '[. ]$' -or
                $part -match '^(CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])(?:\.|$)') {
                throw "目录副本的文件清单包含无效路径: $($file.Path)"
            }
        }
        if ($baseline.ContainsKey($file.Path)) { throw "目录副本的文件清单路径重复: $($file.Path)" }
        $baseline[$file.Path] = $file.Hash
    }
    $baseline
}

function __Publish-CopyFile {
    param([string]$Source, [string]$Target, [string]$OldHash, [string]$NewHash)

    $id = [guid]::NewGuid().ToString('N')
    $parent = [IO.Path]::GetDirectoryName($Target)
    $staged = [IO.Path]::Combine($parent, ".pwsh-copy-$id.tmp")
    $backup = [IO.Path]::Combine($parent, ".pwsh-copy-$id.conflict")
    try {
        if ($Source) {
            [IO.File]::Copy($Source, $staged)
            if ((Get-FileHash -LiteralPath $staged -ErrorAction Stop).Hash -ne $NewHash) {
                throw "复制期间源文件发生变化: $Source"
            }
            if ($OldHash) { [IO.File]::Replace($staged, $Target, $backup) }
            else { [IO.File]::Move($staged, $Target) }
        }
        else {
            [IO.File]::Move($Target, $backup)
        }

        # 原子换出的版本可能比检查时更新，核验之后才能删除。
        if ($OldHash) {
            try {
                $attributes = [IO.File]::GetAttributes($backup)
                if (($attributes -band [IO.FileAttributes]::ReparsePoint) -or
                    (Get-FileHash -LiteralPath $backup -ErrorAction Stop).Hash -ne $OldHash) {
                    throw '目标在同步期间发生变化。'
                }
                [IO.File]::Delete($backup)
            }
            catch {
                if (-not $Source) {
                    try { [IO.File]::Move($backup, $Target) }
                    catch { Write-Warning "无法放回原位置，原内容保留在: $backup" }
                }
                $retained = if ([IO.File]::Exists($backup)) { $backup } else { $Target }
                throw ('无法确认换出的文件可删除，原内容保留在 {0}：{1}' -f $retained, $_.Exception.Message)
            }
        }
    }
    finally {
        if ([IO.File]::Exists($staged)) { [IO.File]::Delete($staged) }
    }
}

function Sync-ConfigCopyDirectory {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Create', Justification = '锁内脚本块使用')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RegistryPath', Justification = '锁内脚本块使用')]
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$RegistryPath,
        [switch]$Create
    )

    $providerPath = $ExecutionContext.SessionState.Path
    $sourceRoot = __Get-NormalizedFullPath ($providerPath.GetUnresolvedProviderPathFromPSPath($Source))
    $targetRoot = __Get-NormalizedFullPath ($providerPath.GetUnresolvedProviderPathFromPSPath($Target))
    if (-not [IO.Path]::IsPathRooted($sourceRoot) -or $sourceRoot -eq ([IO.Path]::GetPathRoot($sourceRoot).TrimEnd('\')) -or
        -not [IO.Path]::IsPathRooted($targetRoot) -or $targetRoot -eq ([IO.Path]::GetPathRoot($targetRoot).TrimEnd('\'))) {
        throw '目录副本的源和目标必须位于卷根下。'
    }
    if ($sourceRoot -eq $targetRoot -or
        $sourceRoot.StartsWith("$targetRoot\", [StringComparison]::OrdinalIgnoreCase) -or
        $targetRoot.StartsWith("$sourceRoot\", [StringComparison]::OrdinalIgnoreCase)) {
        throw "目录副本的源与目标相互重叠: $Target"
    }

    return __Invoke-WithLinkRegistryLock -Body {
        $entries = @(__Read-LinkRegistryEntries $RegistryPath)
        $matching = @($entries | Where-Object { (__Get-NormalizedFullPath ($providerPath.GetUnresolvedProviderPathFromPSPath($_.Target))) -eq $targetRoot })
        if ($matching.Count -gt 1) { throw "目录副本存在重复登记: $Target" }
        $entry = $matching | Select-Object -First 1
        $registered = $entry -and $entry.LinkType -eq 'CopyDirectory' -and
            (__Get-NormalizedFullPath ($providerPath.GetUnresolvedProviderPathFromPSPath($entry.Source))) -eq $sourceRoot
        if (-not $Create -and -not $registered) { throw "目录副本的登记已变更: $Target" }

        $sourceAttributes = __Get-CopyItemAttribute $sourceRoot
        if (-not ($sourceAttributes -band [IO.FileAttributes]::Directory) -or
            ($sourceAttributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "目录副本的源必须是普通目录: $Source"
        }
        $targetAttributes = __Get-CopyItemAttribute $targetRoot
        if ($null -ne $targetAttributes -and ($Create -or ($targetAttributes -band [IO.FileAttributes]::ReparsePoint))) {
            throw "保留现有目标，目录副本无法同步: $Target"
        }
        $sourcePaths = @(__Get-CopySourcePaths -Directory $sourceRoot -ErrorAction Stop)
        $baseline = __Read-CopyFileBaseline $entry
        $newDirectory = -not ($targetAttributes -band [IO.FileAttributes]::Directory)
        if ($newDirectory) {
            if ($null -ne $targetAttributes) {
                $backup = "$targetRoot.conflict-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N'))"
                [IO.File]::Move($targetRoot, $backup)
                Write-Warning "原文件已保留到 $backup；确认内容后可手动归档或删除备份。"
            }
            $baseline.Clear()
            $null = [IO.Directory]::CreateDirectory($targetRoot)
        }
        $changed = $newDirectory
        $complete = $true

        foreach ($relative in @($sourcePaths + @($baseline.Keys) | Sort-Object -Unique)) {
            try {
                $from = [IO.Path]::Combine($sourceRoot, $relative.Replace('/', '\'))
                $to = [IO.Path]::Combine($targetRoot, $relative.Replace('/', '\'))
                $fromAttributes = __Get-CopyPathAttribute -Root $sourceRoot -RelativePath $relative
                $toAttributes = __Get-CopyPathAttribute -Root $targetRoot -RelativePath $relative
                $oldHash = $baseline[$relative]

                if ($fromAttributes -band [IO.FileAttributes]::Directory) {
                    if ($oldHash -or ($null -ne $toAttributes -and -not ($toAttributes -band [IO.FileAttributes]::Directory))) {
                        throw '目录与文件类型冲突。'
                    }
                    if ($null -eq $toAttributes) { $null = [IO.Directory]::CreateDirectory($to) }
                    continue
                }
                if ($toAttributes -band [IO.FileAttributes]::Directory) { throw '文件与目录类型冲突。' }

                $newHash = if ($null -ne $fromAttributes) { (Get-FileHash -LiteralPath $from -ErrorAction Stop).Hash }
                $targetHash = if ($null -ne $toAttributes) { (Get-FileHash -LiteralPath $to -ErrorAction Stop).Hash }
                if ($oldHash) {
                    if ($newHash -eq $oldHash) { continue }
                    if ($targetHash -ne $oldHash -and ($targetHash -or $newHash)) {
                        throw '目标文件已本地修改或删除。'
                    }
                }
                elseif ($targetHash) {
                    if ($newHash -and $targetHash -ne $newHash) { throw '同路径已有内容不同的文件。' }
                    continue
                }
                elseif (-not $newHash) {
                    # 枚举后仓库文件被移走，留待下次同步重新检查。
                    continue
                }

                if ($newHash) {
                    __Publish-CopyFile -Source $from -Target $to -OldHash $oldHash -NewHash $newHash
                    $baseline[$relative] = $newHash
                }
                else {
                    if ($targetHash) { __Publish-CopyFile -Target $to -OldHash $oldHash }
                    $baseline.Remove($relative)
                }
                $changed = $true
            }
            catch {
                $complete = $false
                Write-Warning "目录副本保留冲突或待处理项（$Target，$relative）：$($_.Exception.Message)"
            }
        }

        if ($changed) {
            $entry = [pscustomobject]@{
                Target = $Target
                Source = $Source
                LinkType = 'CopyDirectory'
                CopyFiles = @(foreach ($relative in ($baseline.Keys | Sort-Object)) {
                    [pscustomobject]@{ Path = $relative; Hash = $baseline[$relative] }
                })
            }
            $otherEntries = @($entries | Where-Object { $_ -notin $matching })
            Save-LinkRegistryEntries -Path $RegistryPath -Entries ($otherEntries + $entry)
        }
        return $complete
    }
}
