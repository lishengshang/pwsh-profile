# Pester 5/6 回归：使用临时修复脚本与 Git 桩检查同步结果。
Describe 'psync 的 Git 和配置结果' {
    It '根据 <Case> 报告实际结果' -ForEach @(
        @{ Case = 'Git 失败'; GitExit = 1; Pending = 0; Message = 'git pull 失败' }
        @{ Case = '链接待处理'; GitExit = 0; Pending = 1; Message = 'Git 已同步，仍有 1 个配置目标待处理' }
        @{ Case = '全部完成'; GitExit = 0; Pending = 0; Message = '配置已同步' }
    ) {
        $aliases = Join-Path (Split-Path $PSScriptRoot) 'profile\aliases.ps1'
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $scripts = Join-Path $repo 'Scripts'
        $null = New-Item -ItemType Directory -Path $scripts -Force
        $repair = @'
param([switch]$PassThru)
if (-not $PassThru) { throw 'Missing -PassThru' }
$global:LASTEXITCODE = 3
New-Item -Path (Join-Path $PSScriptRoot 'checked') -ItemType File -Force | Out-Null
[pscustomobject]@{ Unresolved = @(1..$Pending | Select-Object -First $Pending) }
'@
        [IO.File]::WriteAllText((Join-Path $scripts 'Repair-ConfigLinks.ps1'), $repair)
        function Invoke-TestGit { $global:LASTEXITCODE = $GitExit }

        $oldTools = $global:__Tools
        $oldRepo = $global:__ProfileRepoDir
        $oldExit = $global:LASTEXITCODE
        try {
            $global:__Tools = @{ git = @{ Source = 'Invoke-TestGit' } }
            $global:__ProfileRepoDir = $repo
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($aliases, [ref]$null, [ref]$null)
            $command = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'psync' }, $false)
            . ([scriptblock]::Create($command.Extent.Text))
            $output = psync 3>&1 6>&1 | Out-String

            $output | Should -Match $Message
            $LASTEXITCODE | Should -Be $GitExit
            (Test-Path -LiteralPath (Join-Path $scripts 'checked')) | Should -Be ($GitExit -eq 0)
            if ($GitExit -ne 0 -or $Pending) { $output | Should -Not -Match '配置已同步' }
        }
        finally {
            $global:__Tools = $oldTools
            $global:__ProfileRepoDir = $oldRepo
            $global:LASTEXITCODE = $oldExit
        }
    }
}
