#Requires -Version 7
<#
.SYNOPSIS
    安装 PowerShell profile 到当前用户的 PowerShell 配置目录。
.DESCRIPTION
    1. 通过符号链接把仓库中的 profile 文件映射到 $PROFILE 所在目录
       （符号链接需要管理员权限或开发者模式，否则回退到复制模式）。
    2. 默认按 Standard 组件用 winget 安装依赖工具、Install-Module 安装模块；
       加 -SkipTools 可跳过下载（工具均为可选依赖，缺失时 profile 自动降级）。
    仓库目录本身即 $PROFILE 目录时（本机直用仓库），自动跳过文件链接，只装工具。
    组件选择决定"下载哪些工具/模块、链接哪些外部配置"：profile 本体（Core）始终
    部署，运行时所有外部工具引用都被 $global:__Tools.ContainsKey 守卫，未安装的
    工具自动优雅降级（对应别名/函数不创建）。
.PARAMETER SkipTools
    跳过 winget 工具与 PowerShell 模块的自动安装（仍按所选组件链接外部配置）。
.PARAMETER Minimal
    仅安装 core 组件（profile 本体 + 基础命令行工具）。与 -Full 互斥。
.PARAMETER Full
    安装全部组件。与 -Minimal 互斥。
.PARAMETER Components
    显式指定要安装的组件（覆盖 -Minimal/-Full 预设）；可选值见下方"组件"注释。
    多个组件用逗号分隔（-Components core,gitui）。
.PARAMETER SkipComponents
    从解析出的组件集合中剔除指定组件（同样逗号分隔）。
#>
# CmdletBinding(PositionalBinding=$false)：禁止位置绑定。否则 "-Components core gitui"
# 的 gitui 会被位置绑定到 SkipComponents——语义反转为"剔除 gitui"且无任何告警，必须报错。
# 注意：该特性必须放在 param() 上方才生效（放 param() 内部时 PositionalBinding 不起作用）。
[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$SkipTools,
    [switch]$Minimal,
    [switch]$Full,
    [string[]]$Components,
    [string[]]$SkipComponents
)

$ErrorActionPreference = 'Stop'

# ================= 组件选择（多级别下载/安装粒度）=================
# 组件决定"下载哪些工具/模块、链接哪些外部配置"。profile 本体（Core 条目）始终部署；
# 运行时所有外部工具引用都被 $global:__Tools.ContainsKey 守卫，未安装的工具自动优雅
# 降级（对应别名/函数不创建），故安装阶段不装即等于运行时缺失，无需改 profile 代码。
#   -Components <组件>      显式指定要安装的组件（覆盖 -Minimal/-Full 预设）
#   -SkipComponents <组件>  从解析结果中剔除
#   -Minimal = core；-Full = 全部；（默认/无开关 = Standard: core+completion+gitui）
$allComponents      = 'core', 'completion', 'editor', 'files', 'gitui'
$standardComponents = 'core', 'completion', 'gitui'

# 容忍逗号分隔的单 token：pwsh -File 下数组参数不会贪心收集后续参数，
# "-Components core,gitui" 会整体作为单个字符串传入；交互式会话里两种写法
# 都已是数组，按逗号再拆一次是无害的幂等操作。
function __NormalizeComponents ([string[]]$List) {
    @($List | ForEach-Object { $_ -split '\s*,\s*' } | Where-Object { $_ })
}

