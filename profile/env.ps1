# ==============================================================
# 环境初始化
# ==============================================================
# 注：PATH 重建已提前到入口（Microsoft.PowerShell_profile.ps1）的
# 工具探测之前执行，此处只处理 fnm 缓存与默认编辑器。

# fnm (Node 版本管理) —— 静态兑底 + 懒加载两段式
# fnm env 输出含每进程独立的 FNM_MULTISHELL_PATH，无法跨会话缓存（旧注释：
# 缓存会导致新终端指向已销毁的旧进程目录）；同步执行实测 ~25-70ms，曾是
# profile 自身最大的可控启动成本。拆成两段后启动期零进程调用：
#   1. 静态兑底：把 default 版本的安装目录（junction）前置到 PATH——
#      node/npm/npx/corepack 及 npm -g 全局命令立即可用（默认版本）。
#   2. 懒初始化：首次调用 node/npm/npx/corepack 时才执行 fnm env（定义 cd
#      包装函数实现进目录自动切换 .nvmrc/.node-version）并对当前目录做一次
#      版本解析（等价 use-on-cd 进目录行为），multishell 前置覆盖静态目录。
# PROFILE_NO_FNM=1 完全跳过（不用 Node 的场景，node 等走系统 PATH）。
if ($global:__Tools.ContainsKey('fnm') -and -not $env:PROFILE_NO_FNM) {
    # 静态兑底目录：fnm default 别名 junction（用户从未装过 Node 时不存在，静默跳过）
    $_fnmDefault = Join-Path $env:APPDATA 'fnm\aliases\default'
    if (Test-Path $_fnmDefault) { $env:PATH = "$_fnmDefault;$env:PATH" }

    $script:__fnmReady = $false
    # 占位函数模式：首次调用触发完整初始化，之后每次都转发到真实可执行文件。
    # 注意不能用 zoxide 那种「init 重定义自身」的模式——fnm env 只设环境变量、
    # 不重定义这些命令，必须显式解析 Application 类型避开占位函数自身。
    function __Ensure-Fnm ([string]$Cmd) {
        if (-not $script:__fnmReady) {
            $script:__fnmReady = $true
            Remove-Item "$env:TEMP\fnm-init-cache.ps1" -ErrorAction SilentlyContinue   # 清理历史缓存产物
            $out = & $global:__Tools['fnm'].Source env --use-on-cd --shell powershell 2>$null | Out-String
            if ($out) {
                # fnm env 把生成时的 PATH 快照写进 $env:PATH（还可能含父进程遗留的旧
                # multishell），恢复刷新过的 PATH 后只前置本进程的 shim 目录
                $_cleanPath = $env:PATH
                Invoke-Expression $out | Out-Null
                $env:PATH = $_cleanPath
                if ($env:FNM_MULTISHELL_PATH) {
                    $env:PATH = "$env:FNM_MULTISHELL_PATH;$env:PATH"
                }
            }
            # 当前目录带版本文件时补一次解析（模拟 use-on-cd 进入该目录的行为）
            if ($out -and ((Test-Path .nvmrc) -or (Test-Path .node-version) -or (Test-Path package.json))) {
                & $global:__Tools['fnm'].Source use --silent-if-unchanged 2>$null
            }
        }
        # 解析并执行真实命令（-CommandType Application 跳过占位函数自身；
        # 用 Source 而非 FullName——ApplicationInfo 没有 FullName 属性）
        $real = Get-Command $Cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($real) { & $real.Source @args }
        else { Write-Host "找不到 $Cmd（fnm 未安装任何 Node 版本？运行 fnm install <版本>）" -ForegroundColor Yellow }
    }
    function node     { __Ensure-Fnm node @args }
    function npm      { __Ensure-Fnm npm @args }
    function npx      { __Ensure-Fnm npx @args }
    function corepack { __Ensure-Fnm corepack @args }
}

# fzf UI 美化（Tokyo Night 配色 + 高度/反向/圆角边框/预览窗）
# bg:-1 = 使用终端默认背景（不绘制实色块），弹窗区域透出终端背景
# （半透明壁纸效果才能透出来）；注意 fzf 不接受 bg:default，必须用 -1。
# 选中行 bg+ 保留实色作为视觉锚点。用户已自行设置 FZF_DEFAULT_OPTS 时不覆盖。
if (-not $env:FZF_DEFAULT_OPTS) {
    $env:FZF_DEFAULT_OPTS = '--height=40% --layout=reverse --border=rounded --preview-window=right:50%:border-rounded --color=bg:-1,bg+:#414868,fg:#c0caf5,fg+:#c0caf5,hl:#7aa2f7,hl+:#7dcfff,pointer:#f7768e,marker:#9ece6a,header:#a9b1d6,info:#565f89,prompt:#7aa2f7,spinner:#7dcfff,border:#414868,scrollbar:#414868'
}

# 默认编辑器：让 git / npm edit / crontab 等所有遵循 EDITOR/VISUAL 的工具统一走 nvim
if (-not $env:EDITOR -and $global:__Tools.ContainsKey('nvim')) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}

# yazi 的 MIME 检测依赖 GNU file；官方推荐用 Git for Windows 自带的 file.exe
# （scoop/choco 的独立构建有 Unicode 文件名问题，不采用）。动态探测 Git 安装
# 位置（系统级/用户级安装路径不同），找到后设置 YAZI_FILE_ONE 指向完整路径
# ——MSYS DLL 与 exe 同目录，yazi 直接调起即可，无需 Git Bash 环境。
if (-not $env:YAZI_FILE_ONE -and $global:__Tools.ContainsKey('yazi')) {
    # git 用入口 File.Exists 探测结果（启动路径禁用 Get-Command，见 AGENTS.md）。
    # 注意：不能用 ?. 取值（PS7 专属语法，5.1 兼容模式会解析失败）
    $_gitFromTools = $null
    if ($global:__Tools.ContainsKey('git')) { $_gitFromTools = $global:__Tools['git'].Source }
    foreach ($_git in @(
        $_gitFromTools
        "$env:ProgramFiles\Git\cmd\git.exe"
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )) {
        if (-not $_git) { continue }
        $_fileOne = Join-Path (Split-Path (Split-Path $_git)) 'usr\bin\file.exe'
        if (Test-Path $_fileOne) { $env:YAZI_FILE_ONE = $_fileOne; break }
    }
}
