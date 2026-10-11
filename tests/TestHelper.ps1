# Pester 测试共享助手（被各 .Tests.ps1 的 BeforeAll dot-source）。
# 只定义函数不产生状态：Pester 6 每个块运行在独立 script scope，
# $script: 变量不跨块共享，跨块数据一律走普通变量（动态作用域，5/6 均成立）。

# 仓库根目录（tests/ 的上级）
function Get-TestRepoRoot {
    Split-Path $PSScriptRoot
}

# 本次 Describe 专用的临时根目录（调用方在 AfterAll 里 Remove-Item 清理）
function New-TestTempRoot {
    param([Parameter(Mandatory)][string]$Prefix)
    $dir = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

# 取链接的第一目标路径（Windows PowerShell 5.1 的 .Target 是 String[]）
function Get-LinkTargetPath {
    param([string]$Path)
    $prop = @((Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Target) |
        Select-Object -First 1
    if (-not $prop) { return $null }
    return ([System.IO.Path]::GetFullPath([string]$prop)).TrimEnd('\')
}
