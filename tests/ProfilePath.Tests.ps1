# Pester 5/6 兼容测试：子 PowerShell 加载入口时继承已激活的 Python 环境。

Describe 'Profile 的 PATH 继承' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repoProfile = Join-Path (Get-TestRepoRoot) 'Microsoft.PowerShell_profile.ps1'
        $probePath = Join-Path $TestDrive 'probe.ps1'
        $condaPrefix = Join-Path $TestDrive 'conda env'
        $venvPrefix = Join-Path $TestDrive 'uv env'
        $null = New-Item -ItemType Directory -Path (Join-Path $condaPrefix 'conda-meta')
        $null = New-Item -ItemType Directory -Path (Join-Path $venvPrefix 'Scripts')
        $null = New-Item -ItemType File -Path (Join-Path $venvPrefix 'pyvenv.cfg')

        Set-Content -LiteralPath $probePath -Encoding UTF8 -Value @'
param($RepoProfile, $Kind, $Prefix)
$ErrorActionPreference = 'Stop'
$env:PROFILE_QUIET = '1'
$env:PROFILE_NO_CONDA = '1'
$env:PROFILE_NO_FNM = '1'
$env:PROFILE_NO_COMPLETIONS = '1'
$env:PROFILE_DEBUG = $null
$env:PROFILE_KEEP_PARENT_PATH = $null
$env:CONDA_PREFIX = $null
$env:VIRTUAL_ENV = $null
$environmentPath = $Prefix
switch ($Kind) {
    'conda' { $env:CONDA_PREFIX = $Prefix }
    'venv' {
        $env:VIRTUAL_ENV = $Prefix
        $environmentPath = Join-Path $Prefix 'Scripts'
    }
    'keep' { $env:PROFILE_KEEP_PARENT_PATH = '1' }
}
$env:PATH = "$environmentPath;$env:PATH"
. $RepoProfile
($env:PATH -split ';')[0] -eq $environmentPath
'@

        function Test-ProfilePathInheritance {
            param([string]$Kind, [string]$Prefix)
            $result = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -NonInteractive -File $probePath $repoProfile $Kind $Prefix
            $LASTEXITCODE | Should -Be 0
            $result | Select-Object -Last 1
        }
    }

    It '保留激活的 Conda 环境' {
        Test-ProfilePathInheritance -Kind conda -Prefix $condaPrefix | Should -Be 'True'
    }

    It '保留激活的 venv 环境' {
        Test-ProfilePathInheritance -Kind venv -Prefix $venvPrefix | Should -Be 'True'
    }

    It '失效的 Conda 或 venv 路径不影响注册表 PATH 重建' {
        $missingPrefix = Join-Path $TestDrive 'missing env'
        Test-ProfilePathInheritance -Kind conda -Prefix $missingPrefix | Should -Be 'False'
        Test-ProfilePathInheritance -Kind venv -Prefix $missingPrefix | Should -Be 'False'
    }

    It 'PROFILE_KEEP_PARENT_PATH 保留普通父进程 PATH' {
        Test-ProfilePathInheritance -Kind keep -Prefix $TestDrive | Should -Be 'True'
    }
}
