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
    $iUser = [char]0xF007   #   fa-user
    $iWin  = [char]0xF17A   #   fa-windows
    $iTerm = [char]0xF120   #   fa-terminal（PS 图标；不用 dev-terminal F62A，部分字体渲染异常）
    $iCpu  = [char]0xF2DB   #   fa-microchip
    $iKeys = [char]0xF11C   #   fa-keyboard-o
    $iBolt = [char]0xF0E7   #   fa-bolt

    # Solarized 配色（24bit ANSI）
    $cBlue  = '38;2;38;139;210'
    $cGray  = '38;2;101;123;131'
    $cGreen = '38;2;133;153;0'

    # 问候：用户名 + 日期（dddd 在中文区域显示中文星期）
    $date = Get-Date -Format 'yyyy-MM-dd dddd'
    Write-Host "`e[${cBlue}m$iUser Hi $env:USERNAME · $date`e[0m"

    # 系统信息：OS 名称 + 版本（注册表 ~1ms，避免 WMI 慢调用）
    # Win11 的 ProductName 常残留 "Windows 10 Pro"（升级/镜像），
    # 用 CurrentBuildNumber >= 22000 判定，并附上 DisplayVersion（23H2/24H2 等）
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    $os = $k.ProductName
    if (-not $os) { $os = 'Windows' }
    if ([int]$k.CurrentBuildNumber -ge 22000) { $os = $os -replace 'Windows 10', 'Windows 11' }
    if ($k.DisplayVersion) { $os = "$os $($k.DisplayVersion)" }
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
