<#
.SYNOPSIS
    安装 PowerShell profile 到当前用户的 PowerShell 配置目录。
.DESCRIPTION
    1. 把仓库中的 profile 文件链接到 $PROFILE 目录（无符号链接权限时回退复制模式）；
       链接目标按运行时 $PROFILE 动态解析，5.1 部署到 Documents\WindowsPowerShell\，
       与 PS7 互不影响。仓库目录本身即 $PROFILE 目录时跳过文件链接，只装工具。
    2. 按所选组件用 winget 装依赖工具、Install-Module 装模块（-SkipTools 跳过下载；
       工具均为可选依赖，缺失时 profile 自动降级）。
    3. 无显式组件参数且处于交互终端时进入安装向导（-Yes / 非交互环境自动跳过）。

    组件决定装哪些工具/模块、链接哪些外部配置；profile 本体（Core）始终部署。
    各参数的含义与预设见 docs/reference.md「参数一览」，此处不重复维护。
#>
#Requires -Version 5.1
# 须在帮助块之后：放在首位会让 Get-Help / -? 读不到本块
# CmdletBinding(PositionalBinding=$false)：禁止位置绑定。否则 "-Components core gitui"
# 的 gitui 会被位置绑定到 SkipComponents——语义反转为"剔除 gitui"且无任何告警，必须报错。
# 注意：该特性必须放在 param() 上方才生效（放 param() 内部时 PositionalBinding 不起作用）。
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipTools,
    [switch]$Minimal,
    [switch]$Full,
    [string[]]$Components,
    [string[]]$SkipComponents,
    [switch]$Yes,
    [switch]$Wizard,
    [string[]]$ExcludeTools
)

$ErrorActionPreference = 'Stop'

# ================= 组件选择（多级别下载/安装粒度）=================
# 组件决定装哪些工具/模块、链接哪些外部配置。profile 本体（Core 条目）始终部署，
# 未装的工具运行时被 $global:__Tools.ContainsKey 守卫自动降级，故装不装即等于
# 有没有该功能，无需改 profile 代码。
#   -Minimal = core；-Full = 全部；无开关 = Standard（core+completion+gitui）
$allComponents      = 'core', 'completion', 'editor', 'files', 'gitui'
$standardComponents = 'core', 'completion', 'gitui'

# 解析矩阵单源在 Scripts/Resolve-SetupComponents.ps1（可测试单元；
# __NormalizeComponents 也定义在此，-ExcludeTools 归一化复用）
. (Join-Path $PSScriptRoot 'Scripts\Resolve-SetupComponents.ps1')
$componentChoice = Resolve-SetupComponents -AllComponents $allComponents `
    -StandardComponents $standardComponents -Minimal:$Minimal -Full:$Full `
    -Components $Components -SkipComponents $SkipComponents -Yes:$Yes -Wizard:$Wizard
$effectiveComponents = $componentChoice.Components
$pendingWizard = $componentChoice.PendingWizard

