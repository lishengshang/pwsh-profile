# ==============================================================
# PowerShell Profile - 模块化入口
# ==============================================================
# 版本守卫：此配置仅支持 PowerShell 7+。Windows PowerShell 5.1 的角色只是
# 运行 bootstrap.ps1 引导安装 pwsh 7；误加载时给出引导后直接退出，
# 避免子模块的 PS7 语法（?. 等）产生满屏解析错误。
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "此 PowerShell 配置需要 PowerShell 7+（当前 $($PSVersionTable.PSVersion)）。" -ForegroundColor Yellow
    Write-Host 'Windows PowerShell 5.1 仅用于引导：在仓库目录执行 .\bootstrap.ps1 安装 pwsh 7。' -ForegroundColor Yellow
    return
}

# 全局变量：profile 根目录，供子模块引用
$global:__ProfileDir = Split-Path $PROFILE

# 先从注册表重建 PATH，再探测工具——否则父进程 PATH 不完整时
# （如从 IDE/快捷方式启动）注册表里已有的工具会探测不到。
# 需要保留父进程 PATH 时设置 $env:PROFILE_KEEP_PARENT_PATH=1（见 README「设计说明」）。
if (-not $env:PROFILE_KEEP_PARENT_PATH) {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
}

# 仅在 $env:PROFILE_DEBUG 非空时打印各模块耗时
$_debug = [bool]$env:PROFILE_DEBUG

# 启动计时（Stopwatch 开销可忽略；默认显示总耗时，PROFILE_NO_TIME=1 关闭）
$_total = [System.Diagnostics.Stopwatch]::StartNew()

# 批量探测工具是否存在。
# 用 File.Exists 遍历 PATH（.exe/.cmd/.bat），比 Get-Command 快约 5 倍：
# Get-Command 对每个缺失名字会做 PATH × PATHEXT 全展开（11 个名字 ~190ms），
# 这里 ~37ms。工具一律为外部可执行文件，无需 Get-Command 的命令发现语义。
$global:__Tools = @{}
$_dirs = $env:PATH -split ';' | Where-Object { $_ }
foreach ($_name in 'eza','rg','grep','fd','bat','7z','fnm','nvim','zoxide','fzf','starship','yazi','jq','lazygit') {
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
    'startup.ps1'      # 启动信息（问候/系统信息/键位速查，在耗时行前显示）
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

# 启动信息（问候/系统信息/键位速查）+ 总耗时
Show-StartupInfo
if ($_debug) {
    Write-Host "TOTAL: $($_total.ElapsedMilliseconds)ms" -ForegroundColor Green
}
elseif (-not $env:PROFILE_NO_TIME) {
    Write-Host "Profile loaded in $($_total.ElapsedMilliseconds)ms" -ForegroundColor Cyan
}
