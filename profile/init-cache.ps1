# ==============================================================
# 外部工具 init 缓存助手
# 统一 starship / zoxide 的缓存逻辑（fnm 不缓存——其输出含每进程独立的
# FNM_MULTISHELL_PATH，跨会话缓存会导致 PATH 失效，见 env.ps1）：
#   - 默认 7 天 TTL（TtlDays=0 时只按工具二进制 mtime 失效）
#   - 工具二进制升级（mtime 更新）即失效，无需手动删缓存
#   - 原子写入（先 .tmp 再 Move），生成失败时回退旧缓存
# 用法（profile 加载时同步调用）：
#   Initialize-CachedInit -Command starship -CacheFile $path -Arguments @('init','powershell')
#   返回 $true 表示缓存文件可用，调用方再决定 dot-source 时机。
#   Use-CachedInit 为其组合形式：生成成功即 dot-source（zoxide 场景——init 输出
#   全是 global: 函数 + 别名，可安全在任意时机加载；prompt 需要控制加载时机，用两步形式）。
# ==============================================================

function Initialize-CachedInit {
    param(
        [Parameter(Mandatory)][string]$Command,   # $global:__Tools 中的键名
        [Parameter(Mandatory)][string]$CacheFile, # 缓存文件完整路径
        [string[]]$Arguments,                     # 生成 init 脚本的参数
        [int]$TtlDays = 7                         # 0 = 不按时间过期，只按工具 mtime
    )

    $tool = $global:__Tools[$Command]
    if (-not $tool) { return $false }

    $item = Get-Item $CacheFile -ErrorAction SilentlyContinue
    if ($item) {
        # 工具升级即失效：二进制 mtime 比缓存新则重新生成
        $toolTime = (Get-Item $tool.Source -ErrorAction SilentlyContinue).LastWriteTime
        if ($toolTime -and $toolTime -gt $item.LastWriteTime) {
            $item = $null
        }
        elseif ($TtlDays -le 0 -or $item.LastWriteTime -ge (Get-Date).AddDays(-$TtlDays)) {
            return $true   # 缓存新鲜，直接可用
        }
    }

    try {
        # 用完整路径调用（而非裸命令名），避免 PATH 变化导致解析失败；
        # Source 由入口探测构造，恒非空
        $out = & $tool.Source @Arguments 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and $out.Trim()) {
            $tmp = "$CacheFile.tmp"
            Set-Content -Path $tmp -Value $out -Encoding UTF8
            Move-Item -Path $tmp -Destination $CacheFile -Force
            return $true
        }
    }
    catch {
        Write-Host "[$Command] 缓存生成失败: $_" -ForegroundColor Yellow
    }
    return (Test-Path $CacheFile)  # 生成失败时回退到旧缓存
}

function Use-CachedInit {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$CacheFile,
        [string[]]$Arguments,
        [int]$TtlDays = 7
    )
    $null = Initialize-CachedInit @PSBoundParameters
    if (Test-Path $CacheFile) { . $CacheFile }
}
