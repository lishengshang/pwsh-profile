#Requires -Version 5.1
<#
.SYNOPSIS
    在全新 Windows 机器上从零引导：装 PowerShell 7 → 装 Git → 克隆仓库 → 运行 setup.ps1。
.DESCRIPTION
    只需在系统自带的 Windows PowerShell 5.1（powershell.exe）里执行一次，
    适合"别人拿到这个项目"的第一条命令。默认克隆到 $HOME\Documents\PowerShell
    （pwsh 的 $PROFILE 目录），因此 profile 直接生效，setup.ps1 会跳过文件链接只装工具。
.PARAMETER RepoUrl
    仓库地址，默认本仓库（https://github.com/lishengshang/pwsh-profile.git）。
.PARAMETER RepoDir
    克隆目标目录，默认 $HOME\Documents\PowerShell。
.PARAMETER SkipTools
    透传给 setup.ps1，跳过工具与模块安装。
.PARAMETER Minimal / Full / Components / SkipComponents
    透传给 setup.ps1 的组件选择（含义见 setup.ps1；默认 Standard = core+completion+gitui）。
.PARAMETER Yes
    透传给 setup.ps1：跳过交互式安装向导，完全非交互（脚本/CI 自动化用；
    不指定时交互终端会进入向导：简介 → 组件勾选 → 工具预览 → 确认）。
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File bootstrap.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -Full
#>
# CmdletBinding：让 -? 显示本帮助而非直接执行（param() 上方才生效）
[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://github.com/lishengshang/pwsh-profile.git',
    [string]$RepoDir = (Join-Path $HOME 'Documents\PowerShell'),
    [switch]$SkipTools,
    [switch]$Minimal,
    [switch]$Full,
    [string[]]$Components,
    [string[]]$SkipComponents,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

function Assert-Tool {
    param([string]$Name, [string]$Id)
    if (Get-Command $Name -ErrorAction SilentlyContinue) {
        Write-Host "已安装: $Name" -ForegroundColor DarkGray
        return
    }
    Write-Host "正在安装: $Name ($Id) ..." -ForegroundColor Cyan
    winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "安装 $Name 失败（exit $LASTEXITCODE），可稍后手动安装后重试"
    }
    # 刚装完的工具不会自动出现在当前进程 PATH，从注册表（Machine+User）重建
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('PATH', 'User')
}

# winget 安装的工具可能不在注册表 PATH（如 per-user 安装到固定目录），兜底探测
function Get-ToolPath ([string]$Name, [string[]]$Fallbacks) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in $Fallbacks) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    return $null
}

# 1. winget（Windows 10 1809+ 自带 App Installer）
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw '未找到 winget：需要 Windows 10 1809+ 的 App Installer，请先从 Microsoft Store 安装。'
}

# 2. PowerShell 7 + Git
Assert-Tool 'pwsh' 'Microsoft.PowerShell'
Assert-Tool 'git' 'Git.Git'

# git 解析（PATH 重建后仍找不到时兜底常见安装路径，git clone 依赖它）
$gitPath = Get-ToolPath 'git' @(
    "$env:ProgramFiles\Git\cmd\git.exe"
    "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
)
if (-not $gitPath) {
    throw '找不到 git（PATH 与常见安装路径均无）。请重新打开终端后重试，或手动安装 Git。'
}

# 3. 克隆仓库
if (Test-Path (Join-Path $RepoDir '.git')) {
    Write-Host "仓库已存在于 $RepoDir，跳过克隆。" -ForegroundColor DarkGray
}
elseif (Test-Path $RepoDir) {
    Write-Warning "$RepoDir 已存在且非空（可能已有其他配置）。请先备份/移走该目录后重试，或用 -RepoDir 指定其他目录。"
    return
}
else {
    New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
    Write-Host "正在克隆: $RepoUrl -> $RepoDir" -ForegroundColor Cyan
    & $gitPath clone $RepoUrl $RepoDir
    if ($LASTEXITCODE -ne 0) { throw "克隆失败：$RepoUrl" }
}

# 4. 运行 setup.ps1（刚装的 pwsh 可能不在 PATH，用完整路径兜底）
$setup = Join-Path $RepoDir 'setup.ps1'
if (-not (Test-Path $setup)) { throw "未找到 $setup" }

# 已运行在 pwsh 中时直接复用当前实例（不依赖 PATH，兼容"用户已装 pwsh"的场景）
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $pwshPath = Join-Path $PSHOME 'pwsh.exe'
}
else {
    $pwshPath = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if (-not $pwshPath) {
        $pwshPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    }
}
if (-not (Test-Path $pwshPath)) {
    Write-Warning "找不到 pwsh（$pwshPath）。请重新打开终端后再运行: .\setup.ps1"
    return
}

# 透传组件选择参数给 setup.ps1
# 注意：pwsh -File 下数组参数不会贪心收集后续 token——'-Components','a','b' 只会
# 绑定 a、丢弃 b。多值参数必须 join 成单个逗号分隔字符串（setup.ps1 侧会拆分）
$setupArgs = @('-NoProfile', '-File', $setup)
if ($SkipTools)      { $setupArgs += '-SkipTools' }
if ($Minimal)        { $setupArgs += '-Minimal' }
if ($Full)           { $setupArgs += '-Full' }
if ($Components)     { $setupArgs += '-Components', ($Components -join ',') }
if ($SkipComponents) { $setupArgs += '-SkipComponents', ($SkipComponents -join ',') }
if ($Yes)            { $setupArgs += '-Yes' }
& $pwshPath @setupArgs

Write-Host "`n引导完成。请关闭本窗口，打开 Windows Terminal 或新的 PowerShell 7 窗口。" -ForegroundColor Cyan
