# ==============================================================
# 环境初始化
# ==============================================================
# 注：PATH 重建已提前到入口（Microsoft.PowerShell_profile.ps1）的
# 工具探测之前执行，此处只处理 fnm 缓存与默认编辑器。

# fnm (Node 版本管理) -- 缓存 7 天 + 升级即失效，原子写入
if (Initialize-CachedInit -Command 'fnm' -CacheFile "$env:TEMP\fnm-init-cache.ps1" -Arguments @('env','--use-on-cd','--shell','powershell')) {
    # 缓存里的 $env:PATH 是生成时的快照，会覆盖上面刷新的 PATH；
    # 只取 FNM_* 变量，PATH 用已刷新的值 + fnm shim 前置
    $_cleanPath = $env:PATH
    . "$env:TEMP\fnm-init-cache.ps1"
    $env:PATH = $_cleanPath
    if ($env:FNM_MULTISHELL_PATH) {
        $env:PATH = "$env:FNM_MULTISHELL_PATH;$env:PATH"
    }
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
    foreach ($_git in @(
        (Get-Command git -ErrorAction SilentlyContinue).Source
        "$env:ProgramFiles\Git\cmd\git.exe"
        "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
    )) {
        if (-not $_git) { continue }
        $_fileOne = Join-Path (Split-Path (Split-Path $_git)) 'usr\bin\file.exe'
        if (Test-Path $_fileOne) { $env:YAZI_FILE_ONE = $_fileOne; break }
    }
}
