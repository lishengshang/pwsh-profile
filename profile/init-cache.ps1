# ==============================================================
# 外部工具 init 缓存助手（Starship、zoxide）
# fnm 输出包含每个会话独立的路径，见 env.ps1。
# ==============================================================

function __ConvertTo-CachedInitBlock {
    param([string]$Text, [string]$CacheFile)

    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, $CacheFile, [ref]$tokens, [ref]$errors)
    if ($errors.Count -eq 0) { $ast.GetScriptBlock() }
}

function __Get-CachedInitScript {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$CacheFile,
        [string[]]$Arguments,
        [ValidateRange(0, [int]::MaxValue)][int]$TtlDays = 7
    )

    $tool = $global:__Tools[$Command]
    if (-not $tool) { return }
    $source = [IO.Path]::GetFullPath($tool.Source)
    $toolItem = [IO.FileInfo]::new($source)
    if (-not $toolItem.Exists) { return }

    $parts = [string[]]@($source; foreach ($argument in $Arguments) { $argument })
    # 原生参数不能含 NUL，用它分隔能保留参数边界及顺序。
    $identityBytes = [Text.Encoding]::UTF8.GetBytes([string]::Join([string][char]0, $parts))
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $identity = [BitConverter]::ToString($hash.ComputeHash($identityBytes)).Replace('-', '')
    }
    finally {
        $hash.Dispose()
    }
    $prefix = "# pwsh-profile-init-cache-v1 $identity "
    $fingerprint = '{0}:{1}' -f $toolItem.LastWriteTimeUtc.Ticks, $toolItem.Length

    $cached = $null
    $cacheItem = [IO.FileInfo]::new($CacheFile)
    if ($cacheItem.Exists) {
        try {
            $text = [IO.File]::ReadAllText($CacheFile, [Text.Encoding]::UTF8)
            $lineEnd = $text.IndexOf([char]10)
            if ($lineEnd -ge 0) {
                $header = $text.Substring(0, $lineEnd).TrimEnd([char]13)
                if ($header.StartsWith($prefix, [StringComparison]::Ordinal) -and
                    $header.Substring($prefix.Length) -match '^\d+:\d+$') {
                    $cached = __ConvertTo-CachedInitBlock -Text $text.Substring($lineEnd + 1) -CacheFile $CacheFile
                    $unexpired = $TtlDays -eq 0 -or ([DateTime]::UtcNow - $cacheItem.LastWriteTimeUtc).TotalDays -le $TtlDays
                    if ($null -ne $cached -and $unexpired -and $header -ceq "$prefix$fingerprint") { return $cached }
                }
            }
        }
        catch {
            Write-Debug "[$Command] 读取初始化缓存失败：$_"
        }
    }

    $fresh = $null
    try {
        $out = & $source @Arguments 2>$null | Out-String
        if ($LASTEXITCODE -eq 0) { $fresh = __ConvertTo-CachedInitBlock -Text $out -CacheFile $CacheFile }
    }
    catch {
        Write-Debug "[$Command] 生成初始化脚本失败：$_"
    }
    if ($null -eq $fresh) { return $cached }

    # 不同会话各写同目录的独立临时文件，再发布已验证的完整内容。
    $tempFile = "$CacheFile.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        $text = "$prefix$fingerprint" + [Environment]::NewLine + $out
        [IO.File]::WriteAllText($tempFile, $text, [Text.UTF8Encoding]::new($true))
        if ([IO.File]::Exists($CacheFile)) {
            [IO.File]::Replace($tempFile, $CacheFile, [NullString]::Value)
        }
        else {
            [IO.File]::Move($tempFile, $CacheFile)
        }
    }
    catch {
        Write-Debug "[$Command] 写入初始化缓存失败：$_"
    }
    finally {
        try { [IO.File]::Delete($tempFile) }
        catch { Write-Debug "[$Command] 清理初始化缓存临时文件失败：$_" }
    }
    # 落盘失败不影响本次使用。调用方执行已验证的代码块，不必重读缓存。
    $fresh
}
