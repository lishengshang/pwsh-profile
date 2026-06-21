# ==============================================================
# PowerShell Profile - 模块化入口
# ==============================================================

# 全局变量：profile 根目录，供子模块引用
$global:__ProfileDir = Split-Path $PROFILE

# 加载计时
$_total = [System.Diagnostics.Stopwatch]::StartNew()

# 按顺序加载各模块
$modules = @(
    'env.ps1'
    'prompt.ps1'
    'psreadline.ps1'
    'modules.ps1'
    'aliases.ps1'
)

foreach ($mod in $modules) {
    $_step = [System.Diagnostics.Stopwatch]::StartNew()
    $modPath = Join-Path $global:__ProfileDir "profile\$mod"
    if (Test-Path $modPath) {
        . $modPath
    } else {
        Write-Host "[profile] 未找到模块: $mod" -ForegroundColor Yellow
    }
    Write-Host "[$($_step.ElapsedMilliseconds)ms] $mod" -ForegroundColor DarkGray
}

Write-Host "TOTAL: $($_total.ElapsedMilliseconds)ms" -ForegroundColor Green
