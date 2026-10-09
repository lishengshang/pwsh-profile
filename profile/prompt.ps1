# ==============================================================
# Starship 懒加载
# ==============================================================
# 缓存 starship 完整 init 脚本（--print-full-init），dot-source 零进程调用；
# 生成延迟到首次 prompt（7 天 TTL + starship 升级即失效，见 init-cache.ps1）。
# v2 文件名：v1 缓存的是引导行，dot-source 时还要再起一次 starship 进程。
$global:__starshipCache = "$env:TEMP\starship-init-cache-v2.ps1"
$script:__starshipReady = $false

function prompt {
    if (-not $script:__starshipReady) {
        $script:__starshipReady = $true
        $null = Initialize-CachedInit -Command 'starship' -CacheFile $global:__starshipCache -Arguments @('init','powershell','--print-full-init')
    }
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    if (Test-Path $global:__starshipCache) {
        . $global:__starshipCache
    } elseif ($global:__Tools.ContainsKey('starship')) {
        Invoke-Expression (& starship init powershell --print-full-init | Out-String)
    }
    # 兜底：上面两条路都没定义新 prompt 时重建一个默认值，否则调用 prompt 会
    # CommandNotFoundException。必须 global: 限定——函数体内的普通 function
    # 定义只存活于本次调用
    if (-not (Get-Command prompt -ErrorAction SilentlyContinue)) {
        function global:prompt { 'PS> ' }
    }
    prompt
}
