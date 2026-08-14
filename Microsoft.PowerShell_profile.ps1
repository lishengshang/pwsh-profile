# ==============================================================
# PowerShell Profile - 模块化入口
# ==============================================================
# 全局变量：profile 根目录，供子模块引用
$global:__ProfileDir = Split-Path $PROFILE

# 先从注册表重建 PATH，再探测工具——否则父进程 PATH 不完整时
# （如从 IDE/快捷方式启动）注册表里已有的工具会探测不到。
# 需要保留父进程 PATH 时设置 $env:PROFILE_KEEP_PARENT_PATH=1（见 README「设计说明」）。
if (-not $env:PROFILE_KEEP_PARENT_PATH) {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
}

# 仅在 $env:PROFILE_DEBUG 非空时打印加载耗时
$_debug = [bool]$env:PROFILE_DEBUG

# 加载计时（仅 debug 模式下使用）
if ($_debug) { $_total = [System.Diagnostics.Stopwatch]::StartNew() }

# 批量探测工具是否存在。
# 用 File.Exists 遍历 PATH（.exe/.cmd/.bat），比 Get-Command 快约 5 倍：
# Get-Command 对每个缺失名字会做 PATH × PATHEXT 全展开（11 个名字 ~190ms），
# 这里 ~37ms。工具一律为外部可执行文件，无需 Get-Command 的命令发现语义。
$global:__Tools = @{}
$_dirs = $env:PATH -split ';' | Where-Object { $_ }
foreach ($_name in 'eza','rg','grep','fd','bat','7z','fnm','nvim','zoxide','fzf','starship') {
    foreach ($_d in $_dirs) {
        foreach ($_e in '.exe','.cmd','.bat') {
            if ([System.IO.File]::Exists("$_d\$_name$_e")) {
                $global:__Tools[$_name] = [pscustomobject]@{ Name = $_name; Source = "$_d\$_name$_e" }
                break
            }
        }
        if ($global:__Tools.ContainsKey($_name)) { break }
    }
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
