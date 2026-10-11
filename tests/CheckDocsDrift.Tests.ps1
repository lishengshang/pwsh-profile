# Pester 5/6 兼容测试：文档防漂移校验（Scripts/Check-DocsDrift.ps1）
# 在临时目录构造迷你仓库树（profile/aliases.ps1 + setup.ps1 + docs + README），
# 逐项注入漂移场景断言失败信息，全覆盖场景断言通过。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/CheckDocsDrift.Tests.ps1"

Describe 'Check-DocsDrift 文档防漂移校验' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        $script = Join-Path $repoRoot 'Scripts\Check-DocsDrift.ps1'
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-drift-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        # 全覆盖迷你仓库：usage 收录 alpha（公开函数）与 al（别名）；
        # beta 由别名 al 代表、__hidden 私有——两者都不要求收录
        function New-TestRepo {
            $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path (Join-Path $case 'profile') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $case 'docs') -Force | Out-Null
            Set-Content -Path (Join-Path $case 'profile\aliases.ps1') -Encoding utf8BOM -Value @'
function alpha { }
function __hidden { }
function beta { }
Set-Alias -Name al -Value beta -Force
'@
            Set-Content -Path (Join-Path $case 'setup.ps1') -Encoding utf8BOM -Value @'
$wingetTools = @(
    @{ Name = 'ToolA'; Id = 'x.ToolA'; Component = 'core' }
    @{ Name = 'ToolB'; Id = 'y.ToolB'; Component = 'extra' }
)
'@
            Set-Content -Path (Join-Path $case 'docs\usage.md') -Encoding utf8BOM -Value @'
# 使用速查

| 命令 | 说明 |
|---|---|
| `alpha` | 测试函数 |
| `al` | 测试别名 |
'@
            Set-Content -Path (Join-Path $case 'docs\reference.md') -Encoding utf8BOM -Value @'
# 配置参考

| 组件 | 内容 |
|---|---|
| `core` | 基础 |
| `extra` | 扩展 |

| 工具 | 组件 |
|---|---|
| ToolA（`x.ToolA`） | core |
| ToolB（`y.ToolB`） | extra |
'@
            Set-Content -Path (Join-Path $case 'README.md') -Encoding utf8BOM -Value @'
# pwsh-profile

## 快速上手

| 命令 | 说明 |
|---|---|
| `alpha` | x |
| `git push` | y |
'@
            return $case
        }

        # 运行校验并捕获终止性错误（throw 以 ErrorRecord 传播到调用方）
        function Invoke-DriftCheck {
            param([string]$Case)
            $err = $null
            try { & $script -RepoRoot $Case } catch { $err = $_ }
            return $err
        }
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '全覆盖时通过（别名代表函数、私有函数不要求收录）' {
        { & $script -RepoRoot (New-TestRepo) } | Should -Not -Throw
    }

    It '公开函数未收录 usage.md 时失败并指名' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'docs\usage.md') -Encoding utf8BOM -Value @'
# 使用速查

| `al` | 测试别名 |
'@
        $err = Invoke-DriftCheck $case
        $err | Should -Not -BeNullOrEmpty
        $err.Exception.Message | Should -Match 'usage\.md 缺少函数: alpha'
    }

    It '别名未收录 usage.md 时失败并指名' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'docs\usage.md') -Encoding utf8BOM -Value @'
# 使用速查

| `alpha` | 测试函数 |
'@
        $err = Invoke-DriftCheck $case
        $err.Exception.Message | Should -Match 'usage\.md 缺少别名: al'
    }

    It 'winget 工具或组件缺失 reference.md 时失败并指名' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'docs\reference.md') -Encoding utf8BOM -Value @'
# 配置参考

| 组件 | 内容 |
|---|---|
| `core` | 基础 |

| 工具 | 组件 |
|---|---|
| ToolA（`x.ToolA`） | core |
'@
        $err = Invoke-DriftCheck $case
        $err.Exception.Message | Should -Match 'reference\.md 缺少工具: ToolB'
        $err.Exception.Message | Should -Match '缺少组件: extra'
    }

    It 'README 快速上手引用未收录命令时失败，非 profile 命令跳过' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'README.md') -Encoding utf8BOM -Value @'
# pwsh-profile

## 快速上手

| 命令 | 说明 |
|---|---|
| `beta` | 未收录的实现名 |
| `git push` | 非 profile 命令 |
'@
        $err = Invoke-DriftCheck $case
        # beta 是被别名代表的函数，usage 检查放行，但 README 引用必须用收录名
        $err.Exception.Message | Should -Match 'README 快速上手引用了 usage\.md 未收录的命令: beta'
        $err.Exception.Message | Should -Not -Match 'git'
    }

    It 'setup.ps1 缺少 wingetTools 清单时显式报错不静默' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'setup.ps1') -Encoding utf8BOM -Value 'Write-Host ok'
        $err = Invoke-DriftCheck $case
        $err.Exception.Message | Should -Match '未找到 .*wingetTools 清单定义'
    }

    It 'aliases.ps1 语法损坏时报错不静默' {
        $case = New-TestRepo
        Set-Content -Path (Join-Path $case 'profile\aliases.ps1') -Encoding utf8BOM -Value 'function { broken !!!'
        $err = Invoke-DriftCheck $case
        $err.Exception.Message | Should -Match '解析失败'
    }
}
