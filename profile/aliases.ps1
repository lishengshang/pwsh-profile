# ==============================================================
# 导航
# ==============================================================
function ..   { Set-Location .. }
function ...  { Set-Location ../.. }
function .... { Set-Location ../../.. }
function ~    { Set-Location $HOME }
function mkcd ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null; Set-Location $dir }

# ==============================================================
# ls 变体（基于 eza）
# ==============================================================
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls  { eza --icons @args }
    function ll  { eza --icons -l --git @args }
    function la  { eza --icons -la --git @args }
    function lt  { eza --icons --tree --level=2 @args }
    function llt { eza --icons -l --tree --level=2 --git @args }
} else {
    function ll  { Get-ChildItem @args }
    function la  { Get-ChildItem -Force @args }
}

# ==============================================================
# Profile 管理
# ==============================================================
function Edit-Profile   { code $PROFILE }
function Reload-Profile { . $PROFILE }
Set-Alias -Name ep -Value Edit-Profile
Set-Alias -Name rp -Value Reload-Profile -Force

# ==============================================================
# Linux 移植（优先使用现代替代工具）
# ==============================================================
function touch ($file) { New-Item -ItemType File -Path $file -Force | Out-Null }

function which ($cmd) {
    if (-not $cmd) {
        Write-Host "用法: which <命令名称>" -ForegroundColor Yellow
        return
    }
    Get-Command $cmd -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

# grep -> ripgrep (rg)
if (Get-Command rg -ErrorAction SilentlyContinue) {
    function grep { rg @args }
} elseif (-not (Get-Command grep.exe -ErrorAction SilentlyContinue)) {
    function grep { Select-String @args }
}

# find -> fd
if (Get-Command fd -ErrorAction SilentlyContinue) {
    function find { fd @args }
}

# cat -> bat（如果安装了的话）
if (Get-Command bat -ErrorAction SilentlyContinue) {
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
function gquick ($msg) { git add --all; git commit -m $msg; git push }

# ==============================================================
# 网络 / 系统
# ==============================================================
function reboot ($delay = 0) { shutdown.exe /r /t $delay }
function shutdown ($delay = 0) { shutdown.exe /s /t $delay }
function hibernate { shutdown.exe /h }
function sleep { rundll32.exe powrprof.dll,SetSuspendState 0,1,0 }
function lock { rundll32.exe user32.dll,LockWorkStation }
function Get-PublicIP { (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 5).Trim() }
Set-Alias -Name myip -Value Get-PublicIP

function Get-PortProcess ($port) {
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "端口 $port 未被占用" -ForegroundColor Green; return }
    $conns | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        [PSCustomObject]@{ Port = $port; PID = $_.OwningProcess; Process = $proc?.Name }
    }
}
Set-Alias -Name portof -Value Get-PortProcess

function Kill-Port ($port) {
    $conns = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "端口 $port 未被占用" -ForegroundColor Green; return }
    $conns | ForEach-Object {
        $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
        Write-Host "终止: $($proc?.Name) (PID $($_.OwningProcess))" -ForegroundColor Yellow
        Stop-Process -Id $_.OwningProcess -Force
    }
}
Set-Alias -Name killport -Value Kill-Port

# ==============================================================
# 文件工具
# ==============================================================
# unzip -> 7z（更快，支持更多格式）
if (Get-Command 7z -ErrorAction SilentlyContinue) {
    function unzip ($file) { 7z x $file -y -o. @args }
} else {
    function unzip ($file) { Expand-Archive -Path $file -DestinationPath . -Force }
}
function codehere { code . }
Set-Alias -Name ch -Value codehere

# ==============================================================
# 自定义脚本（使用相对路径，避免硬编码）
# ==============================================================
function wallpaper { & "$global:__ProfileDir\Scripts\wallpaper.ps1" @args }
