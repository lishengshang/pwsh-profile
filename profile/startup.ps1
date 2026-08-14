# ==============================================================
# 启动信息（问候 + 系统信息 + 键位速查 + 耗时）
# 显示在 "Profile loaded in ..." 耗时行之前，由入口在模块加载后调用。
# 全部使用注册表/内置变量等轻量读取（毫秒级），刻意不引入 WMI/CIM
# （Win32_OperatingSystem 等首次调用 ~100ms，会拖慢启动）。
# 图标需要 Nerd Font 字体（见 windows-terminal/README.md）。
# $env:PROFILE_NO_STARTUP=1 可关闭。
# ==============================================================

function Show-StartupInfo {
    if ($env:PROFILE_NO_STARTUP) { return }

    # Nerd Font 图标
    $iUser   = [char]0xF007   #   fa-user
    $iWin    = [char]0xF17A   #   fa-windows
    $iTerm   = [char]0xF62A   #   dev-terminal
    $iCpu    = [char]0xF2DB   #   fa-microchip
    $iKeys   = [char]0xF11C   #   fa-keyboard-o
    $iBolt   = [char]0xF0E7   #   fa-bolt

    # Solarized 配色（24bit ANSI）
    $cBlue  = '38;2;38;139;210'
    $cGray  = '38;2;101;123;131'
    $cGreen = '38;2;133;153;0'

    # 问候：用户名 + 日期（dddd 在中文区域显示中文星期）
    $date = Get-Date -Format 'yyyy-MM-dd dddd'
    Write-Host "`e[${cBlue}m$iUser Hi $env:USERNAME · $date`e[0m"

    # 系统信息：OS 名称（注册表 ~1ms）+ PS 版本 + CPU 核数
    $os = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ProductName -ErrorAction SilentlyContinue).ProductName
    if (-not $os) { $os = 'Windows' }
    $ver = $PSVersionTable.PSVersion.ToString()
    $cores = [Environment]::ProcessorCount
    Write-Host "`e[${cGray}m$iWin $os · $iTerm PS $ver · $iCpu $cores 核`e[0m"

    # 键位速查（fzf 未安装时省略 fzf 相关键位）
    $keys = 'gs 状态 · z 跳转 · .. 上级'
    if ($global:__Tools.ContainsKey('fzf')) {
        $keys = 'Ctrl+t 文件 · Ctrl+r 历史 · Ctrl+g git · ' + $keys
    }
    Write-Host "`e[${cGray}m$iKeys $keys`e[0m"
}
