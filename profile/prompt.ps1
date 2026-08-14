# ==============================================================
# Starship 懒加载
# ==============================================================
# 缓存 starship init 的完整脚本（--print-full-init），dot-source 零进程调用；
# 缓存生成延迟到首次 prompt（7 天 TTL + starship 升级即失效，见 init-cache.ps1）。
# v2 文件名：旧版缓存的是引导行（dot-source 时还要再起一次 starship 进程）。
$global:__starshipCache = "$env:TEMP\starship-init-cache-v2.ps1"
$script:__starshipReady = $false

function prompt {
    # 仅首次：确保缓存新鲜（生成/刷新），此后每次 prompt 零额外开销
    if (-not $script:__starshipReady) {
        $script:__starshipReady = $true
        $null = Initialize-CachedInit -Command 'starship' -CacheFile $global:__starshipCache -Arguments @('init','powershell','--print-full-init')
    }
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    if (Test-Path $global:__starshipCache) {
        . $global:__starshipCache
    } elseif ($global:__Tools.ContainsKey('starship')) {
        # 保底：缓存生成失败时的现场回退（罕见）
        Invoke-Expression (& starship init powershell --print-full-init | Out-String)
    }
    # 兜底：上方路径都未定义新的 prompt 函数时重建一个简单默认值，
    # 否则 Remove-Item 之后调用 prompt 会报 CommandNotFoundException。
    # 必须用 global: 限定——在函数体内定义普通 function 只存活于本次调用
    if (-not (Get-Command prompt -ErrorAction SilentlyContinue)) {
        function global:prompt { 'PS> ' }
    }
    prompt
}
