# ==============================================================
# 导航
# ==============================================================
function ..   { Set-Location .. }
function ...  { Set-Location ../.. }
function .... { Set-Location ../../.. }
# 注：PowerShell 原生支持 `cd ~`，故不再定义 ~ 函数（函数名 ~ 永远不会被解析）
function mkcd ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }

# yazi 文件管理器：退出时 cd 到最后浏览的目录（官方 PowerShell 集成写法）
if ($global:__Tools.ContainsKey('yazi')) {
    function y {
        $tmp = [System.IO.Path]::GetTempFileName()
        try {
            yazi $args --cwd-file="$tmp"
            $cwd = Get-Content -Path $tmp -ErrorAction SilentlyContinue
            if (-not [String]::IsNullOrEmpty($cwd) -and $cwd -ne $PWD.Path) {
                Set-Location -LiteralPath ([System.IO.Path]::GetFullPath($cwd))
            }
        } finally {
            Remove-Item -Path $tmp -ErrorAction SilentlyContinue
        }
    }
}

# ==============================================================
# ls 变体（基于 eza）
# ==============================================================
if ($global:__Tools.ContainsKey('eza')) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls  { eza --icons @args }
    function ll  { eza --icons -l --git @args }
    function la  { eza --icons -la --git @args }
    function lt  { eza --icons --tree --level=2 @args }
    function llt { eza --icons -l --tree --level=2 --git @args }
} else {
    # eza 缺失：回退 Get-ChildItem。Terminal-Icons 延迟到首次 ls 调用时才加载
    # （该模块加载很重 ~100-400ms，不能进启动路径）；缺失或加载失败时静默降级为无图标
    $script:__TerminalIconsLoaded = $false
    function __Ensure-TerminalIcons {
        if ($script:__TerminalIconsLoaded) { return }
        $script:__TerminalIconsLoaded = $true
        # 临时压低 ErrorActionPreference，避免模块内部错误（如设置目录不可写）刷屏
        $_eap = $ErrorActionPreference
        $ErrorActionPreference = 'SilentlyContinue'
        try { Import-Module Terminal-Icons -ErrorAction SilentlyContinue } finally { $ErrorActionPreference = $_eap }
    }
    function ls  { __Ensure-TerminalIcons; Get-ChildItem @args }
    function ll  { __Ensure-TerminalIcons; Get-ChildItem @args }
    function la  { __Ensure-TerminalIcons; Get-ChildItem -Force @args }
    function lt  { __Ensure-TerminalIcons; Get-ChildItem -Recurse -Depth 1 @args }
    function llt { __Ensure-TerminalIcons; Get-ChildItem -Recurse -Depth 1 @args }
}

# ==============================================================
# Profile 管理
# ==============================================================
# 使用未批准动词会触发警告，故采用普通命名 + 别名；code 缺失时回退 $EDITOR
function profile-edit {
    if (Get-Command code -ErrorAction SilentlyContinue) { code $PROFILE }
    elseif ($env:EDITOR) { & $env:EDITOR $PROFILE }
    else { Write-Host '未找到 code 且未设置 $EDITOR' -ForegroundColor Yellow }
}
Set-Alias -Name ep -Value profile-edit -Force

# 多设备同步：拉取本 profile 仓库的最新配置（重开终端生效；nvim 插件重开 nvim 自动对齐）
function psync {
    if (-not (Test-Path (Join-Path $global:__ProfileDir '.git'))) {
        Write-Host "当前 profile 目录不是 git 仓库（$($global:__ProfileDir)），请到本机仓库克隆目录手动 git pull。" -ForegroundColor Yellow
        return
    }
    git -C $global:__ProfileDir pull --rebase @args
    if ($LASTEXITCODE -eq 0) {
        # git 的原子写入会替换仓库文件 inode、弄断文件类硬链接，拉取后自动修复
        $repair = Join-Path $global:__ProfileDir 'Scripts\Repair-ConfigLinks.ps1'
        if (Test-Path $repair) { & $repair }
        Write-Host '配置已同步。重开终端生效；nvim 配置有变时重开 nvim 自动安装插件。' -ForegroundColor Cyan
    }
}

# ==============================================================
# Linux 移植（优先使用现代替代工具）
# ==============================================================
function touch ($file) { New-Item -ItemType File -Path $file -Force | Out-Null }

function which ($cmd) {
    if (-not $cmd) {
        Write-Host "用法: which <命令名称>" -ForegroundColor Yellow
        return
    }
    $c = Get-Command $cmd -ErrorAction SilentlyContinue
    if (-not $c) {
        Write-Host "未找到命令: $cmd" -ForegroundColor Yellow
        return
    }
    $c | Select-Object -ExpandProperty Source
}

# grep -> ripgrep (rg)
if ($global:__Tools.ContainsKey('rg')) {
    function grep { rg @args }
} elseif (-not $global:__Tools.ContainsKey('grep')) {
    function grep { Select-String @args }
}

# find -> fd（使用别名而非函数，避免覆盖 find.exe 在脚本中的显式调用）
if ($global:__Tools.ContainsKey('fd')) {
    Set-Alias -Name find -Value fd -Force -Option AllScope
}

# cat -> bat（如果安装了的话）
if ($global:__Tools.ContainsKey('bat')) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat @args }
}