$repoDir = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$profileDir = [System.IO.Path]::GetFullPath((Split-Path $PROFILE)).TrimEnd('\')
# backup-<时间戳> 备份目录由 Invoke-ConfigLinkDeployment 按需创建（返回 BackupDir）

# 管理链接清单（唯一事实来源，Scripts/Get-ManagedLinks.ps1）：
#   Core 条目部署 $PROFILE 本体（仓库即 $PROFILE 目录时整组跳过）；
#   外部条目（starship/lazygit/yazi/nvim）即使仓库即 $PROFILE 目录也照常链接；
#   SkipIfExists：目标已存在时不动它（用户自己的配置优先），仅缺失时引入仓库默认。
$linkItems = @(. (Join-Path $repoDir 'Scripts\Get-ManagedLinks.ps1'))
# 按组件选择过滤外部配置；Core 条目是 profile 本体，始终部署
# 防呆：既非 Core 又无合法 Component 的条目会被静默跳过，提前告警（同 $wingetTools）
foreach ($l in $linkItems) {
    if (-not $l.Core -and $l.Component -notin $allComponents) {
        Write-Warning "链接条目 '$($l.Source)' 既非 Core 也无合法 Component，它不会被链接——请修正 Get-ManagedLinks.ps1。"
    }
}
$linkItems = @($linkItems | Where-Object { $_.Core -or ($effectiveComponents -contains $_.Component) })

# winget 工具清单（与 docs/reference.md「依赖工具」表保持一致）
# 每项的 Component 决定它属于哪个安装组件；Desc 是向导与安装日志里的一句话用途；
# Optional = 纯增强不影响核心体验，向导标注「可剔除」。
$wingetTools = @(
    @{ Name = 'Starship';   Id = 'Starship.Starship';               Component = 'core'; Desc = '提示符主题' }
    @{ Name = 'eza';        Id = 'eza-community.eza';               Component = 'core'; Desc = '文件列表（图标 + git 状态）' }
    @{ Name = 'zoxide';     Id = 'ajeetdsouza.zoxide';              Component = 'core'; Desc = '智能目录跳转（z）' }
    @{ Name = 'ripgrep';    Id = 'BurntSushi.ripgrep.MSVC';         Component = 'core'; Desc = '内容搜索（grep）' }
    @{ Name = 'fd';         Id = 'sharkdp.fd';                      Component = 'core'; Desc = '文件查找（find）' }
    @{ Name = 'bat';        Id = 'sharkdp.bat';                     Component = 'core'; Desc = '文件高亮查看（cat）' }
    @{ Name = '7-Zip';      Id = '7zip.7zip';                       Component = 'core'; Desc = '解压（unzip）' }
    @{ Name = 'fnm';        Id = 'Schniz.fnm';                      Component = 'core'; Desc = 'Node.js 版本管理'; Optional = $true }
    @{ Name = 'fzf';        Id = 'junegunn.fzf';                    Component = 'completion'; Desc = '模糊查找（Ctrl+t 文件 / Ctrl+r 历史）' }
    @{ Name = 'Neovim';     Id = 'Neovim.Neovim';                   Component = 'editor'; Desc = '终端编辑器（LazyVim 基座）' }
    # Yazi 及其预览依赖
    @{ Name = 'Yazi';        Id = 'sxyazi.yazi';                    Component = 'files'; Desc = '终端文件管理器（y）' }
    @{ Name = 'ffmpeg';      Id = 'Gyan.FFmpeg';                    Component = 'files'; Desc = 'yazi 视频缩略图'; Optional = $true }
    @{ Name = 'jq';          Id = 'jqlang.jq';                      Component = 'files'; Desc = 'yazi JSON 预览'; Optional = $true }
    @{ Name = 'poppler';     Id = 'oschwartz10612.Poppler';         Component = 'files'; Desc = 'yazi PDF 预览'; Optional = $true }
    @{ Name = 'ImageMagick'; Id = 'ImageMagick.ImageMagick';        Component = 'files'; Desc = 'yazi 字体/HEIC 预览'; Optional = $true }
    # lazygit（终端 git UI）与 LazyVim 的 treesitter 编译器
    @{ Name = 'lazygit';     Id = 'JesseDuffield.lazygit';          Component = 'gitui'; Desc = '终端 Git UI（lg）' }
    @{ Name = 'WinLibs gcc'; Id = 'BrechtSanders.WinLibs.POSIX.UCRT'; Component = 'editor'; Desc = 'treesitter 编译器（Neovim 需要）' }
)
# 防呆：缺 Component 标注（或值非法）的条目会被组件过滤静默跳过、永不安装，
# 提前显式告警，避免"加了工具却怎么都装不上"的排查成本
foreach ($t in $wingetTools) {
    if (-not $t.Component -or $t.Component -notin $allComponents) {
        Write-Warning "工具 '$($t.Name)' 的 Component 标注缺失或非法（$($t.Component)），它不会被安装——请修正清单。"
    }
}

# 组件 → 随组件安装的 PSGallery 模块（唯一事实来源：向导展示与实际安装共用，
# 改这里即可，勿在向导/安装函数里另写一份）
$componentModules = [ordered]@{
    core       = @('Terminal-Icons')
    completion = @('PSCompletions', 'PSFzf')
}

# ================= 交互式安装向导 =================
# 无显式组件参数时的选择界面：简介 → 组件勾选 → 工具预览/剔除 → 确认。
# 返回 $null 表示用户退出：不做任何改动直接结束。
if ($pendingWizard) {
    . (Join-Path $repoDir 'Scripts\Invoke-SetupWizard.ps1')
    $wizardChoice = Invoke-SetupWizard -Tools $wingetTools -DefaultComponents $standardComponents -ComponentModules $componentModules
    if ($null -eq $wizardChoice) {
        Write-Host '已取消安装，未做任何改动。' -ForegroundColor DarkYellow
        return
    }
    $effectiveComponents = @($wizardChoice.Components)
    $ExcludeTools        = @($wizardChoice.ExcludeTools)
}
# -ExcludeTools 直接传参时同样归一化（逗号分隔兼容 pwsh -File 的单 token 形态）
$ExcludeTools = if ($ExcludeTools) { @(__NormalizeComponents $ExcludeTools) } else { @() }
Write-Host "安装组件: $($effectiveComponents -join ', ')" -ForegroundColor Cyan
if ($ExcludeTools) {
    Write-Host "剔除工具: $($ExcludeTools -join ', ')" -ForegroundColor Cyan
}

# 链接注册表（机器本地状态，不入库）：登记 setup 创建/发现的受管目标，
# Repair-ConfigLinks.ps1 的修复依据。读写函数与幂等判定（Get-ManagedLinkState）、
# 旧 txt 迁移转换单源在 Scripts/LinkRegistry.ps1（原子写，防并发损坏）。
. (Join-Path $repoDir 'Scripts\LinkRegistry.ps1')
$__RegistryPath = Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json'

# winget 探测/安装单源在 Scripts/ToolInstall.ps1（bootstrap 是仓库克隆前执行的
# 单文件引导脚本，自包含不复用本片段）
. (Join-Path $repoDir 'Scripts\ToolInstall.ps1')

function Install-DepTools {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning '未找到 winget（需要 Windows 10 1809+ 的 App Installer），跳过工具安装。'
        return
    }

    foreach ($tool in @($wingetTools | Where-Object {
                $effectiveComponents -contains $_.Component -and $_.Name -notin $ExcludeTools
            })) {
        # 幂等：已安装则跳过（探测逻辑单源在 Scripts/ToolInstall.ps1）
        if (Test-ManagedToolInstalled -Name $tool.Name -Id $tool.Id) {
            Write-Host "已安装: $($tool.Name)" -ForegroundColor DarkGray
            continue
        }
        $null = Install-ManagedTool -Name $tool.Name -Id $tool.Id -Desc $tool.Desc
    }
}

