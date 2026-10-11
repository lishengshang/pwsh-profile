# Pester 5/6 兼容测试：setup 组件解析（Scripts/Resolve-SetupComponents.ps1）
# 覆盖 -Minimal/-Full/-Components/-SkipComponents 矩阵、未知组件告警、互斥校验
# 与向导触发标记。交互判定统一注入，测试不依赖宿主终端状态。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/SetupComponents.Tests.ps1"

Describe 'Resolve-SetupComponents 组件解析矩阵' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\Resolve-SetupComponents.ps1')
        $all = 'core', 'completion', 'editor', 'files', 'gitui'
        $standard = 'core', 'completion', 'gitui'
        # 非交互注入的调用模板（splat + 常量组件表）
        function Invoke-Resolve {
            param([hashtable]$Params)
            $Params.Interactive = $false
            Resolve-SetupComponents @Params -AllComponents $all -StandardComponents $standard
        }
    }

    It '缺省时解析为 Standard 且不进向导（非交互）' {
        $r = Invoke-Resolve @{}
        $r.Components | Should -Be $standard
        $r.PendingWizard | Should -BeFalse
    }

    It '-Minimal 只装 core' {
        (Invoke-Resolve @{ Minimal = $true }).Components | Should -Be 'core'
    }

    It '-Full 装全部组件' {
        (Invoke-Resolve @{ Full = $true }).Components | Should -Be $all
    }

    It '-Components 接受逗号分隔单 token（pwsh -File 形态）' {
        (Invoke-Resolve @{ Components = 'core,gitui' }).Components | Should -Be 'core', 'gitui'
    }

    It '-Components 接受数组形态' {
        (Invoke-Resolve @{ Components = 'core', 'gitui' }).Components | Should -Be 'core', 'gitui'
    }

    It '-Components 混合合法与未知时忽略未知并保留合法' {
        (Invoke-Resolve @{ Components = 'core', 'nope' }).Components | Should -Be 'core'
    }

    It '-Components 全部未知时终止' {
        { Invoke-Resolve @{ Components = 'nope', 'nada' } } | Should -Throw '*未包含任何合法组件*'
    }

    It '-Minimal 与 -Full 互斥' {
        { Invoke-Resolve @{ Minimal = $true; Full = $true } } | Should -Throw '*互斥*'
    }

    It '-SkipComponents 从 Standard 剔除' {
        (Invoke-Resolve @{ SkipComponents = 'gitui' }).Components | Should -Be 'core', 'completion'
    }

    It '-SkipComponents 未知项忽略不影响其余' {
        (Invoke-Resolve @{ SkipComponents = 'gitui,nope' }).Components | Should -Be 'core', 'completion'
    }

    It '-SkipComponents 剔空时终止' {
        { Invoke-Resolve @{ Components = 'core'; SkipComponents = 'core' } } | Should -Throw '*剔除了全部组件*'
    }

    It '无显式参数且交互时标记进向导，组件预置为 Standard' {
        $r = Resolve-SetupComponents -AllComponents $all -StandardComponents $standard -Interactive $true
        $r.PendingWizard | Should -BeTrue
        $r.Components | Should -Be $standard
    }

    It '-Yes 交互下不进向导（CI/自动化路径）' {
        $r = Resolve-SetupComponents -AllComponents $all -StandardComponents $standard -Interactive $true -Yes
        $r.PendingWizard | Should -BeFalse
    }

    It '-Wizard 强制进向导且优先于 -Yes' {
        $r = Resolve-SetupComponents -AllComponents $all -StandardComponents $standard -Interactive $false -Wizard -Yes
        $r.PendingWizard | Should -BeTrue
    }
}