# ==============================================================
# Git
# ==============================================================
function gs   { git status }
function ga   { git add @args }
function gaa  { git add --all }
function gcm  { git commit -m @args }
function gc   { git commit @args }
function gp   { git push @args }
function gpl  { git pull @args }
function gl   { git log --oneline --graph --decorate --all @args }
function gd   { git diff @args }
function gds  { git diff --staged @args }
function gco  { git checkout @args }
function gcb  { git checkout -b @args }
function gb   { git branch @args }
function gst  { git stash @args }
function grs  { git restore @args }
function gbn  { git rev-parse --abbrev-ref HEAD }
function gquick ($msg) {
    if (-not $msg) { Write-Host "用法: gquick <commit message>" -ForegroundColor Yellow; return }
    git add --all
    if ($LASTEXITCODE -ne 0) { return }
    git commit -m $msg
    if ($LASTEXITCODE -ne 0) { return }
    git push
}

# 详细日志（图形 + 颜色 + 日期/作者）
function glog {
    git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' @args
}

function gup { git pull --rebase @args }

# lazygit 终端 UI（LazyVim 内 <leader>gg 调起的也是它）
if ($global:__Tools.ContainsKey('lazygit')) {
    function lg { lazygit @args }
}

# 清理已合并到当前分支的本地分支（保护 main/master/dev/develop 与当前分支）
function gclean {
    git branch --merged | Where-Object { $_ -notmatch '^\*' -and $_ -notmatch '\b(main|master|dev|develop)\b' } |
        ForEach-Object { git branch -d $_.Trim() }
}

# ==============================================================
# 网络 / 系统（避免覆盖系统命令，使用 ps- 前缀）
# ==============================================================
function ps-reboot    ($delay = 0) { shutdown.exe /r /t $delay }
function ps-shutdown  ($delay = 0) { shutdown.exe /s /t $delay }
function ps-hibernate { shutdown.exe /h }
function ps-suspend   { rundll32.exe powrprof.dll,SetSuspendState Sleep }
function ps-lock      { rundll32.exe user32.dll,LockWorkStation }
Set-Alias -Name lock -Value ps-lock

function Get-PublicIP {
    # 备用 API 链：ifconfig.me 在大陆网络经常不可达，逐个尝试
    $apis = @('https://ifconfig.me/ip', 'https://api.ipify.org', 'https://ipinfo.io/ip')
    foreach ($u in $apis) {
        try {
            return (Invoke-RestMethod -Uri $u -TimeoutSec 5).Trim()
        } catch { }
    }
    Write-Host '无法获取公网 IP（网络问题或所有 API 均不可达）' -ForegroundColor Yellow
}
Set-Alias -Name myip -Value Get-PublicIP

# winget 一键升级全部已安装工具
function wup {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host '未找到 winget（需要 Windows 10 1809+ 的 App Installer）' -ForegroundColor Yellow
        return
    }
    winget upgrade --all @args
}

# 一键更新 PSGallery 模块（与 wup 对应；模块升级后需新开终端生效，
# 旧会话残留的 $PSCompletions 等全局变量会让新版本模块跳过初始化）
function wum {
    foreach ($_m in 'PSCompletions','PSFzf','Terminal-Icons') {
        if (Get-Module -ListAvailable -Name $_m) {
            Write-Host "更新: $_m" -ForegroundColor Cyan
            Update-Module -Name $_m -Scope CurrentUser -Force
        }
    }
    Write-Host '模块更新完成，请新开终端生效。' -ForegroundColor Cyan
}

function Get-PortProcess ($port) {
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "端口 $port 未被占用" -ForegroundColor Green; return }
    $conns | Sort-Object OwningProcess -Unique | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        $pname = if ($proc) { $proc.Name }
        [PSCustomObject]@{ Port = $port; PID = $_.OwningProcess; Process = $pname }
    }
}
Set-Alias -Name portof -Value Get-PortProcess

function Stop-Port ($port) {
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "端口 $port 未被占用" -ForegroundColor Green; return }
    $conns.OwningProcess | Sort-Object -Unique | ForEach-Object {
        $proc = Get-Process -Id $_ -ErrorAction SilentlyContinue
        $pname = if ($proc) { $proc.Name }
        Write-Host "终止: $pname (PID $_)" -ForegroundColor Yellow
        Stop-Process -Id $_ -Force
    }
}
Set-Alias -Name killport -Value Stop-Port

# ==============================================================
# 文件工具
# ==============================================================
# unzip -> 7z（更快，支持更多格式）
if ($global:__Tools.ContainsKey('7z')) {
    function unzip ($file) { 7z x $file -y -o. @args }
} else {
    function unzip ($file) { Expand-Archive -Path $file -DestinationPath . -Force }
}
function codehere {
    if (Get-Command code -ErrorAction SilentlyContinue) { code . }
    elseif ($env:EDITOR) { & $env:EDITOR . }
    else { Write-Host '未找到 code 且未设置 $EDITOR' -ForegroundColor Yellow }
}
Set-Alias -Name ch -Value codehere

# ==============================================================
# 自定义脚本（使用相对路径，避免硬编码）
# ==============================================================
function wallpaper { & "$global:__ProfileDir\Scripts\wallpaper.ps1" @args }