# LazyVim 配置入库：仓库 nvim/ 不存在时引入官方 starter（去掉其 .git，
# 作为普通目录随本仓库提交；插件本体在每设备 $LOCALAPPDATA\nvim-data 自动安装）
function Initialize-LazyVim {
    $nvimDir = Join-Path $repoDir 'nvim'
    if (Test-Path $nvimDir) {
        Write-Host '已存在: nvim/（LazyVim 配置）' -ForegroundColor DarkGray
        return
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning '未找到 git，跳过 LazyVim starter 引入。'
        return
    }
    Write-Host '正在引入 LazyVim starter 到 nvim/ ...' -ForegroundColor Cyan
    git clone --depth 1 https://github.com/LazyVim/starter $nvimDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'LazyVim starter 克隆失败（网络问题？）。可稍后手动: git clone https://github.com/LazyVim/starter nvim'
        return
    }
    Remove-Item -Path (Join-Path $nvimDir '.git') -Recurse -Force
    # starter 默认忽略 lazy-lock.json；多设备插件版本一致必须跟踪它
    $gi = Join-Path $nvimDir '.gitignore'
    if (Test-Path $gi) {
        (Get-Content $gi) | Where-Object { $_ -notmatch 'lazy-lock' } | Set-Content $gi
    }
    Write-Host '已引入: nvim/（LazyVim starter）' -ForegroundColor Green
}

# yazi 主题 flavor（theme.toml 引用的 solarized；每设备安装，不入库）
function Install-YaziFlavor {
    if (-not (Test-Path (Join-Path $repoDir 'yazi\theme.toml'))) { return }
    # winget 刚装完 yazi 时当前进程 PATH 里还没有 ya，从注册表重建
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH','Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH','User')
    if (-not (Get-Command ya -ErrorAction SilentlyContinue)) {
        Write-Warning '未找到 ya（yazi CLI），跳过 Solarized flavor 安装，可稍后手动: ya pkg add peterfication/solarized'
        return
    }
    $flavorDir = Join-Path $env:APPDATA 'yazi\config\flavors'
    if ((Test-Path $flavorDir) -and (Get-ChildItem $flavorDir -Filter '*solarized*' -ErrorAction SilentlyContinue)) {
        Write-Host '已安装: yazi flavor (solarized)' -ForegroundColor DarkGray
        return
    }
    Write-Host '正在安装 yazi Solarized flavor ...' -ForegroundColor Cyan
    $output = ya pkg add peterfication/solarized 2>&1 | Out-String
    Write-Host $output.TrimEnd() -ForegroundColor DarkGray
}

