# Pester 5/6 兼容测试：外部工具初始化缓存的有效期与版本失效。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/InitCache.Tests.ps1"

Describe 'Initialize-CachedInit 缓存失效策略' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        . (Join-Path (Get-TestRepoRoot) 'profile\init-cache.ps1')
        $root = New-TestTempRoot 'pester-init-cache'
        $originalTools = $global:__Tools

        function New-CacheFixture {
            $dir = Join-Path $root ([guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $dir | Out-Null
            $tool = Join-Path $dir 'tool.cmd'
            $cache = Join-Path $dir 'init.ps1'
            [IO.File]::WriteAllLines($tool, @('@echo off', 'echo # regenerated', 'exit /b 0'), [Text.Encoding]::ASCII)
            Set-Content -Path $cache -Value '# stale' -Encoding UTF8
            $global:__Tools = @{
                demo = [pscustomobject]@{ Name = 'demo'; Source = $tool }
            }
            [pscustomobject]@{ Tool = $tool; Cache = $cache }
        }
    }
    AfterAll {
        $global:__Tools = $originalTools
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'TtlDays 为 0 时过期缓存仍可用' {
        $fixture = New-CacheFixture
        (Get-Item $fixture.Tool).LastWriteTime = (Get-Date).AddDays(-40)
        (Get-Item $fixture.Cache).LastWriteTime = (Get-Date).AddDays(-30)

        $result = Initialize-CachedInit -Command demo -CacheFile $fixture.Cache -TtlDays 0

        $result | Should -BeTrue
        (Get-Content $fixture.Cache -Raw).Trim() | Should -Be '# stale'
    }

    It '默认策略会重建超过 7 天的缓存' {
        $fixture = New-CacheFixture
        (Get-Item $fixture.Tool).LastWriteTime = (Get-Date).AddDays(-40)
        (Get-Item $fixture.Cache).LastWriteTime = (Get-Date).AddDays(-30)

        $result = Initialize-CachedInit -Command demo -CacheFile $fixture.Cache

        $result | Should -BeTrue
        (Get-Content $fixture.Cache -Raw).Trim() | Should -Be '# regenerated'
    }

    It '工具比缓存新时不限时间也立即重建' {
        $fixture = New-CacheFixture
        (Get-Item $fixture.Cache).LastWriteTime = (Get-Date).AddDays(-1)
        (Get-Item $fixture.Tool).LastWriteTime = Get-Date

        $result = Initialize-CachedInit -Command demo -CacheFile $fixture.Cache -TtlDays 0

        $result | Should -BeTrue
        (Get-Content $fixture.Cache -Raw).Trim() | Should -Be '# regenerated'
    }

    It 'Use-CachedInit 转发 TtlDays 并加载缓存' {
        $fixture = New-CacheFixture
        Set-Content -Path $fixture.Cache -Value '$script:cachedInitLoaded = $true' -Encoding UTF8
        Mock Initialize-CachedInit { $true }

        Use-CachedInit -Command demo -CacheFile $fixture.Cache -TtlDays 0

        Should -Invoke Initialize-CachedInit -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'demo' -and $TtlDays -eq 0
        }
        $script:cachedInitLoaded | Should -BeTrue
    }
}
