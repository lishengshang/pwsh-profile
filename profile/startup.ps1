# ==============================================================
# 启动信息（问候 + 系统信息 + 键位速查），显示在耗时行之前，由入口调用。
# 只用注册表/内置变量等轻量读取，刻意不引入 WMI/CIM（首次调用 ~100ms 拖慢启动）。
# 图标需要 Nerd Font（见 windows-terminal/README.md）；$env:PROFILE_NO_STARTUP=1 关闭。
# ==============================================================

function Show-StartupInfo {
    if ($env:PROFILE_NO_STARTUP) { return }

    # Nerd Font 图标
    $iUser = [char]0xF007   #  fa-user
    $iWin  = [char]0xF17A   #  fa-windows
    $iTerm = [char]0xF120   #  fa-terminal（PS 图标；不用 dev-terminal F62A，部分字体渲染异常）
    $iCpu  = [char]0xF2DB   #  fa-microchip
    $iKeys = [char]0xF11C   #  fa-keyboard-o

    # Solarized 24bit ANSI；$esc 用 [char]27 而非 `e（后者是 PS7 专属转义）
    $esc    = [char]27
    $cBlue  = '38;2;38;139;210'
    $cGray  = '38;2;101;123;131'

    $date = Get-Date -Format 'yyyy-MM-dd dddd'   # dddd 在中文区域显示中文星期
    Write-Host "$esc[${cBlue}m$iUser Hi $env:USERNAME · $date$esc[0m"

    # Win11 的 ProductName 常残留 "Windows 10 Pro"，用 CurrentBuildNumber >= 22000 判定，
    # 并附 DisplayVersion（23H2/24H2 等）；读注册表失败整体降级为内置值
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
