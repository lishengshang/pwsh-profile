# ==============================================================
# 环境初始化
# ==============================================================
# 从注册表重建 PATH，避免继承父进程的陈旧 PATH。
# 取舍：会丢弃父进程注入的 PATH（如 IDE 启动器、venv 激活后的入口）。
# 需要保留父进程 PATH 时设置 $env:PROFILE_KEEP_PARENT_PATH=1（见 README「设计说明」）。
if (-not $env:PROFILE_KEEP_PARENT_PATH) {
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
}

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

# 默认编辑器：让 git / npm edit / crontab 等所有遵循 EDITOR/VISUAL 的工具统一走 nvim
if (-not $env:EDITOR -and $global:__Tools.ContainsKey('nvim')) {
    $env:EDITOR = 'nvim'
    $env:VISUAL = 'nvim'
}