function Install-PwshModules {
    # 5.1 默认 TLS 协议连不上 PSGallery，强制 TLS 1.2（PS7 默认已含，无副作用）
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    # NuGet provider 缺失时自动装（否则 Install-Module 会交互式询问）
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }

    # 从唯一事实来源（$componentModules）按所选组件推导，与向导展示同源
    $wanted = @(
        $componentModules.Keys | Where-Object { $effectiveComponents -contains $_ } |
            ForEach-Object { $componentModules[$_] }
    )
    $need = @($wanted | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if (-not $need) {
        Write-Host "已安装: $($wanted -join ', ')" -ForegroundColor DarkGray
        return
    }
    try {
        Install-Module -Name $need -Scope CurrentUser -Force -ErrorAction Stop
        Write-Host "已安装模块: $($need -join ', ')" -ForegroundColor Green
    }
    catch {
        Write-Warning "模块安装失败: $_"
        Write-Host '可稍后手动执行: Install-Module PSCompletions, PSFzf -Scope CurrentUser'
    }
}

# ================= 文件链接 =================
# Core 条目的目标在 $PROFILE 目录下，仓库目录即 $PROFILE 目录时跳过
# （源与目标同路径，无法自链）；外部条目任何情况下都链接。
if ($repoDir -ieq $profileDir) {
    Write-Host '检测到仓库目录就是 $PROFILE 所在目录（本机直用仓库），跳过 $PROFILE 相关文件链接。' -ForegroundColor DarkYellow
    $linkItems = @($linkItems | Where-Object { -not $_.Core })
}

# 链接必须在 Initialize-LazyVim 之后建立（nvim/ 目录要先存在）；仅 editor 组件引入
if ($effectiveComponents -contains 'editor') { Initialize-LazyVim }

# 部署循环单源在 Scripts/Deploy-ConfigLinks.ps1（符号链接探测、备份接管、
# Junction/HardLink/Copy 回退链与注册表登记），供 Pester 直接测试
. (Join-Path $repoDir 'Scripts\Deploy-ConfigLinks.ps1')
$deploy = Invoke-ConfigLinkDeployment -Items $linkItems -RepoDir $repoDir `
    -RegistryPath $__RegistryPath -BackupRoot $profileDir
$backupCreated = $deploy.BackupCreated
$copyDeployed  = $deploy.CopyDeployed
$backupDir     = $deploy.BackupDir

# 修复历史断链（幂等；对已完好的链接无操作）
& (Join-Path $repoDir 'Scripts\Repair-ConfigLinks.ps1')

# ================= 工具 / 模块安装 =================
if ($SkipTools) {
    Write-Host '已跳过工具与模块安装（-SkipTools）。' -ForegroundColor DarkGray
}
else {
    Install-DepTools
    if ($effectiveComponents -contains 'files') { Install-YaziFlavor }
    Install-PwshModules
    Write-Host "`n依赖安装完成。请重新打开终端让 winget 注入的 PATH 生效。" -ForegroundColor Cyan
}

# ================= 5.1 执行策略 =================
# Windows PowerShell 5.1 默认执行策略 Restricted，新会话会拒绝加载 profile。
# 仅当「新会话的实际生效策略会是 Restricted」时放开为 CurrentUser RemoteSigned
# （用户已显式设置过策略则不动；PS7 不经过这里，其策略由 powershell.config.json 管理）。
if ($PSVersionTable.PSVersion.Major -lt 7) {
    $policyDefault = Get-ExecutionPolicy -Scope CurrentUser
    if ($policyDefault -eq 'Undefined') { $policyDefault = Get-ExecutionPolicy -Scope LocalMachine }
    if ($policyDefault -eq 'Restricted') {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Write-Host '已将当前用户执行策略设为 RemoteSigned（Windows PowerShell 5.1 加载 profile 需要）。' -ForegroundColor DarkYellow
    }
}

Write-Host "`n安装完成。请重新打开 PowerShell 或执行 `. `$PROFILE` 加载配置。" -ForegroundColor Cyan
if ($copyDeployed) {
    Write-Warning '部分条目以复制模式部署（无符号链接/硬链接权限）：不实时同步，但 psync / 重跑 setup 会自动镜像刷新。'
}
if ($backupCreated) {
    Write-Host "原配置已备份到: $backupDir" -ForegroundColor Cyan
}
