Describe 'PSFzf 空闲事件订阅' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $modulesPath = Join-Path (Get-TestRepoRoot) 'profile\modules.ps1'
        $enginePath = (Get-Process -Id $PID).Path
        $probePath = Join-Path $TestDrive 'idle-probe.ps1'
        $probe = @'
param([string]$ModulesPath)
$ErrorActionPreference = 'Stop'
$env:PROFILE_NO_COMPLETIONS = '1'
$env:PROFILE_FZF_TAB = $null
$global:__Tools = @{ fzf = @{ Source = 'unused.exe' } }
$global:foreignEvents = 0
$global:projectEvents = 0
function global:Import-Module {
    param($Name, $ErrorAction)
    if ($Name -ne 'PSFzf') { throw "Unexpected module import: $Name" }
    $global:projectEvents++
}
function global:Set-PsFzfOption {
    param($PSReadlineChordProvider, $PSReadlineChordReverseHistory, [switch]$GitKeyBindings)
    if ($PSReadlineChordProvider -ne 'Ctrl+t' -or $PSReadlineChordReverseHistory -ne 'Ctrl+r' -or !$GitKeyBindings) {
        throw 'Unexpected PSFzf key setup'
    }
}
$foreign = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action { $global:foreignEvents++ }
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {}
. $ModulesPath
. $ModulesPath
$subscribers = @(Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle)
if ($subscribers.Count -ne 3 -or $subscribers.Action.Id -notcontains $foreign.Id) {
    throw 'Reload must preserve both foreign subscribers and one project subscriber'
}

foreach ($expected in 1..2) {
    $null = New-Event -SourceIdentifier PowerShell.OnIdle
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    while ($global:foreignEvents -lt $expected -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 25
    }
    if ($global:foreignEvents -ne $expected) { throw "Foreign subscriber did not run $expected time(s)" }
}
if ($global:projectEvents -ne 1) { throw 'The PSFzf action should run once' }
if (@(Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle).Count -ne 2) {
    throw 'One-shot expiration must preserve both foreign subscribers'
}

. $ModulesPath
$global:__Tools.Remove('fzf')
. $ModulesPath
if (@(Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle).Count -ne 2) {
    throw 'A reload without fzf should only clear the pending project subscription'
}
'@
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($true))
    }

    It '重载时保留其他订阅，自己的初始化最多运行一次' {
        $output = & $enginePath -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath -ModulesPath $modulesPath 2>&1 | Out-String
        $LASTEXITCODE | Should -Be 0 -Because $output
    }
}
