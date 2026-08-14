# ==============================================================
# 启动信息（问候 + 系统信息 + 键位速查）
# 显示在 "Profile loaded in ..." 耗时行之前，由入口在模块加载后调用。
# 全部使用注册表/内置变量等轻量读取（毫秒级），刻意不引入 WMI/CIM
# （Win32_OperatingSystem 等首次调用 ~100ms，会拖慢启动）。
# $env:PROFILE_NO_STARTUP=1 可关闭。
# ==============================================================

function Show-StartupInfo {
    if ($env:PROFILE_NO_STARTUP) { return }

    # 问候：用户名 + 日期（dddd 在中文区域显示中文星期）
    Write-Host "Hi $env:USERNAME · $(Get-Date -Format 'yyyy-MM-dd dddd')" -ForegroundColor Cyan

    # 系统信息：OS 名称（注册表 ~1ms）+ PS 版本 + CPU 核数
    $os = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name ProductName -ErrorAction SilentlyContinue).ProductName
    if (-not $os) { $os = 'Windows' }
    Write-Host "$os · PS $($PSVersionTable.PSVersion.ToString()) · $([Environment]::ProcessorCount) 核" -ForegroundColor DarkGray

    # 键位速查（fzf 未安装时省略 fzf 相关键位）
    $keys = 'gs 状态 · z 跳转 · .. 上级'
    if ($global:__Tools.ContainsKey('fzf')) {
        $keys = 'Ctrl+t 文件 · Ctrl+r 历史 · Ctrl+g git · ' + $keys
    }
    Write-Host $keys -ForegroundColor DarkGray
}
