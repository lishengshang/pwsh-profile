# Pester 5/6 兼容测试：外部工具初始化缓存的读取、生成与降级。

Describe '外部工具初始化缓存' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        . (Join-Path (Get-TestRepoRoot) 'profile\init-cache.ps1')
        $root = New-TestTempRoot 'pester-init-cache'
        $originalTools = $global:__Tools

        function Set-CacheFixtureTool {
            param([string]$Path, [string]$Text, [int]$ExitCode = 0)

            $lines = @(
                '@echo off'
                'echo called>> "%~dp0calls.log"'
                'if exist "%~dp0fail" exit /b 13'
                if ($Text) { "echo $Text" }
                "exit /b $ExitCode"
            )
            [IO.File]::WriteAllLines($Path, $lines, [Text.Encoding]::ASCII)
        }

        function New-CacheFixture {
            $dir = Join-Path $root ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            $tool = Join-Path $dir 'tool.cmd'
            Set-CacheFixtureTool -Path $tool -Text "'initial data'"
            $global:__Tools = @{ demo = [pscustomobject]@{ Source = $tool } }
            [pscustomobject]@{
                Dir   = $dir
                Tool  = $tool
                Cache = Join-Path $dir 'init.ps1'
                Calls = Join-Path $dir 'calls.log'
                Fail  = Join-Path $dir 'fail'
            }
        }
    }

    AfterAll {
        $global:__Tools = $originalTools
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '不设置过期天数时仍能读取较早的匹配缓存' {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache
        (Get-Item -LiteralPath $fixture.Cache).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-30)

        $init = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -TtlDays 0

        (. $init) | Should -Be 'initial data'
        @(Get-Content -LiteralPath $fixture.Calls).Count | Should -Be 1
    }

    It '默认重建超过 7 天的缓存' {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache
        (Get-Item -LiteralPath $fixture.Cache).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-8)

        $init = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache

        (. $init) | Should -Be 'initial data'
        @(Get-Content -LiteralPath $fixture.Calls).Count | Should -Be 2
    }

    It '替换成时间更早的二进制后也重建缓存' {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -TtlDays 0
        Set-CacheFixtureTool -Path $fixture.Tool -Text "'changed data'"
        (Get-Item -LiteralPath $fixture.Tool).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-30)

        $init = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -TtlDays 0

        (. $init) | Should -Be 'changed data'
    }

    It '拒绝与可执行文件路径或参数不匹配的旧脚本' {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -Arguments @('init', 'pwd')
        $oldBinary = Join-Path $fixture.Dir 'older.cmd'
        Copy-Item -LiteralPath $fixture.Tool -Destination $oldBinary
        (Get-Item -LiteralPath $oldBinary).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-30)
        New-Item -ItemType File -Path $fixture.Fail | Out-Null

        $argsMismatch = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -Arguments @('pwd', 'init')
        $global:__Tools.demo.Source = $oldBinary
        $pathMismatch = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache -Arguments @('init', 'pwd')

        $argsMismatch | Should -BeNullOrEmpty
        $pathMismatch | Should -BeNullOrEmpty
    }

    It '生成无有效脚本时沿用已验证的同一工具缓存' -ForEach @(
        @{ Text = 'function ['; ExitCode = 0 }
        @{ Text = "'failed script'"; ExitCode = 13 }
        @{ Text = ''; ExitCode = 0 }
    ) {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache
        $before = Get-Content -LiteralPath $fixture.Cache -Raw
        Set-CacheFixtureTool -Path $fixture.Tool -Text $Text -ExitCode $ExitCode

        $init = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache

        (. $init) | Should -Be 'initial data'
        Get-Content -LiteralPath $fixture.Cache -Raw | Should -BeExactly $before
    }

    It '拒绝损坏的已标记缓存和无法确认来源的旧缓存' {
        $fixture = New-CacheFixture
        $null = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache
        $header = Get-Content -LiteralPath $fixture.Cache -TotalCount 1
        New-Item -ItemType File -Path $fixture.Fail | Out-Null

        Set-Content -LiteralPath $fixture.Cache -Value @($header, 'function [') -Encoding UTF8
        (__Get-CachedInitScript -Command demo -CacheFile $fixture.Cache) | Should -BeNullOrEmpty

        Set-Content -LiteralPath $fixture.Cache -Value "'legacy data'" -Encoding UTF8
        (__Get-CachedInitScript -Command demo -CacheFile $fixture.Cache) | Should -BeNullOrEmpty
    }

    It '落盘失败时仍返回可在调用方使用的已验证脚本' {
        $fixture = New-CacheFixture
        Set-CacheFixtureTool -Path $fixture.Tool -Text '$fixtureValue = 42'
        $missingCache = Join-Path $fixture.Dir 'missing\cache.ps1'

        $init = __Get-CachedInitScript -Command demo -CacheFile $missingCache
        . $init

        $fixtureValue | Should -Be 42
        Test-Path -LiteralPath $missingCache | Should -BeFalse
    }

    It '返回的程序块与缓存之后的变化无关且缓存带 UTF-8 BOM' {
        $fixture = New-CacheFixture
        $init = __Get-CachedInitScript -Command demo -CacheFile $fixture.Cache

        ([IO.File]::ReadAllBytes($fixture.Cache)[0..2] -join ',') | Should -Be '239,187,191'
        [IO.File]::WriteAllText($fixture.Cache, "'different data'")
        (. $init) | Should -Be 'initial data'
    }
}
