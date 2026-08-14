# ==============================================================
# PowerShell Profile - 模块化入口
# ==============================================================
# 全局变量：profile 根目录，供子模块引用
$global:__ProfileDir = Split-Path $PROFILE

# 仅在 $env:PROFILE_DEBUG 非空时打印加载耗时
$_debug = [bool]$env:PROFILE_DEBUG

# 加载计时（仅 debug 模式下使用）
if ($_debug) { $_total = [System.Diagnostics.Stopwatch]::StartNew() }

# 批量探测工具是否存在（一次 cmdlet 调用替代各模块中的多次 Get-Command）
$global:__Tools = @{}
foreach ($cmd in Get-Command eza,rg.exe,grep.exe,fd.exe,bat.exe,7z.exe,fnm,nvim,zoxide,fzf,starship -ErrorAction SilentlyContinue) {
    $global:__Tools[[System.IO.Path]::GetFileNameWithoutExtension($cmd.Name)] = $cmd
}

# 按顺序加载各模块
$modules = @(
    'init-cache.ps1'   # 缓存助手（供 env/prompt/modules 使用，必须最先加载）
    'env.ps1'
    'prompt.ps1'
    'psreadline.ps1'
    'modules.ps1'
    'aliases.ps1'
)

foreach ($mod in $modules) {
    if ($_debug) { $_step = [System.Diagnostics.Stopwatch]::StartNew() }
    $modPath = Join-Path $global:__ProfileDir "profile\$mod"
    if (Test-Path $modPath) {
        . $modPath
    } elseif ($_debug) {
        Write-Host "[profile] 未找到模块: $mod" -ForegroundColor Yellow
    }
    if ($_debug) {
        Write-Host "[$($_step.ElapsedMilliseconds)ms] $mod" -ForegroundColor DarkGray
    }
}

if ($_debug) {
    Write-Host "TOTAL: $($_total.ElapsedMilliseconds)ms" -ForegroundColor Green
}
