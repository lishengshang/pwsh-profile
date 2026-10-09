# ==============================================================
# PowerShell Profile - 模块化入口
# ==============================================================
# 版本守卫：PS 7+ 主力支持，5.1 兼容模式降级加载（子模块语法均保持 5.1 可解析，
# 见 AGENTS.md 规则 4）。兼容提示只对「装了 pwsh 7 却开 5.1」的场景轻提一句，
# 纯 5.1 机器静默；PWSH_PROFILE_QUIET=1 彻底关闭。
if ($PSVersionTable.PSVersion.Major -lt 7 -and -not $env:PWSH_PROFILE_QUIET) {
    foreach ($_pwsh in @(
            (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
            (Join-Path $env:LOCALAPPDATA 'Programs\PowerShell\7\pwsh.exe')
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\pwsh.exe')   # Microsoft Store 版
        )) {
        if (Test-Path $_pwsh) {
            Write-Host '兼容模式加载（已装 PowerShell 7，完整体验请用 pwsh 启动；设 PWSH_PROFILE_QUIET=1 关闭本提示）' -ForegroundColor DarkYellow
            break
        }
    }
}

# profile 根目录（安装目录），供子模块引用。用 $PSScriptRoot 而非 Split-Path $PROFILE：
# 手动 dot-source 仓库入口时也能从当前仓库加载。仓库目录另见 $global:__ProfileRepoDir。
$global:__ProfileDir = $PSScriptRoot

# 仓库目录发现顺序：a. $PSScriptRoot 含 .git（仓库即安装目录）
#   b. profile\ 是 Junction/SymbolicLink -> 解析 Target 父目录
#   c. 链接注册表里入口条目的 Source（Copy 降级部署）
#   d. 均失败 -> $null（psync 提示手动 git pull）
$_repoDir = $null
$_gitMeta = Get-Item -LiteralPath (Join-Path $PSScriptRoot '.git') -Force -ErrorAction SilentlyContinue
if ($_gitMeta) {
    # .git 可能是目录，也可能是 worktree 使用的指针文件
    $_repoDir = $PSScriptRoot
}
else {
    $_pl = Get-Item (Join-Path $PSScriptRoot 'profile') -Force -ErrorAction SilentlyContinue
    if ($_pl -and $_pl.LinkType -in 'Junction', 'SymbolicLink' -and $_pl.Target) {
        $_repoDir = Split-Path ([System.IO.Path]::GetFullPath($_pl.Target).TrimEnd('\'))
    }
    if (-not $_repoDir) {
        $_reg = Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json'
        if (Test-Path $_reg) {
            try {
                $_e = @(Get-Content $_reg -Raw | ConvertFrom-Json) |
                    Where-Object { $_.Target -ieq $PROFILE } | Select-Object -First 1
                if ($_e -and $_e.Source) { $_repoDir = Split-Path $_e.Source }
            } catch { }
        }
    }
    # 发现的目录必须真的含 .git 才算仓库（防止误判随机目录）
    if ($_repoDir -and -not (Test-Path -LiteralPath (Join-Path $_repoDir '.git'))) {
        $_repoDir = $null
    }
}
$global:__ProfileRepoDir = $_repoDir

# 先从注册表重建 PATH 再探测工具——否则从 IDE/快捷方式启动时父进程 PATH 不完整，
# 注册表里已有的工具会探测不到。PROFILE_KEEP_PARENT_PATH=1 保留父进程 PATH。
if (-not $env:PROFILE_KEEP_PARENT_PATH) {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
}

# 仅在 $env:PROFILE_DEBUG 非空时打印各模块耗时
$_debug = [bool]$env:PROFILE_DEBUG

# 启动计时（Stopwatch 开销可忽略；默认显示总耗时，PROFILE_NO_TIME=1 关闭）
$_total = [System.Diagnostics.Stopwatch]::StartNew()

# 批量探测外部工具。用 File.Exists 遍历 PATH（.exe/.cmd/.bat）而非 Get-Command：
# 后者对每个缺失名字要做 PATH × PATHEXT 全展开（11 个名字 ~190ms vs 这里 ~37ms）。
# 只列 profile 会引用 __Tools 的名字；jq 等纯外部依赖（yazi 预览自寻 PATH）不入列。
$global:__Tools = @{}
$_dirs = $env:PATH -split ';' | Where-Object { $_ }
foreach ($_name in 'eza','rg','grep','fd','bat','7z','fnm','nvim','zoxide','fzf','starship','yazi','lazygit','git') {
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
        # 单模块失败不阻断后续模块（典型：PSReadLine 参数不支持、注册表读取
        # 失败、fnm 输出异常）；默认静默，PROFILE_DEBUG=1 时显示详情
        try {
            . $modPath
        }
        catch {
            if ($_debug) {
                Write-Host "[profile] 模块加载失败: $mod - $_" -ForegroundColor Red
            }
        }
    } elseif ($_debug) {
        Write-Host "[profile] 未找到模块: $mod" -ForegroundColor Yellow
    }
    if ($_debug) {
        Write-Host "[$($_step.ElapsedMilliseconds)ms] $mod" -ForegroundColor DarkGray
    }
}

# 非交互环境（输出被重定向 / 无用户会话，如 pwsh -Command 管道捕获、CI）
# 默认静默：问候横幅与耗时行会污染 JSON/CSV/脚本管道输出。
# PROFILE_QUIET=1 可在交互终端强制静默。
$_quiet = [bool]$env:PROFILE_QUIET -or
    [Console]::IsOutputRedirected -or
    -not [Environment]::UserInteractive

# 启动信息（问候/系统信息/键位速查）+ 总耗时（startup.ps1 加载失败时不致命）
if (-not $_quiet) {
    try { Show-StartupInfo } catch { }
}
if ($_debug) {
    Write-Host "TOTAL: $($_total.ElapsedMilliseconds)ms" -ForegroundColor Green
}
elseif (-not $_quiet -and -not $env:PROFILE_NO_TIME) {
    Write-Host "Profile loaded in $($_total.ElapsedMilliseconds)ms" -ForegroundColor Cyan
}
