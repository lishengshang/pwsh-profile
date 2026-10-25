# Pester 5/6 兼容测试：Conda shell hook 接入与禁用开关。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/CondaIntegration.Tests.ps1"

Describe 'Conda 初始化接入' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $envScript = Join-Path (Get-TestRepoRoot) 'profile\env.ps1'
        $originalTools = $global:__Tools
        $originalNoConda = $env:PROFILE_NO_CONDA
        $originalFzfOptions = $env:FZF_DEFAULT_OPTS
        function Use-CachedInit {
            param($Command, $CacheFile, $Arguments, $TtlDays)
        }
    }
    BeforeEach {
        $global:__Tools = @{
            conda = [pscustomobject]@{ Name = 'conda'; Source = 'C:\fake\conda.exe' }
        }
        Remove-Item Env:PROFILE_NO_CONDA -ErrorAction SilentlyContinue
        Mock Use-CachedInit {}
    }
    AfterAll {
        $global:__Tools = $originalTools
        $env:PROFILE_NO_CONDA = $originalNoConda
        $env:FZF_DEFAULT_OPTS = $originalFzfOptions
    }

    It '使用入口探测结果并仅按工具版本缓存' {
        . $envScript

        Should -Invoke Use-CachedInit -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'conda' -and
            $CacheFile -eq (Join-Path $env:TEMP 'conda-init-cache.ps1') -and
            $TtlDays -eq 0 -and
            @($Arguments).Count -eq 2 -and
            $Arguments[0] -eq 'shell.powershell' -and
            $Arguments[1] -eq 'hook'
        }
    }

    It 'PROFILE_NO_CONDA 跳过初始化' {
        $env:PROFILE_NO_CONDA = '1'

        . $envScript

        Should -Invoke Use-CachedInit -Times 0 -Exactly
    }
}
