# ==============================================================
# Starship 懒加载
# ==============================================================
$global:__starshipCache = "$env:TEMP\starship-init-cache.ps1"

# 首次或缓存过期时同步生成（带原子写入，避免半写竞态）
if (-not (Test-Path $global:__starshipCache) -or
    (Get-Item $global:__starshipCache).LastWriteTime -lt (Get-Date).AddDays(-7)) {
    try {
        $_starshipOut = & starship init powershell 2>$null | Out-String
        if ($LASTEXITCODE -eq 0 -and $_starshipOut.Trim()) {
            $_tmp = "$($global:__starshipCache).tmp"
            Set-Content -Path $_tmp -Value $_starshipOut -Encoding UTF8
            Move-Item -Path $_tmp -Destination $global:__starshipCache -Force
        }
    } catch {
        Write-Host "[starship] 缓存生成失败: $_" -ForegroundColor Yellow
    }
}

function prompt {
    Remove-Item Function:\prompt -ErrorAction SilentlyContinue
    if (Test-Path $global:__starshipCache) {
        . $global:__starshipCache
    } elseif (Get-Command starship -ErrorAction SilentlyContinue) {
        Invoke-Expression (&starship init powershell | Out-String)
    } else {
        'PS> '
    }
    prompt
}