if ($Minimal -and $Full) {
    throw '-Minimal 与 -Full 互斥，请只选其一（或改用 -Components 显式指定）。'
}
$Components     = __NormalizeComponents $Components
$SkipComponents = __NormalizeComponents $SkipComponents
if ($Components) {
    $effectiveComponents = @($Components | Where-Object { $_ -in $allComponents })
    $unknown = @($Components | Where-Object { $_ -notin $allComponents })
    if ($unknown) {
        Write-Warning "未知组件将被忽略: $($unknown -join ', ')（合法值: $($allComponents -join ', ')）"
    }
    # 显式指定却全部无效，几乎必然是调用方式/拼写错误——静默空集会让用户
    # 误以为装好了，必须终止
    if (-not $effectiveComponents) {
        throw "-Components 未包含任何合法组件（收到: $($Components -join ', ')；合法值: $($allComponents -join ', ')）。"
    }
} elseif ($Minimal) {
    $effectiveComponents = @('core')
} elseif ($Full) {
    $effectiveComponents = @($allComponents)
} else {
    $effectiveComponents = @($standardComponents)
}
if ($SkipComponents) {
    $unknownSkip = @($SkipComponents | Where-Object { $_ -notin $allComponents })
    if ($unknownSkip) {
        Write-Warning "SkipComponents 中的未知组件将被忽略: $($unknownSkip -join ', ')（合法值: $($allComponents -join ', ')）"
    }
    $effectiveComponents = @($effectiveComponents | Where-Object { $_ -notin $SkipComponents })
    if (-not $effectiveComponents) {
        throw "-SkipComponents（$($SkipComponents -join ', ')）剔除了全部组件，没有可安装的内容。"
    }
}
$effectiveComponents = @($effectiveComponents | Select-Object -Unique)
Write-Host "安装组件: $($effectiveComponents -join ', ')" -ForegroundColor Cyan

