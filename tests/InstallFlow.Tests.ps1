# Pester 5/6 安装流程回归：真实子进程运行 setup/bootstrap，配置与注册表均在临时目录。

Describe '安装流程与用户配置保护' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repoRoot = Get-TestRepoRoot
        $root = New-TestTempRoot 'pester-install'
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'

        function New-SetupFixture {
            $caseRoot = Join-Path $root ([guid]::NewGuid().ToString('N'))
            $repo = Join-Path $caseRoot 'repo'
            foreach ($dir in 'Scripts', 'profile', 'nvim', 'lazygit', 'yazi') {
                New-Item -ItemType Directory -Path (Join-Path $repo $dir) -Force | Out-Null
            }
            $setupText = [IO.File]::ReadAllText((Join-Path $repoRoot 'setup.ps1'))
            $setupText = $setupText.Replace("Name = 'Starship';", "Name = 'FixtureMissingTool';")
            [IO.File]::WriteAllText((Join-Path $repo 'setup.ps1'), $setupText, [Text.UTF8Encoding]::new($true))
            Get-ChildItem (Join-Path $repoRoot 'Scripts') -Filter '*.ps1' -File |
                Copy-Item -Destination (Join-Path $repo 'Scripts')
            foreach ($file in 'Microsoft.PowerShell_profile.ps1', 'powershell.config.json', 'starship.toml', 'lazygit\config.yml', 'yazi\theme.toml') {
                Copy-Item (Join-Path $repoRoot $file) (Join-Path $repo $file)
            }
            # HOME 是宿主只读自动变量；只改临时清单里的引用，不改真实用户目录。
            $manifest = Join-Path $repo 'Scripts\Get-ManagedLinks.ps1'
            $text = [IO.File]::ReadAllText($manifest).Replace('$HOME', '$env:PWSH_TEST_HOME')
            [IO.File]::WriteAllText($manifest, $text, [Text.UTF8Encoding]::new($true))
            $wizard = @'
function Invoke-SetupWizard {
    param($Tools, $DefaultComponents, $ComponentModules)
    return @{ Components = @($env:PWSH_TEST_COMPONENTS -split ','); ExcludeTools = @() }
}
'@
            [IO.File]::WriteAllText((Join-Path $repo 'Scripts\Invoke-SetupWizard.ps1'), $wizard, [Text.UTF8Encoding]::new($true))
            $runner = @'
param([string]$Mode)
$ErrorActionPreference = 'Stop'
$env:LOCALAPPDATA = Join-Path $PSScriptRoot 'local'
$env:APPDATA = Join-Path $PSScriptRoot 'roaming'
$env:PWSH_TEST_HOME = Join-Path $PSScriptRoot 'home'
$PROFILE = Join-Path $PSScriptRoot 'profile\Microsoft.PowerShell_profile.ps1'
foreach ($dir in $env:LOCALAPPDATA, $env:APPDATA, $env:PWSH_TEST_HOME, (Split-Path $PROFILE)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
$setup = Join-Path $PSScriptRoot 'repo\setup.ps1'
$messages = & { switch ($Mode) {
    'Full' { & $setup -Full -SkipTools -Yes; & $setup -Full -SkipTools -Yes }
    'WizardFull' { $env:PWSH_TEST_COMPONENTS = 'core,completion,editor,files,gitui,python'; & $setup -Wizard -SkipTools -Yes }
    'WizardCore' { $env:PWSH_TEST_COMPONENTS = 'core'; & $setup -Wizard -SkipTools -Yes }
    'Minimal' { & $setup -Minimal -SkipTools -Yes }
    'MissingNvim' {
        function git {
            Set-Content -LiteralPath (Join-Path $PSScriptRoot 'git-attempted') -Value 'attempted'
            $global:LASTEXITCODE = 41
        }
        & $setup -Full -SkipTools -Yes
    }
    'PartialTools' {
        function winget {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq 'install') { $global:LASTEXITCODE = 7 }
        }
        function Get-PackageProvider { [CmdletBinding()] param($Name) 'NuGet' }
        function Get-Module { param([switch]$ListAvailable, $Name) }
        function Install-Module {
            [CmdletBinding()] param($Name, $Scope, [switch]$Force)
            if ($Name -eq 'PSCompletions') { throw 'fixture failure' }
        }
        & $setup -Components core,completion -Yes -ExcludeTools 'eza,zoxide,ripgrep,fd,bat,7-Zip,fnm,fzf'
    }
    default { throw 'Unknown fixture mode' }
} } 3>&1 6>&1 | Out-String
$reg = Join-Path $env:LOCALAPPDATA 'pwsh-profile\linked-targets.json'
[pscustomobject]@{
    Sources = @((Get-Content $reg -Raw | ConvertFrom-Json).Source | ForEach-Object { $_.Substring((Join-Path $PSScriptRoot 'repo').Length + 1) })
    Backups = @(Get-ChildItem (Split-Path $PROFILE) -Directory -Filter 'backup-*').Count
    Messages = $messages
} | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot 'result.json')
'@
            [IO.File]::WriteAllText((Join-Path $caseRoot 'run.ps1'), $runner, [Text.UTF8Encoding]::new($true))
            return $caseRoot
        }

        function Invoke-SetupFixture {
            param([string]$CaseRoot, [string]$Mode)
            $output = & $pwshPath -NoProfile -File (Join-Path $CaseRoot 'run.ps1') -Mode $Mode 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw $output }
            Get-Content (Join-Path $CaseRoot 'result.json') -Raw | ConvertFrom-Json
        }
    }
    AfterAll {
        Remove-Item -LiteralPath $root -Recurse -Force
    }

    It '显式 Full 与向导全选部署相同配置' {
        $explicit = Invoke-SetupFixture -CaseRoot (New-SetupFixture) -Mode Full
        $wizard = Invoke-SetupFixture -CaseRoot (New-SetupFixture) -Mode WizardFull
        $explicit.Sources | Should -Contain 'nvim'
        $explicit.Sources | Should -Contain 'yazi\theme.toml'
        @($wizard.Sources | Sort-Object) | Should -Be @($explicit.Sources | Sort-Object)
        $explicit.Backups | Should -Be 0
    }

    It '缺失 nvim 时 SkipTools 提示并继续部署其余配置' {
        $caseRoot = New-SetupFixture
        [IO.Directory]::Delete((Join-Path $caseRoot 'repo\nvim'))

        $result = Invoke-SetupFixture -CaseRoot $caseRoot -Mode MissingNvim

        Test-Path -LiteralPath (Join-Path $caseRoot 'git-attempted') | Should -BeFalse
        $result.Sources | Should -Contain 'Microsoft.PowerShell_profile.ps1'
        $result.Sources | Should -Not -Contain 'nvim'
        $result.Messages | Should -Match '未找到 nvim/ 配置'
        $result.Messages | Should -Match '安装部分完成[^\r\n]*LazyVim starter'
    }

    It '向导仅选 core 不部署其他组件的配置' {
        $result = Invoke-SetupFixture -CaseRoot (New-SetupFixture) -Mode WizardCore
        $result.Sources | Should -Contain 'starship.toml'
        $result.Sources | Should -Not -Contain 'lazygit\config.yml'
        $result.Sources | Should -Not -Contain 'nvim'
        $result.Sources | Should -Not -Contain 'yazi\theme.toml'
    }

    It 'Minimal 安装先备份损坏登记并恢复未选组件的受管链接' {
        $caseRoot = New-SetupFixture
        $target = Join-Path $caseRoot 'local\nvim'
        $source = Join-Path $caseRoot 'repo\nvim'
        $registryDir = Join-Path $caseRoot 'local\pwsh-profile'
        New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
        New-Item -ItemType Junction -Path $target -Target $source | Out-Null
        $registry = Join-Path $registryDir 'linked-targets.json'
        $original = '{ damaged registry'
        [IO.File]::WriteAllText($registry, $original)

        $result = Invoke-SetupFixture -CaseRoot $caseRoot -Mode Minimal

        $result.Sources | Should -Contain 'nvim'
        $backups = @(Get-ChildItem -LiteralPath $registryDir -File -Filter 'linked-targets.json.corrupt-*')
        $backups.Count | Should -Be 1
        [IO.File]::ReadAllText($backups[0].FullName) | Should -BeExactly $original
    }

    It '依赖安装部分完成时保留逐项告警并继续安装模块' {
        $result = Invoke-SetupFixture -CaseRoot (New-SetupFixture) -Mode PartialTools

        $result.Sources | Should -Contain 'Microsoft.PowerShell_profile.ps1'
        $result.Messages | Should -Match '已安装模块: PSFzf'
        $result.Messages | Should -Match '安装部分完成[^\r\n]*FixtureMissingTool[^\r\n]*PSCompletions'
        $result.Messages | Should -Not -Match '安装完成。'
    }

    It 'Minimal 安装保留旧 editor 登记下的新个人目录' {
        $caseRoot = New-SetupFixture
        $target = Join-Path $caseRoot 'local\nvim'
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        Set-Content (Join-Path $target 'personal.lua') 'personal'
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        Set-LinkRegistryEntry -Path (Join-Path $caseRoot 'local\pwsh-profile\linked-targets.json') `
            -Target $target -Source (Join-Path $caseRoot 'repo\nvim') -LinkType Junction

        $result = Invoke-SetupFixture -CaseRoot $caseRoot -Mode Minimal
        $result.Messages | Should -Match '安装部分完成'

        (Get-Item $target -Force).LinkType | Should -BeNullOrEmpty
        Get-Content (Join-Path $target 'personal.lua') | Should -Be 'personal'
    }
}

Describe 'bootstrap 传递安装结果' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repoRoot = Get-TestRepoRoot
        $root = New-TestTempRoot 'pester-bootstrap'
        $pwshPath = Join-Path $PSHOME 'pwsh.exe'
    }
    AfterAll {
        Remove-Item -LiteralPath $root -Recurse -Force
    }

    It 'setup 返回 <Code> 时引导结果为 <Success>' -ForEach @(
        @{ Code = 23; Success = $false }
        @{ Code = 0; Success = $true }
    ) {
        $caseRoot = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $caseRoot '.git') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $caseRoot 'setup.ps1'), "exit $Code", [Text.UTF8Encoding]::new($true))
        $runner = @'
param([string]$Bootstrap, [string]$Repo)
# bootstrap 只需探测 winget；已安装工具与已有仓库确保不会触发下载。
function winget { throw 'Unexpected installation attempt' }
& $Bootstrap -RepoDir $Repo -SkipPwsh -SkipTools -Yes
'@
        $runnerPath = Join-Path $caseRoot 'run.ps1'
        [IO.File]::WriteAllText($runnerPath, $runner, [Text.UTF8Encoding]::new($true))
        $output = & $pwshPath -NoProfile -File $runnerPath -Bootstrap (Join-Path $repoRoot 'bootstrap.ps1') -Repo $caseRoot 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($Success) {
            $exitCode | Should -Be 0
            $output | Should -Match '安装脚本已返回'
        }
        else {
            $exitCode | Should -Not -Be 0
            $output | Should -Not -Match '安装脚本已返回'
            $output | Should -Match '23'
        }
    }
}
