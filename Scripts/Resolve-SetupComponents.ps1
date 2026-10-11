#Requires -Version 5.1
# ==============================================================
# setup.ps1 组件解析（从 setup.ps1 提取的可测试单元，被其 dot-source）
# -Minimal = core；-Full = 全部；-Components 显式指定；只给 -SkipComponents =
# 基于 Standard 剔除；全部缺省 = 交互终端进向导（PendingWizard 标记，实际执行
# 推迟到 setup 工具清单定义之后），否则 Standard。
# 组件常量（$allComponents / $standardComponents）由调用方传入——它们还被
# setup 的链接/工具防呆与向导默认值消费，事实来源仍在 setup.ps1。
# ==============================================================

# 容忍逗号分隔的单 token：pwsh -File 下数组参数不会贪心收集后续参数，
# "-Components core,gitui" 会整体作为单个字符串传入；交互式会话里两种写法
# 都已是数组，按逗号再拆一次是无害的幂等操作。
function __NormalizeComponents ([string[]]$List) {
    @($List | ForEach-Object { $_ -split '\s*,\s*' } | Where-Object { $_ })
}

function Resolve-SetupComponents {
    # 复数名词是函数语义本身（解析一组组件的完整选择矩阵），非命名疏忽
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = '解析多个组件的选择，复数语义正确')]
    [CmdletBinding(PositionalBinding = $false)]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)][string[]]$AllComponents,
        [Parameter(Mandatory)][string[]]$StandardComponents,
        [switch]$Minimal,
        [switch]$Full,
        [string[]]$Components,
        [string[]]$SkipComponents,
        [switch]$Yes,
        [switch]$Wizard,
        # 交互终端判定参数化供测试注入；默认取宿主真实状态
        [bool]$Interactive = ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected)
    )

    # 显式初始化，不依赖「未定义变量即 $null」的隐式契约
    $pendingWizard = $false
    if ($Minimal -and $Full) {
        throw '-Minimal 与 -Full 互斥，请只选其一（或改用 -Components 显式指定）。'
    }
    $Components     = __NormalizeComponents $Components
    $SkipComponents = __NormalizeComponents $SkipComponents
    if ($Components) {
        $effectiveComponents = @($Components | Where-Object { $_ -in $AllComponents })
        $unknown = @($Components | Where-Object { $_ -notin $AllComponents })
        if ($unknown) {
            Write-Warning "未知组件将被忽略: $($unknown -join ', ')（合法值: $($AllComponents -join ', ')）"
        }
        # 显式指定却全部无效，几乎必然是调用方式/拼写错误——静默空集会让用户
        # 误以为装好了，必须终止
        if (-not $effectiveComponents) {
            throw "-Components 未包含任何合法组件（收到: $($Components -join ', ')；合法值: $($AllComponents -join ', ')）。"
        }
    } elseif ($Minimal) {
        $effectiveComponents = @('core')
    } elseif ($Full) {
        $effectiveComponents = @($AllComponents)
    } elseif ($SkipComponents) {
        # 只给了 -SkipComponents：视为显式选择（基于 Standard 剔除，不进向导），
        # 后续 SkipComponents 过滤块会应用并在剔空时报错
        $effectiveComponents = @($StandardComponents)
    } else {
        # 无显式组件参数：交互终端进入向导（-Wizard 可强制、优先于 -Yes）；
        # -Yes 或 stdin 被重定向（CI/管道）时保持原全自动行为（Standard）。
        $pendingWizard = $Wizard -or ($Interactive -and -not $Yes)
        $effectiveComponents = @($StandardComponents)
    }
    if ($SkipComponents) {
        $unknownSkip = @($SkipComponents | Where-Object { $_ -notin $AllComponents })
        if ($unknownSkip) {
            Write-Warning "SkipComponents 中的未知组件将被忽略: $($unknownSkip -join ', ')（合法值: $($AllComponents -join ', ')）"
        }
        $effectiveComponents = @($effectiveComponents | Where-Object { $_ -notin $SkipComponents })
        if (-not $effectiveComponents) {
            throw "-SkipComponents（$($SkipComponents -join ', ')）剔除了全部组件，没有可安装的内容。"
        }
    }
    $effectiveComponents = @($effectiveComponents | Select-Object -Unique)

    return @{
        Components    = $effectiveComponents
        PendingWizard = $pendingWizard
    }
}
