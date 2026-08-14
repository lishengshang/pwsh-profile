# ==============================================================
# Starship 懒加载
# ==============================================================
$global:__starshipCache = "$env:TEMP\starship-init-cache.ps1"

# 首次 / 缓存过期 / starship 升级时同步生成（原子写入，失败保留旧缓存）
$null = Initialize-CachedInit -Command 'starship' -CacheFile $global:__starshipCache -Arguments @('init','powershell')

function prompt {
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    if (Test-Path $global:__starshipCache) {
        . $global:__starshipCache
    } elseif ($global:__Tools.ContainsKey('starship')) {
        Invoke-Expression (&starship init powershell | Out-String)
    }
    # 兜底：上方路径都未定义新的 prompt 函数时重建一个简单默认值，
    # 否则 Remove-Item 之后调用 prompt 会报 CommandNotFoundException。
    # 必须用 global: 限定——在函数体内定义普通 function 只存活于本次调用
    if (-not (Get-Command prompt -ErrorAction SilentlyContinue)) {
        function global:prompt { 'PS> ' }
    }
    prompt
}
