# ==============================================================
# Starship 懒加载
# ==============================================================
$global:__starshipCache = "$env:TEMP\starship-init-cache.ps1"

# 首次或缓存过期时，同步生成缓存（避免 Start-Job 半写竞态）
if (-not (Test-Path $global:__starshipCache) -or
    (Get-Item $global:__starshipCache).LastWriteTime -lt (Get-Date).AddDays(-1)) {
    try {
        &starship init powershell | Set-Content $global:__starshipCache -Encoding UTF8
    } catch {
        Write-Host "[starship] 缓存生成失败: $_" -ForegroundColor Yellow
    }
}

function prompt {
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    if (Test-Path $global:__starshipCache) {
        . $global:__starshipCache
    } else {
        Invoke-Expression (&starship init powershell)
    }
    prompt
}
