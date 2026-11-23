# ==============================================================
# 环境初始化（fnm、Conda、EDITOR、fzf、Yazi）
# ==============================================================

# fnm 的 shim 路径属于当前进程，收到需要版本环境的命令时再生成。
if ($global:__Tools.ContainsKey('fnm') -and -not $env:PROFILE_NO_FNM) {
    $_fnmDefault = Join-Path $env:APPDATA 'fnm\aliases\default'
    if (Test-Path -LiteralPath $_fnmDefault) { $env:PATH = "$_fnmDefault;$env:PATH" }

    $script:__fnmReady = $false
    $script:__fnmDirectory = $null

    function __Initialize-FnmEnv {
        if ($script:__fnmReady) { return $true }

        $fnmExe = $global:__Tools['fnm'].Source
        $originalPath = $env:PATH
        $originalShim = $env:FNM_MULTISHELL_PATH
        try {
            $out = & {
                # Windows PowerShell 5.1 把 fnm 已重定向的版本提示视为错误流。
                $ErrorActionPreference = 'Continue'
                $PSNativeCommandUseErrorActionPreference = $false
                & $fnmExe env --use-on-cd --shell powershell 2>$null | Out-String
            }
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($out)) { return $false }

            $hook = [scriptblock]::Create($out)
            . $hook | Out-Null
            $script:__fnmReady = [bool]$env:FNM_MULTISHELL_PATH
        }
        catch {
            Write-Debug "fnm 会话初始化失败：$_"
        }
        finally {
            if ($script:__fnmReady) {
                $env:PATH = "$env:FNM_MULTISHELL_PATH;$originalPath"
            }
            else {
                $env:FNM_MULTISHELL_PATH = $originalShim
                $env:PATH = $originalPath
            }
        }
        $script:__fnmReady
    }

    function __Set-FnmProjectVersion {
        if ($PWD.Provider.Name -ne 'FileSystem' -or $PWD.ProviderPath -eq $script:__fnmDirectory) { return }
        $script:__fnmDirectory = $PWD.ProviderPath

        # cd 的官方钩子会经过 fnm；其他导航入口在下一次 Node 命令前检查版本。
        if ($env:FNM_VERSION_FILE_STRATEGY -eq 'recursive' -or
            (Test-Path -LiteralPath .nvmrc) -or (Test-Path -LiteralPath .node-version) -or
            (Test-Path -LiteralPath package.json)) {
            $previousExitCode = $global:LASTEXITCODE
            try {
                $null = & {
                    $ErrorActionPreference = 'Continue'
                    $PSNativeCommandUseErrorActionPreference = $false
                    & $global:__Tools['fnm'].Source use --silent-if-unchanged 2>$null
                }
            }
            catch {
                Write-Debug "fnm 项目版本切换失败：$_"
            }
            finally {
                $global:LASTEXITCODE = $previousExitCode
            }
        }
    }

    function fnm {
        $commandIndex = 0
        $optionsWithValue = '--node-dist-mirror', '--fnm-dir', '--log-level', '--arch', '--version-file-strategy'
        # 仅识别子命令的位置，原始参数仍由 fnm 完整解析。
        while ($commandIndex -lt $args.Count -and $args[$commandIndex] -clike '--*') {
            $option = $args[$commandIndex]
            if ($option -cin '--', '--help', '--version') { break }
            $commandIndex++
            if ($option -cin $optionsWithValue -or
                ($option -ceq '--resolve-engines' -and $commandIndex -lt $args.Count -and
                    $args[$commandIndex] -cin 'true', 'false')) {
                $commandIndex++
            }
        }
        $subcommand = if ($commandIndex -lt $args.Count) { $args[$commandIndex] }
        $installsVersion = $subcommand -in 'install', 'i'
        $activatesVersion = $subcommand -eq 'use' -or ($installsVersion -and '--use' -in $args)
        if ($activatesVersion -or $subcommand -eq 'current') {
            if (-not (__Initialize-FnmEnv)) {
                if (!$LASTEXITCODE) { $global:LASTEXITCODE = 1 }
                Write-Warning 'fnm 会话初始化失败。请检查 fnm env 的输出后重试。'
                return
            }
            if ($subcommand -eq 'current') { __Set-FnmProjectVersion }
        }
        & $global:__Tools['fnm'].Source @args
        if ($LASTEXITCODE -eq 0) {
            if ($activatesVersion -and $PWD.Provider.Name -eq 'FileSystem') {
                $script:__fnmDirectory = $PWD.ProviderPath
            }
            elseif ($installsVersion) {
                # 之前的项目版本可能尚未安装，下次使用 Node 时重新选择。
                $script:__fnmDirectory = $null
            }
        }
    }

    function __Invoke-FnmNode {
        param([string]$Command)

        if (__Initialize-FnmEnv) { __Set-FnmProjectVersion }
        $real = Get-Command $Command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($real) { & $real.Source @args }
        else { Write-Host "找不到 $Command（fnm 未安装任何 Node 版本？运行 fnm install <版本>）" -ForegroundColor Yellow }
    }

    function node {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidOverwritingBuiltInCmdlets', 'node',
            Justification = 'fnm 占位转发函数，非 PowerShell 内置命令')]
        param()
        __Invoke-FnmNode node @args
    }
    function npm      { __Invoke-FnmNode npm @args }
    function npx      { __Invoke-FnmNode npx @args }
    function corepack { __Invoke-FnmNode corepack @args }
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

if (-not $env:PROFILE_NO_CONDA -and $global:__Tools.ContainsKey('conda')) {
    function conda {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingInvokeExpression', '',
            Justification = 'Conda 官方 hook 必须在当前会话执行才能导入模块并设置环境')]
        param()

        $autoActivate = $env:CONDA_AUTO_ACTIVATE
        $legacyAutoActivate = $env:CONDA_AUTO_ACTIVATE_BASE
        $changePs1 = $env:CONDA_CHANGEPS1
        $condaExe = $global:__Tools['conda'].Source
        try {
            # 新旧 Conda 都识别 AUTO_ACTIVATE_BASE，同时设两个同义键会报错。
            $env:CONDA_AUTO_ACTIVATE = $null
            $env:CONDA_AUTO_ACTIVATE_BASE = 'false'
            # 提示符由 Starship 管理，首次导入 Conda 时不能接管 prompt。
            $env:CONDA_CHANGEPS1 = 'false'
            $hook = & $condaExe shell.powershell hook | Out-String
        }
        finally {
            $env:CONDA_AUTO_ACTIVATE = $autoActivate
            $env:CONDA_AUTO_ACTIVATE_BASE = $legacyAutoActivate
            $env:CONDA_CHANGEPS1 = $changePs1
        }
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($hook)) {
            throw "Conda hook 生成失败：$condaExe（退出码 $LASTEXITCODE）"
        }
        & {
            $ErrorActionPreference = 'Stop'
            Invoke-Expression $hook
        }
        # 后续调用由模块导出的同名别名接管。首次显式转发，避免递归进入占位函数。
        Conda\Invoke-Conda @args
    }
}
