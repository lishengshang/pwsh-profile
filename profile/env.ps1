# ==============================================================
# 环境初始化（PATH 重建在入口的工具探测之前，本文件只管 fnm / EDITOR / fzf）
# ==============================================================

# fnm（Node 版本管理）两段式：default 版本目录（junction）前置 PATH 作静态兜底，
# 首次调用 node/npm/npx/corepack 才执行 fnm env。fnm env 输出不可跨会话缓存——
# FNM_MULTISHELL_PATH 每进程独立，复用会让新终端指向已销毁的目录。
# PROFILE_NO_FNM=1 完全跳过。
if ($global:__Tools.ContainsKey('fnm') -and -not $env:PROFILE_NO_FNM) {
    $_fnmDefault = Join-Path $env:APPDATA 'fnm\aliases\default'
    if (Test-Path $_fnmDefault) { $env:PATH = "$_fnmDefault;$env:PATH" }

    $script:__fnmReady = $false
    # 占位函数：首次调用触发初始化。不能用 zoxide 那种「init 重定义自身」模式——
    # fnm env 只设环境变量不重定义命令，须显式按 Application 解析避开占位函数自身。
    function __Ensure-Fnm ([string]$Cmd) {
        if (-not $script:__fnmReady) {
            $script:__fnmReady = $true
            Remove-Item "$env:TEMP\fnm-init-cache.ps1" -ErrorAction SilentlyContinue
            $out = & $global:__Tools['fnm'].Source env --use-on-cd --shell powershell 2>$null | Out-String
            if ($out) {
                # fnm env 会把生成时的 PATH 快照写进 $env:PATH，恢复后只前置本进程 shim 目录
                $_cleanPath = $env:PATH
                Invoke-Expression $out | Out-Null
                $env:PATH = $_cleanPath
                if ($env:FNM_MULTISHELL_PATH) {
                    $env:PATH = "$env:FNM_MULTISHELL_PATH;$env:PATH"
                }
            }
            # 补一次当前目录版本解析，等价 use-on-cd 的进入行为
            if ($out -and ((Test-Path .nvmrc) -or (Test-Path .node-version) -or (Test-Path package.json))) {
                & $global:__Tools['fnm'].Source use --silent-if-unchanged 2>$null
            }
        }
        $real = Get-Command $Cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($real) { & $real.Source @args }
        else { Write-Host "找不到 $Cmd（fnm 未安装任何 Node 版本？运行 fnm install <版本>）" -ForegroundColor Yellow }
    }
    function node     { __Ensure-Fnm node @args }
    function npm      { __Ensure-Fnm npm @args }
    function npx      { __Ensure-Fnm npx @args }
    function corepack { __Ensure-Fnm corepack @args }
}

# fzf 配色 Tokyo Night。bg:-1 = 用终端默认背景（不绘制实色块），壁纸半透明才透得出来；
# fzf 不接受 bg:default，必须用 -1。用户已设 FZF_DEFAULT_OPTS 时不覆盖。
if (-not $env:FZF_DEFAULT_OPTS) {
    $env:FZF_DEFAULT_OPTS = '--height=40% --layout=reverse --border=rounded --preview-window=right:50%:border-rounded --color=bg:-1,bg+:#414868,fg:#c0caf5,fg+:#c0caf5,hl:#7aa2f7,hl+:#7dcfff,pointer:#f7768e,marker:#9ece6a,header:#a9b1d6,info:#565f89,prompt:#7aa2f7,spinner:#7dcfff,border:#414868,scrollbar:#414868'
}

# 统一 git / npm edit / crontab 等工具的编辑器
if (-not $env:EDITOR -and $global:__Tools.ContainsKey('nvim')) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}

# yazi 的 MIME 检测依赖 GNU file；官方推荐用 Git for Windows 自带的 file.exe
# （scoop/choco 的独立构建有 Unicode 文件名问题）。Git 安装位置每设备不同，动态探测。
if (-not $env:YAZI_FILE_ONE -and $global:__Tools.ContainsKey('yazi')) {
    # 用入口的 File.Exists 探测结果（启动路径禁用 Get-Command，见 AGENTS.md）
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
