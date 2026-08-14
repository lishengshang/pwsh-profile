#Requires -Version 7
<#
.SYNOPSIS
    安装 PowerShell profile 到当前用户的 PowerShell 配置目录。
.DESCRIPTION
    1. 通过符号链接把仓库中的 profile 文件映射到 $PROFILE 所在目录
       （符号链接需要管理员权限或开发者模式，否则回退到复制模式）。
    2. 默认用 winget 安装全部依赖工具、Install-Module 安装 PSCompletions/PSFzf，
       加 -SkipTools 可跳过（工具均为可选依赖，缺失时 profile 自动降级）。
    仓库目录本身即 $PROFILE 目录时（本机直用仓库），自动跳过文件链接，只装工具。
.PARAMETER SkipTools
    跳过 winget 工具与 PowerShell 模块的自动安装。
#>
param(
    [switch]$SkipTools
)

$ErrorActionPreference = 'Stop'

$repoDir = [System.IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$profileDir = [System.IO.Path]::GetFullPath((Split-Path $PROFILE)).TrimEnd('\')
$backupDir = Join-Path $profileDir "backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# 需要映射的条目：源文件/目录（在仓库内） -> 目标路径（在 $profileDir 下）
$items = @(
    @{ Source = 'Microsoft.PowerShell_profile.ps1'; Target = $PROFILE }
    @{ Source = 'profile'; Target = Join-Path $profileDir 'profile' }
    @{ Source = 'Scripts'; Target = Join-Path $profileDir 'Scripts' }
    @{ Source = 'powershell.config.json'; Target = Join-Path $profileDir 'powershell.config.json' }
)

# winget 工具清单（与 README「依赖工具」表保持一致）
$wingetTools = @(
    @{ Name = 'Starship'; Id = 'Starship.Starship' }
    @{ Name = 'eza';      Id = 'eza-community.eza' }
    @{ Name = 'zoxide';   Id = 'ajeetdsouza.zoxide' }
    @{ Name = 'ripgrep';  Id = 'BurntSushi.ripgrep.MSVC' }
    @{ Name = 'fd';       Id = 'sharkdp.fd' }
    @{ Name = 'bat';      Id = 'sharkdp.bat' }
    @{ Name = '7-Zip';    Id = '7zip.7zip' }
    @{ Name = 'fzf';      Id = 'junegunn.fzf' }
    @{ Name = 'fnm';      Id = 'Schniz.fnm' }
    @{ Name = 'Neovim';   Id = 'neovim.neovim' }
)

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

    foreach ($tool in $wingetTools) {
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

function Install-PwshModules {
    # NuGet provider 缺失时自动装（否则 Install-Module 会交互式询问）
    if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    }

    $need = 'PSCompletions', 'PSFzf' | Where-Object { -not (Get-Module -ListAvailable -Name $_) }
    if (-not $need) {
        Write-Host '已安装: PSCompletions / PSFzf' -ForegroundColor DarkGray
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

# ================= 文件链接（仓库目录即配置目录时跳过） =================
if ($repoDir -ieq $profileDir) {
    Write-Host '检测到仓库目录就是 $PROFILE 所在目录（本机直用仓库），跳过文件链接。' -ForegroundColor DarkYellow
}
else {
    $useSymlink = Test-SymlinkAvailable
    if (-not $useSymlink) {
        Write-Warning '当前环境不支持创建符号链接（需管理员权限或开启开发者模式），将使用复制模式。'
    }

    # 备份已存在的目标文件/目录
    $needBackup = $items | Where-Object { Test-Path $_.Target }
    if ($needBackup) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        foreach ($item in $needBackup) {
            $name = Split-Path $item.Target -Leaf
            Move-Item -Path $item.Target -Destination (Join-Path $backupDir $name) -Force
            Write-Host "已备份: $($item.Target) -> $backupDir\$name" -ForegroundColor DarkYellow
        }
    }

    foreach ($item in $items) {
        $src = Join-Path $repoDir $item.Source
        if (-not (Test-Path $src)) {
            Write-Host "跳过（不存在）: $src" -ForegroundColor DarkGray
            continue
        }

        if (Test-Path $item.Target) {
            Remove-Item -Path $item.Target -Recurse -Force
        }

        $parent = Split-Path $item.Target
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }

        if ($useSymlink) {
            $null = New-Item -ItemType SymbolicLink -Path $item.Target -Target $src -Force
            Write-Host "已链接: $($item.Source) -> $($item.Target)" -ForegroundColor Green
        }
        else {
            if ((Get-Item $src).PSIsContainer) {
                Copy-Item -Path $src -Destination $item.Target -Recurse -Force
            }
            else {
                Copy-Item -Path $src -Destination $item.Target -Force
            }
            Write-Host "已复制: $($item.Source) -> $($item.Target)" -ForegroundColor Green
        }
    }
}

# ================= 工具 / 模块安装 =================
if ($SkipTools) {
    Write-Host '已跳过工具与模块安装（-SkipTools）。' -ForegroundColor DarkGray
}
else {
    Install-DepTools
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
Write-Host ''
for ($i = 0; $i -lt 7; $i++) {
    Write-Host "`e[$($bannerColors[$i])m$($bannerRows[$i])`e[0m"
}

Write-Host "安装完成。请重新打开 PowerShell 或执行 `. `$PROFILE` 加载配置。" -ForegroundColor Cyan
if (($repoDir -ine $profileDir) -and $needBackup) {
    Write-Host "原配置已备份到: $backupDir" -ForegroundColor Cyan
}
