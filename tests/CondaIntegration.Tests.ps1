# Pester 5/6 兼容测试：用子进程隔离 Conda 模块、提示符与环境变量。

Describe 'Conda 按需初始化' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $envScript = Join-Path (Get-TestRepoRoot) 'profile\env.ps1'
        $probePath = Join-Path $TestDrive 'probe.ps1'

        Set-Content -LiteralPath (Join-Path $TestDrive 'conda-stub.ps1') -Encoding UTF8 -Value @'
$env:TEST_CONDA_CALLS = 1 + [int]$env:TEST_CONDA_CALLS
if ($env:TEST_CONDA_FAIL) { 'throw "Failed hook was evaluated"'; exit 12 }
if ($args.Count -ne 2 -or $args[0] -ne 'shell.powershell' -or $args[1] -ne 'hook') { exit 13 }
if ((Test-Path Env:CONDA_AUTO_ACTIVATE) -or $env:CONDA_AUTO_ACTIVATE_BASE -ne 'false' -or
    $env:CONDA_CHANGEPS1 -ne 'false') { exit 14 }
'Import-Module (Join-Path $env:TEST_CONDA_ROOT "Conda.psm1")'
exit 0
'@

        Set-Content -LiteralPath (Join-Path $TestDrive 'Conda.psm1') -Encoding UTF8 -Value @'
function Invoke-Conda { $args -join '|' }
Set-Alias -Name conda -Value Invoke-Conda
Export-ModuleMember -Function Invoke-Conda -Alias conda
'@

        Set-Content -LiteralPath $probePath -Encoding UTF8 -Value @'
param($EnvScript, $Scenario)
$ErrorActionPreference = 'Stop'
$env:TEST_CONDA_ROOT = $PSScriptRoot
$env:TEST_CONDA_CALLS = '0'
$env:TEST_CONDA_FAIL = $null
$env:PROFILE_NO_CONDA = $null
$env:CONDA_AUTO_ACTIVATE = 'true'
$env:CONDA_AUTO_ACTIVATE_BASE = $null
$env:CONDA_CHANGEPS1 = 'true'
$global:__Tools = @{}
if ($Scenario -ne 'missing') {
    $global:__Tools['conda'] = [pscustomobject]@{ Source = Join-Path $PSScriptRoot 'conda-stub.ps1' }
}
if ($Scenario -eq 'disabled') { $env:PROFILE_NO_CONDA = '1' }

. (Join-Path (Split-Path $EnvScript) 'init-cache.ps1')
$env:TEMP = $PSScriptRoot
$promptBefore = (Get-Command prompt).Definition
. $EnvScript
if ($env:TEST_CONDA_CALLS -ne '0' -or (Get-Module Conda)) { throw 'Conda ran at profile startup' }
if ($Scenario -in 'disabled','missing') {
    if (Get-Command conda -CommandType Function -ErrorAction Ignore) { throw 'Conda wrapper was defined' }
    return
}

if ($Scenario -eq 'retry') {
    $env:TEST_CONDA_FAIL = '1'
    $failure = try { conda --version } catch { $_ }
    if ($failure -isnot [System.Management.Automation.ErrorRecord] -or
        $failure.Exception.Message -notmatch '12') { throw 'Failed hook was not reported' }
    if ($env:CONDA_AUTO_ACTIVATE -ne 'true' -or $env:CONDA_CHANGEPS1 -ne 'true' -or
        (Test-Path Env:CONDA_AUTO_ACTIVATE_BASE)) { throw 'Settings were not restored after failure' }
    $env:TEST_CONDA_FAIL = $null
}

if ((conda run -n 'Env With Spaces' python) -ne 'run|-n|Env With Spaces|python') { throw 'First call lost arguments' }
if ((Get-Command conda).CommandType -ne 'Alias') { throw 'Conda alias was not loaded' }
if ((conda --version) -ne '--version') { throw 'Conda alias did not dispatch' }
$expectedCalls = if ($Scenario -eq 'retry') { 2 } else { 1 }
if ([int]$env:TEST_CONDA_CALLS -ne $expectedCalls) { throw 'Unexpected number of hook calls' }
if ($promptBefore -ne (Get-Command prompt).Definition) { throw 'Conda changed the prompt' }
if ($env:CONDA_AUTO_ACTIVATE -ne 'true' -or $env:CONDA_CHANGEPS1 -ne 'true' -or
    (Test-Path Env:CONDA_AUTO_ACTIVATE_BASE)) { throw 'Settings were not restored after success' }
if (Test-Path (Join-Path $env:TEMP 'conda-init-cache.ps1')) { throw 'Conda wrote a cross-session cache' }
'@

        function Test-CondaIntegration {
            param([string]$Scenario)
            & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -File $probePath $envScript $Scenario
            $LASTEXITCODE | Should -Be 0
        }
    }

    It '首次调用加载 hook 并将参数交给 Conda，后续调用直接走模块' {
        Test-CondaIntegration -Scenario ready
    }

    It '首次初始化失败后可重试' {
        Test-CondaIntegration -Scenario retry
    }

    It 'PROFILE_NO_CONDA 跳过初始化' {
        Test-CondaIntegration -Scenario disabled
    }

    It '未检测到 Conda 时不创建占位命令' {
        Test-CondaIntegration -Scenario missing
    }
}
