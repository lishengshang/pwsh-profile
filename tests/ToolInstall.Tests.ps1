Describe '安装工具探测' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        . (Join-Path (Get-TestRepoRoot) 'Scripts\ToolInstall.ps1')
        function winget { throw 'Unexpected WinGet invocation' }
        function Invoke-TestToolCommand {}
    }

    It '按实际命令识别 PATH 中的便携程序' {
        Set-Content -LiteralPath (Join-Path $TestDrive 'pester-managed-tool.cmd') -Encoding ASCII -Value '@exit /b 0'
        $previousPath = $env:PATH
        try {
            $env:PATH = "$TestDrive;$previousPath"
            Test-ManagedToolInstalled -Name '测试工具' -Id Fixture.Tool -CommandName pester-managed-tool | Should -BeTrue
            Test-ManagedToolInstalled -Name '测试工具' -Id Fixture.Tool -CommandName pester-managed-tool -PathOnly | Should -BeTrue
        }
        finally {
            $env:PATH = $previousPath
        }
    }

    It '同名 PowerShell 函数不能代替可执行程序' {
        Test-ManagedToolInstalled -Name '测试工具' -Id Fixture.Tool -CommandName Invoke-TestToolCommand -PathOnly |
            Should -BeFalse
    }

    It '实际命令缺失时可以用 WinGet 登记兜底' {
        Mock winget {
            $global:LASTEXITCODE = 0
            'Test Tool  Fixture.Tool  1.0'
        }
        Test-ManagedToolInstalled -Name '测试工具' -Id Fixture.Tool -CommandName pester-missing-tool |
            Should -BeTrue
    }

    It 'WinGet 查询失败时视为未安装' {
        Mock winget {
            $global:LASTEXITCODE = 12
            'Fixture.Tool'
        }
        Test-ManagedToolInstalled -Name '测试工具' -Id Fixture.Tool -CommandName pester-missing-tool |
            Should -BeFalse
    }
}
