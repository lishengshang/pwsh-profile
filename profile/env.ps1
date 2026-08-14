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

# fzf UI 美化（Solarized 配色 + 高度/反向/圆角边框/预览窗）
# 用户已自行设置 FZF_DEFAULT_OPTS 时不覆盖；fzf 官方参数，PSFzf/命令行 fzf 均生效
if (-not $env:FZF_DEFAULT_OPTS) {
    $env:FZF_DEFAULT_OPTS = '--height=40% --layout=reverse --border=rounded --preview-window=right:50%:border-rounded --color=bg:#002B36,bg+:#073642,fg:#839496,fg+:#93A1A1,hl:#268BD2,hl+:#2AA198,pointer:#CB4B16,marker:#DC322F,header:#586E75,info:#586E75,prompt:#268BD2,spinner:#2AA198,border:#586E75,scrollbar:#586E75'
}

# 默认编辑器：让 git / npm edit / crontab 等所有遵循 EDITOR/VISUAL 的工具统一走 nvim
if (-not $env:EDITOR -and $global:__Tools.ContainsKey('nvim')) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}
