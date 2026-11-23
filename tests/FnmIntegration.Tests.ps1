Describe 'fnm 会话和项目版本' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $profileEnv = Join-Path (Get-TestRepoRoot) 'profile\env.ps1'
        $enginePath = (Get-Process -Id $PID).Path

        Set-Content -LiteralPath (Join-Path $TestDrive 'node.cmd') -Encoding ASCII -Value '@echo %TEST_FNM_VERSION%'
        Set-Content -LiteralPath (Join-Path $TestDrive 'fnm-stub.ps1') -Encoding UTF8 -Value @'
if ($args[0] -eq '--log-level') {
    if ($args[1] -ne 'quiet' -or $args[2] -ne '--resolve-engines' -or $args[3] -ne 'true') { exit 5 }
    $args = @($args[4..($args.Count - 1)])
}
switch ($args[0]) {
    '--version' { 'fixture-fnm' }
    'env' {
        $env:TEST_FNM_INIT_COUNT = 1 + [int]$env:TEST_FNM_INIT_COUNT
        '$env:FNM_MULTISHELL_PATH = $env:TEST_FNM_ROOT'
        '$env:PATH = "fixture-hook-replaces-path"'
    }
    'use' {
        if (!$env:FNM_MULTISHELL_PATH) { exit 2 }
        $env:TEST_FNM_USE_COUNT = 1 + [int]$env:TEST_FNM_USE_COUNT
        $version = if ($args[1] -eq '--silent-if-unchanged') { (Get-Content .node-version -Raw).Trim() } else { $args[1] }
        if ($version -eq '25.0.0' -and !$env:TEST_FNM_INSTALLED) { exit 4 }
        $env:TEST_FNM_VERSION = $version
    }
    'install' { $env:TEST_FNM_INSTALLED = '1' }
    'current' { $env:TEST_FNM_VERSION }
    default { exit 3 }
}
exit 0
'@

        $probePath = Join-Path $TestDrive 'fnm-probe.ps1'
        Set-Content -LiteralPath $probePath -Encoding UTF8 -Value @'
param([string]$ProfileEnv, [switch]$PrefixOptions)
$ErrorActionPreference = 'Stop'
$env:PROFILE_NO_FNM = $null
$env:APPDATA = $PSScriptRoot
$env:FNM_DIR = $PSScriptRoot
$env:FNM_MULTISHELL_PATH = $null
$env:TEST_FNM_ROOT = $PSScriptRoot
$env:TEST_FNM_INIT_COUNT = '0'
$env:TEST_FNM_USE_COUNT = '0'
$env:TEST_FNM_INSTALLED = $null
$oldPath = $env:PATH
$global:__Tools = @{ fnm = @{ Source = Join-Path $PSScriptRoot 'fnm-stub.ps1' } }

$first = New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'first') -Force
$second = New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'second') -Force
foreach ($project in $first,$second) {
    Set-Content -LiteralPath (Join-Path $project.FullName '.node-version') -Value '22.0.0'
}
Set-Location -LiteralPath $first.FullName
. $ProfileEnv

if ((fnm --version) -ne 'fixture-fnm' -or $env:FNM_MULTISHELL_PATH) { throw 'Read-only fnm command should not initialize' }
if ($PrefixOptions) { fnm --log-level quiet --resolve-engines true use 24.0.0 } else { fnm use 24.0.0 }
if ($LASTEXITCODE -or (node --version) -ne '24.0.0') { throw 'First explicit use failed or was overwritten' }
if ($env:PATH -ne "$PSScriptRoot;$oldPath") { throw 'Initialization did not retain the original PATH' }

Set-Location -LiteralPath $second.FullName
if ((node --version) -ne '22.0.0' -or (fnm current) -ne '22.0.0') { throw 'Set-Location did not select the project version' }
if ($env:TEST_FNM_INIT_COUNT -ne '1' -or $env:TEST_FNM_USE_COUNT -ne '2') { throw 'Initialization or version selection ran twice' }

$third = New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'third') -Force
Set-Content -LiteralPath (Join-Path $third.FullName '.node-version') -Value '25.0.0'
Set-Location -LiteralPath $third.FullName
if ((node --version) -ne '22.0.0') { throw 'Attempt to use an uninstalled version changed current Node' }
fnm install 25.0.0
if ((node --version) -ne '25.0.0') { throw 'Newly installed project version was not selected' }
'@
    }

    It '<Name>' -ForEach @(
        @{ Name = '首次切换后保留选择，换目录时按项目选版'; ShellArgs = @() }
        @{ Name = '首次切换支持前置全局选项'; ShellArgs = @('-PrefixOptions') }
    ) {
        $output = & $enginePath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath -ProfileEnv $profileEnv @ShellArgs 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
    }
}