$repoDir = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$profileDir = [System.IO.Path]::GetFullPath((Split-Path $PROFILE)).TrimEnd('\')
$backupDir = Join-Path $profileDir "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

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

# winget 工具清单（与 README「依赖工具」表保持一致）
# 每项标注 Component：决定它属于哪个安装组件（多级别下载粒度的依据）。
#   core      基础 shell 与开发工具
#   completion 命令补全（PSFzf 依赖 fzf）
#   editor     Neovim / LazyVim（+ treesitter 编译器）
#   files      yazi 及其预览依赖
#   gitui      lazygit 终端 git UI
$wingetTools = @(
    @{ Name = 'Starship'; Id = 'Starship.Starship';                    Component = 'core' }
    @{ Name = 'eza';      Id = 'eza-community.eza';                    Component = 'core' }
    @{ Name = 'zoxide';   Id = 'ajeetdsouza.zoxide';                   Component = 'core' }
    @{ Name = 'ripgrep';  Id = 'BurntSushi.ripgrep.MSVC';              Component = 'core' }
    @{ Name = 'fd';       Id = 'sharkdp.fd';                           Component = 'core' }
    @{ Name = 'bat';      Id = 'sharkdp.bat';                          Component = 'core' }
    @{ Name = '7-Zip';    Id = '7zip.7zip';                            Component = 'core' }
    @{ Name = 'fnm';      Id = 'Schniz.fnm';                           Component = 'core' }
    @{ Name = 'fzf';      Id = 'junegunn.fzf';                         Component = 'completion' }
    @{ Name = 'Neovim';   Id = 'Neovim.Neovim';                        Component = 'editor' }
    # Yazi 及其预览依赖
    @{ Name = 'Yazi';         Id = 'sxyazi.yazi';                      Component = 'files' }
    @{ Name = 'ffmpeg';       Id = 'Gyan.FFmpeg';                      Component = 'files' }
    @{ Name = 'jq';           Id = 'jqlang.jq';                        Component = 'files' }
    @{ Name = 'poppler';      Id = 'oschwartz10612.Poppler';           Component = 'files' }
    @{ Name = 'ImageMagick';  Id = 'ImageMagick.ImageMagick';          Component = 'files' }
    # lazygit（终端 git UI）与 LazyVim 的 treesitter 编译器
    @{ Name = 'lazygit';   Id = 'JesseDuffield.lazygit';              Component = 'gitui' }
    @{ Name = 'WinLibs gcc'; Id = 'BrechtSanders.WinLibs.POSIX.UCRT'; Component = 'editor' }
)
# 防呆：缺 Component 标注（或值非法）的条目会被组件过滤静默跳过、永不安装，
# 提前显式告警，避免"加了工具却怎么都装不上"的排查成本
foreach ($t in $wingetTools) {
    if (-not $t.Component -or $t.Component -notin $allComponents) {
        Write-Warning "工具 '$($t.Name)' 的 Component 标注缺失或非法（$($t.Component)），它不会被安装——请修正清单。"
    }
}

# 链接注册表（机器本地状态，不入库）：登记 setup 创建/发现的受管目标，
# Repair-ConfigLinks.ps1 的修复依据。读写函数单源在 Scripts/LinkRegistry.ps1
# （原子写，防并发损坏）。
. (Join-Path $repoDir 'Scripts\LinkRegistry.ps1')
$__RegistryPath = Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json'

# 判定目标是否已由本仓库管理（幂等跳过的依据）。返回 @{ IsManaged; LinkType }：
#   SymbolicLink/Junction -> Target 属性指向仓库源
#   HardLink              -> fsutil 同 inode 路径包含仓库源
#   Copy / CopyDirectory  -> 仅当注册表已登记为该类型且 Source 匹配
#                            （普通文件再比哈希；内容恰好相同的独立文件不算——
#                            Hash 相同 ≠ 受本项目管理，避免误跳过建链）
function Get-ManagedLinkState ([string]$src, [string]$target) {
    $tgt = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
    if (-not $tgt) { return @{ IsManaged = $false; LinkType = $null } }
    $srcFull = [System.IO.Path]::GetFullPath($src).TrimEnd('\')
    if ($tgt.LinkType -in 'SymbolicLink', 'Junction') {
        if ($tgt.Target -and ([System.IO.Path]::GetFullPath($tgt.Target).TrimEnd('\') -ieq $srcFull)) {
            return @{ IsManaged = $true; LinkType = $tgt.LinkType }
        }
        return @{ IsManaged = $false; LinkType = $null }
    }
    $entry = @(Get-LinkRegistryEntries $__RegistryPath) |
        Where-Object { $_.Target -ieq $target } | Select-Object -First 1
    if ($tgt.PSIsContainer) {
        # 目录仅认可登记过的 CopyDirectory（Junction/SymbolicLink 已在上面处理）
        if ($entry -and $entry.LinkType -eq 'CopyDirectory' -and
            (([System.IO.Path]::GetFullPath($entry.Source).TrimEnd('\')) -ieq $srcFull)) {
            return @{ IsManaged = $true; LinkType = 'CopyDirectory' }
        }
        return @{ IsManaged = $false; LinkType = $null }
    }
    # 文件：先查 HardLink 关系（fsutil 输出同 inode 全部路径，不带盘符）
    $srcNorm = ($srcFull -replace '^[A-Za-z]:', '').ToLowerInvariant()
    $links = (fsutil hardlink list $target 2>$null) |
        ForEach-Object { (($_ -replace '^[A-Za-z]:', '').TrimEnd('\')).ToLowerInvariant() }
    if ($links -contains $srcNorm) { return @{ IsManaged = $true; LinkType = 'HardLink' } }
    # 普通文件：注册表登记为 Copy 且 Source 匹配时，内容一致才算管理
    if ($entry -and $entry.LinkType -eq 'Copy' -and
        (([System.IO.Path]::GetFullPath($entry.Source).TrimEnd('\')) -ieq $srcFull)) {
        if ((Get-FileHash $src -ErrorAction SilentlyContinue).Hash -eq
            (Get-FileHash $target -ErrorAction SilentlyContinue).Hash) {
            return @{ IsManaged = $true; LinkType = 'Copy' }
        }
    }
    return @{ IsManaged = $false; LinkType = $null }
}

function Test-SymlinkAvailable {
    $tmp = [System.IO.Path]::GetTempFileName()
    $link = "$tmp-link"
    try {
        $null = New-Item -ItemType SymbolicLink -Path $link -Target $tmp -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
    finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
        Remove-Item $link -ErrorAction SilentlyContinue
    }
}

function Install-DepTools {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        Write-Warning '未找到 winget（需要 Windows 10 1809+ 的 App Installer），跳过工具安装。'
        return
    }

    foreach ($tool in @($wingetTools | Where-Object { $effectiveComponents -contains $_.Component })) {
        # 幂等：已安装则跳过（winget list 无匹配时输出为空）
        $installed = winget list --id $tool.Id --exact --accept-source-agreements 2>$null |
            Select-String -Pattern ([regex]::Escape($tool.Id)) -Quiet
        if ($installed) {
            Write-Host "已安装: $($tool.Name)" -ForegroundColor DarkGray
            continue
        }
        Write-Host "正在安装: $($tool.Name) ($($tool.Id)) ..." -ForegroundColor Cyan
        $output = winget install --id $tool.Id -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            # 打印详细输出，便于定位失败原因（如源/网络问题）
            # -band 0xFFFFFFFF 把负 exit code 转成无符号十六进制（[uint32] 不接受负数）
            $code = '0x{0:X8}' -f ($LASTEXITCODE -band 0xFFFFFFFF)
            Write-Warning "安装失败: $($tool.Name)（exit $code）"
            $output.Trim() -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
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
    # NuGet provider 缺失时自动装（否则 Install-Module 会交互式询问）
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }

    $need = @()
    if ($effectiveComponents -contains 'completion') { $need += 'PSCompletions', 'PSFzf' }
    if ($effectiveComponents -contains 'core')       { $need += 'Terminal-Icons' }
    $need = @($need | Where-Object { -not (Get-Module -ListAvailable -Name $_) })
    if (-not $need) {
        Write-Host '已安装: PSCompletions / PSFzf / Terminal-Icons' -ForegroundColor DarkGray
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

$useSymlink = Test-SymlinkAvailable
if (-not $useSymlink) {
    Write-Warning '当前环境不支持符号链接（需管理员权限或开发者模式），目录将回退 Junction、文件回退 HardLink，仍失败才复制。'
}

# 链接必须在 Initialize-LazyVim 之后建立（nvim/ 目录要先存在）；仅 editor 组件引入
if ($effectiveComponents -contains 'editor') { Initialize-LazyVim }

$backupCreated = $false
$copyDeployed = $false
foreach ($item in $linkItems) {
    $src = Join-Path $repoDir $item.Source
    if (-not (Test-Path $src)) {
        Write-Host "跳过（不存在）: $src" -ForegroundColor DarkGray
        continue
    }

    # 幂等：目标已是受管链接/副本时跳过，并补登记（注册表丢失/手工建的正确
    # 链接也能恢复 Repair 的修复能力）
    $state = Get-ManagedLinkState $src $item.Target
    if ($state.IsManaged) {
        Write-Host "已是正确链接，跳过: $($item.Target)" -ForegroundColor DarkGray
        Set-LinkRegistryEntry -Path $__RegistryPath -Target $item.Target -Source $src -LinkType $state.LinkType
        continue
    }

    # Get-Item -Force 能拿到断链对象（指向已不存在目标的符号链接/Junction，
    # Test-Path 对断链文件返回 False 但对象仍占用路径，不清理则 New-Item 失败）
    $existing = Get-Item -LiteralPath $item.Target -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($item.SkipIfExists) {
            Write-Host "已存在，跳过: $($item.Target)" -ForegroundColor DarkGray
            continue
        }
        $isBrokenLink = $existing.LinkType -and -not (Test-Path -LiteralPath $item.Target)
        if ($isBrokenLink) {
            # 断链对象不含用户可读数据，直接清理后重建
            Remove-Item -LiteralPath $item.Target -Force
            Write-Host "已清理失效链接: $($item.Target)" -ForegroundColor DarkGray
        }
        else {
            # 普通文件/目录，或指向别处的有效链接：均视为用户现有配置，先备份
            if (-not $backupCreated) {
                New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                $backupCreated = $true
            }
            $name = Split-Path $item.Target -Leaf
            Move-Item -LiteralPath $item.Target -Destination (Join-Path $backupDir $name) -Force
            Write-Host "已备份: $($item.Target) -> $backupDir\$name" -ForegroundColor DarkYellow
        }
    }

    $parent = Split-Path $item.Target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    if ($useSymlink) {
        $null = New-Item -ItemType SymbolicLink -Path $item.Target -Target $src -Force
        Write-Host "已链接: $($item.Source) -> $($item.Target)" -ForegroundColor Green
        Set-LinkRegistryEntry -Path $__RegistryPath -Target $item.Target -Source $src -LinkType 'SymbolicLink'
    }
    else {
        # 无符号链接权限时的回退：目录用 Junction、文件用 HardLink（均无需特权，
        # 且和符号链接一样「仓库即实体」，保证改仓库文件即刻生效、不产生两份副本）
        $isDir = (Get-Item $src).PSIsContainer
        $linked = $false
        if ($isDir) {
            try {
                $null = New-Item -ItemType Junction -Path $item.Target -Target $src -ErrorAction Stop
                $linked = $true
            } catch { }
        }
        else {
            try {
                $null = New-Item -ItemType HardLink -Path $item.Target -Target $src -ErrorAction Stop
                $linked = $true
            } catch { }
        }
        if ($linked) {
            $linkType = if ($isDir) { 'Junction' } else { 'HardLink' }
            Write-Host "已链接($($(if ($isDir) {'junction'} else {'hardlink'}))): $($item.Source) -> $($item.Target)" -ForegroundColor Green
            Set-LinkRegistryEntry -Path $__RegistryPath -Target $item.Target -Source $src -LinkType $linkType
            continue
        }
        # 最终回退：Copy 模式（不实时同步；文件由 Repair 按哈希刷新、
        # 目录由 Repair 用 robocopy 镜像同步，psync 拉取后自动对齐）
        if ((Get-Item $src).PSIsContainer) {
            Copy-Item -Path $src -Destination $item.Target -Recurse -Force
            Set-LinkRegistryEntry -Path $__RegistryPath -Target $item.Target -Source $src -LinkType 'CopyDirectory'
        }
        else {
            Copy-Item -Path $src -Destination $item.Target -Force
            Set-LinkRegistryEntry -Path $__RegistryPath -Target $item.Target -Source $src -LinkType 'Copy'
        }
        $copyDeployed = $true
        Write-Host "已复制: $($item.Source) -> $($item.Target)" -ForegroundColor Green
    }
}

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

# ================= 完成横幅（点阵大字，安装完成时显示） =================
$bannerFont = @{
    P = @('#####','#   #','#   #','#####','#    ','#    ','#    ')
    W = @('#   #','#   #','# # #','## ##','## ##','#   #','#   #')
    S = @('#####','#    ','#    ','#### ','    #','    #','#####')
    H = @('#   #','#   #','#   #','#####','#   #','#   #','#   #')
}
$bannerColors = @('38;2;38;139;210','38;2;42;161;152','38;2;133;153;0','38;2;181;137;0','38;2;203;75;22','38;2;220;50;47','38;2;108;113;196')
$bannerRows = @('','','','','','','')
foreach ($ch in 'PWSH'.ToCharArray()) {
    $glyph = $bannerFont[[string]$ch]
    if (-not $glyph) { continue }
    for ($i = 0; $i -lt 7; $i++) { $bannerRows[$i] += $glyph[$i] + '  ' }
}
# 横幅 ANSI 转义用 [char]27 而非 `e（后者是 PS7 专属转义）
$esc = [char]27
Write-Host ''
for ($i = 0; $i -lt 7; $i++) {
    Write-Host "$esc[$($bannerColors[$i])m$($bannerRows[$i])$esc[0m"
}

Write-Host "安装完成。请重新打开 PowerShell 或执行 `. `$PROFILE` 加载配置。" -ForegroundColor Cyan
if ($copyDeployed) {
    Write-Warning '部分条目以复制模式部署（无符号链接/硬链接权限）：不实时同步，但 psync / 重跑 setup 会自动镜像刷新。'
}
if ($backupCreated) {
    Write-Host "原配置已备份到: $backupDir" -ForegroundColor Cyan
}
