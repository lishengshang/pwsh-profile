# ==============================================================
# Starship 懒加载
# ==============================================================

function prompt {
    $previousExitCode = Get-Variable LASTEXITCODE -Scope Global -ValueOnly -ErrorAction Ignore
    # Starship 完整脚本会替换当前占位符，调用方执行缓存助手解析的同一份代码。
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    try {
        $init = __Get-CachedInitScript -Command 'starship' -CacheFile "$env:TEMP\starship-init-cache-v2.ps1" -Arguments @('init', 'powershell', '--print-full-init')
        if ($null -ne $init) { . $init }
    }
    catch {
        Write-Debug "Starship 初始化失败：$_"
    }

    $useDefaultPrompt = -not (Get-Command prompt -ErrorAction SilentlyContinue)
    if ($useDefaultPrompt) {
        function global:prompt { 'PS> ' }
    }
    if ($global:__Tools.ContainsKey('zoxide')) {
        try { __Enable-ZoxideHistory -DefaultPrompt:$useDefaultPrompt }
        catch { Write-Debug "zoxide 目录记录初始化失败：$_" }
    }
    $global:LASTEXITCODE = $previousExitCode
    prompt
}
