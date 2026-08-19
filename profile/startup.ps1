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
    $iUser = [char]0xF007   #  fa-user
    $iWin  = [char]0xF17A   #  fa-windows
    $iTerm = [char]0xF120   #  fa-terminal（PS 图标；不用 dev-terminal F62A，部分字体渲染异常）
    $iCpu  = [char]0xF2DB   #  fa-microchip
    $iKeys = [char]0xF11C   #  fa-keyboard-o

    # Solarized 配色（24bit ANSI）；$esc 用 [char]27 而非 `e（后者是 PS7 专属转义）
    $esc    = [char]27
    $cBlue  = '38;2;38;139;210'
    $cGray  = '38;2;101;123;131'

    # 问候：用户名 + 日期（dddd 在中文区域显示中文星期）
    $date = Get-Date -Format 'yyyy-MM-dd dddd'
    Write-Host "$esc[${cBlue}m$iUser Hi $env:USERNAME · $date$esc[0m"

    # 系统信息：OS 名称 + 版本（注册表 ~1ms，避免 WMI 慢调用）。
    # 读取失败（非 Windows/权限异常/路径缺失）时整体降级为内置值。
    # Win11 的 ProductName 常残留 "Windows 10 Pro"（升级/镜像），
    # 用 CurrentBuildNumber >= 22000 判定，并附上 DisplayVersion（23H2/24H2 等）
    $k = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $os = if ($k) { $k.ProductName } else { $null }
    if (-not $os) { $os = 'Windows' }
    $build = 0
    if ($k -and $k.CurrentBuildNumber) {
        [void][int]::TryParse($k.CurrentBuildNumber, [ref]$build)
    }
    if ($build -ge 22000) { $os = $os -replace 'Windows 10', 'Windows 11' }
    if ($k -and $k.DisplayVersion) { $os = "$os $($k.DisplayVersion)" }
    $ver = $PSVersionTable.PSVersion.ToString()
    $cores = [Environment]::ProcessorCount
    Write-Host "$esc[${cGray}m$iWin $os · $iTerm PS $ver · $iCpu $cores 核$esc[0m"

    # 键位速查（fzf 未安装时省略 fzf 相关键位）
    $keys = 'gs 状态 · z 跳转 · .. 上级'
    if ($global:__Tools.ContainsKey('fzf')) {
        $keys = 'Ctrl+t 文件 · Ctrl+r 历史 · Ctrl+g git · ' + $keys
    }
    Write-Host "$esc[${cGray}m$iKeys $keys$esc[0m"
}
