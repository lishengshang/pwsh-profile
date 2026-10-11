#Requires -Version 5.1
# ==============================================================
# winget 工具安装（setup.ps1 dot-source 的可测试单元）
# 探测：命令已在 PATH 即视为已装（覆盖手动安装等非 winget 渠道）；否则按
# winget 清单判定（覆盖刚装完未重开终端、per-user 目录不进 PATH 的场景）。
# 安装失败默认警告降级（setup 的可选依赖语义），不中断其余工具。
# 注：bootstrap.ps1 不复用本片段——它是仓库克隆前执行的单文件引导脚本，
# 必须自包含，winget 命令串的重复是刻意保留的。
# ==============================================================

function Test-ManagedToolInstalled {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Id
    )
    if (Get-Command $Name -ErrorAction SilentlyContinue) { return $true }
    # 2>$null：winget list 在源异常时往 stderr 输出进度/错误，只取 stdout 匹配
    return [bool](winget list --id $Id --exact --accept-source-agreements 2>$null |
        Select-String -Pattern ([regex]::Escape($Id)) -Quiet)
}

function Install-ManagedTool {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Id,
        [string]$Desc
    )
    if ($Desc) { Write-Host "正在安装: $Name — $Desc（$Id）..." -ForegroundColor Cyan }
    else       { Write-Host "正在安装: $Name（$Id）..." -ForegroundColor Cyan }
    $output = winget install --id $Id -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        # 打印详细输出，便于定位失败原因（如源/网络问题）
        # -band 0xFFFFFFFF 把负 exit code 转成无符号十六进制（[uint32] 不接受负数）
        $code = '0x{0:X8}' -f ($LASTEXITCODE -band 0xFFFFFFFF)
        Write-Warning "安装失败: $Name（exit $code）"
        $output.Trim() -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        return $false
    }
    # 刚装完的工具不会自动出现在当前进程 PATH，从注册表（Machine+User）重建，
    # 后续同进程探测（如 Install-YaziFlavor 的 ya）立即可见
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
        [Environment]::GetEnvironmentVariable('PATH', 'User')
    return $true
}
