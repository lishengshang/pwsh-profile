# 使用子进程验证目录记录与提示符，隔离真实模块和工具数据。

Describe 'zoxide 目录记录与跳转' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repo = Get-TestRepoRoot
        $root = New-TestTempRoot 'pester-zoxide'
        $runner = Join-Path $root 'run.ps1'
        $source = @'
param([string]$Repo, [string]$Fixture, [string]$Mode)
$ErrorActionPreference = 'Stop'
$env:TEMP = $Fixture
$env:PROFILE_NO_COMPLETIONS = '1'
$zoxide = Join-Path $Fixture 'zoxide.cmd'
$global:__Tools = @{ zoxide = [pscustomobject]@{ Source = $zoxide } }
$global:fixturePreCommands = 0
$global:fixtureOtherLocations = 0

if ($Mode -eq 'Starship') {
    $global:__Tools.starship = [pscustomobject]@{ Source = (Join-Path $Fixture 'starship.cmd') }
    function global:Invoke-Starship-PreCommand { $global:fixturePreCommands++ }
}

Set-Location -LiteralPath $Fixture
$locationHookAvailable = $null -ne $ExecutionContext.InvokeCommand.PSObject.Properties['LocationChangedAction']
if ($locationHookAvailable) {
    $ExecutionContext.InvokeCommand.LocationChangedAction = [EventHandler[System.Management.Automation.LocationChangedEventArgs]] {
        $global:fixtureOtherLocations++
    }
}

. (Join-Path $Repo 'profile\init-cache.ps1')
$promptScript = Join-Path $Repo 'profile\prompt.ps1'
$moduleScript = Join-Path $Repo 'profile\modules.ps1'
. $promptScript
. $moduleScript

if ($Mode -eq 'EarlyJump') {
    $early = Join-Path $Fixture 'early'
    $null = [IO.Directory]::CreateDirectory($early)
    z $early
    if ($PWD.Path -ne $early -or (Get-Command zi).CommandType -ne 'Alias') { throw 'Early aliases failed' }
    if ((Get-Command prompt).Definition -notmatch '__Get-CachedInitScript') { throw 'Early z changed prompt' }
}

$expectedPrompt = if ($Mode -eq 'Starship') { 'starship fixture' } else { 'PS> ' }
$global:LASTEXITCODE = 17
if ((prompt) -cne $expectedPrompt -or $LASTEXITCODE -ne 17) { throw 'Initial prompt changed prompt or exit code' }

$first = Join-Path $Fixture 'before-first-z'
$second = Join-Path $Fixture 'after-reload'
$null = [IO.Directory]::CreateDirectory($first)
$null = [IO.Directory]::CreateDirectory($second)
$global:LASTEXITCODE = 27
Set-Location -LiteralPath $first
if ((prompt) -cne $expectedPrompt -or $LASTEXITCODE -ne 27) { throw 'Recording changed prompt or exit code' }
if ($Mode -ne 'EarlyJump' -and (Get-Command z).CommandType -ne 'Function') { throw 'History initialized navigation early' }

. $promptScript
. $moduleScript
if ((prompt) -cne $expectedPrompt) { throw 'Reloaded prompt changed' }
Set-Location -LiteralPath $second
$null = prompt
$null = prompt

$visits = @(Get-Content -LiteralPath (Join-Path $Fixture 'visits.txt') | ForEach-Object { $_.Trim('"') })
if ($visits.Count -ne 2 -or $visits[0] -ne $first -or $visits[1] -ne $second) { throw "Incorrect visits: $($visits -join ', ')" }
if ($Mode -eq 'Starship' -and $global:fixturePreCommands -ne 5) { throw 'Existing Starship precommand lost or duplicated' }
if ($locationHookAvailable -and $Mode -ne 'EarlyJump' -and $global:fixtureOtherLocations -ne 2) { throw 'Existing location callback lost or duplicated' }

z $first
if ($PWD.Path -ne $first -or (Get-Command zi).CommandType -ne 'Alias') { throw 'Aliases failed after history and reload' }
'OK'
'@
        [IO.File]::WriteAllText($runner, $source, [Text.UTF8Encoding]::new($true))
    }

    AfterAll {
        Remove-Item -LiteralPath $root -Recurse -Force
    }

    It '在 <Shell> 的 <Mode> 模式下独立记录目录并保留提示符' -ForEach @(
        @{ Shell = 'pwsh.exe'; Mode = 'Default' }
        @{ Shell = 'powershell.exe'; Mode = 'Starship' }
        @{ Shell = 'powershell.exe'; Mode = 'EarlyJump' }
    ) {
        $fixture = Join-Path $root $Mode
        $null = [IO.Directory]::CreateDirectory($fixture)
        [IO.File]::WriteAllLines((Join-Path $fixture 'zoxide.cmd'), @(
            '@echo off'
            'if "%~1"=="add" goto record'
            'if not "%~3"=="--hook" exit /b 3'
            'if not "%~4"=="none" exit /b 4'
            'type "%~dp0zoxide-generated.ps1"'
            'exit /b 0'
            ':record'
            'echo "%~3">> "%~dp0visits.txt"'
            'exit /b 0'
        ), [Text.Encoding]::ASCII)
        [IO.File]::WriteAllLines((Join-Path $fixture 'zoxide-generated.ps1'), @(
            'function global:Invoke-ZoxideFixtureJump { param($Path); Set-Location -LiteralPath $Path }'
            'Set-Alias -Name z -Value Invoke-ZoxideFixtureJump -Scope Global -Force'
            'Set-Alias -Name zi -Value Invoke-ZoxideFixtureJump -Scope Global -Force'
        ), [Text.Encoding]::ASCII)
        if ($Mode -eq 'Starship') {
            [IO.File]::WriteAllLines((Join-Path $fixture 'starship.cmd'), @(
                '@echo off'
                'type "%~dp0starship-generated.ps1"'
                'exit /b 0'
            ), [Text.Encoding]::ASCII)
            [IO.File]::WriteAllText((Join-Path $fixture 'starship-generated.ps1'),
                "function global:prompt { Invoke-Starship-PreCommand; 'starship fixture' }", [Text.Encoding]::ASCII)
        }

        $output = & $Shell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -Repo $repo -Fixture $fixture -Mode $Mode
        $LASTEXITCODE | Should -Be 0
        $output | Should -Be 'OK'
    }
}
