# ==============================================================
# Starship 懒加载
# ==============================================================

function prompt {
    # Starship 完整脚本会替换当前占位符，调用方执行缓存助手解析的同一份代码。
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    try {
        $init = __Get-CachedInitScript -Command 'starship' -CacheFile "$env:TEMP\starship-init-cache-v2.ps1" -Arguments @('init', 'powershell', '--print-full-init')
        if ($null -ne $init) { . $init }
    }
    catch {
        Write-Debug "Starship 初始化失败：$_"
    }

    if (-not (Get-Command prompt -ErrorAction SilentlyContinue)) {
        function global:prompt { 'PS> ' }
    }
    prompt
}
