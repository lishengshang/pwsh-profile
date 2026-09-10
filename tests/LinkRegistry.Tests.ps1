# Pester 5/6 兼容测试：链接注册表读写（Scripts/LinkRegistry.ps1）
# 注意：Pester 6 中每个块运行在独立 script scope，$script: 变量不再跨块共享，
# 因此全部使用普通变量（动态作用域在 Pester 5/6 均成立）。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/LinkRegistry.Tests.ps1"
# 不需要管理员权限：Junction / HardLink 无特权即可创建。

Describe 'Get-LinkRegistryEntries' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-reg-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '注册表不存在时返回空数组' {
        Get-LinkRegistryEntries (Join-Path $root 'missing.json') | Should -Be @()
    }

    It '正常 JSON 数组按对象数组返回' {
        $reg = Join-Path $root 'normal.json'
        Set-Content -Path $reg -Encoding UTF8 -Value @'
[
  { "Target": "C:\\a\\t1", "Source": "C:\\r\\s1", "LinkType": "HardLink" },
  { "Target": "C:\\a\\t2", "Source": "C:\\r\\s2", "LinkType": "Copy" }
]
'@
        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 2
        $entries[0].Target | Should -Be 'C:\a\t1'
        $entries[1].LinkType | Should -Be 'Copy'
    }

    It '5.1 合并数组形态的 JSON 被展开为对象数组' {
        # Windows PowerShell 5.1 读取顶层对象数组时会把同名字段合并成数组，
        # 函数必须展开还原，否则 Target/Source/LinkType 会是数组
        $reg = Join-Path $root 'merged.json'
        Set-Content -Path $reg -Encoding UTF8 -Value @'
{
  "Target": ["C:\\a\\t1", "C:\\a\\t2"],
  "Source": ["C:\\r\\s1", "C:\\r\\s2"],
  "LinkType": ["HardLink", "Copy"]
}
'@
        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 2
        $entries[0].Target | Should -Be 'C:\a\t1'
        $entries[0].Source | Should -Be 'C:\r\s1'
        $entries[1].LinkType | Should -Be 'Copy'
        # 展开后必须是标量字符串而不是数组
        $entries[0].Target | Should -BeOfType [string]
    }

    It '损坏的 JSON 视为空（按未登记处理）' {
        $reg = Join-Path $root 'corrupt.json'
        Set-Content -Path $reg -Encoding UTF8 -Value '{ not valid json !!!'
        Get-LinkRegistryEntries $reg | Should -Be @()
    }
}

Describe 'Save-LinkRegistryEntries / Set-LinkRegistryEntry' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-reg-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '写入会自动创建父目录' {
        $reg = Join-Path $root 'nested\dir\linked-targets.json'
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = 'C:\a\t1'; Source = 'C:\r\s1'; LinkType = 'HardLink' }
        )
        Test-Path $reg | Should -BeTrue
    }

    It '单条目也写成 JSON 数组（兼容 -InputObject 语义）' {
        $reg = Join-Path $root 'single.json'
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = 'C:\a\t1'; Source = 'C:\r\s1'; LinkType = 'Copy' }
        )
        $raw = (Get-Content $reg -Raw).Trim()
        $raw.StartsWith('[') | Should -BeTrue
        @(Get-LinkRegistryEntries $reg).Count | Should -Be 1
    }

    It '同目标重复登记只保留最新一条且类型生效' {
        $reg = Join-Path $root 'overwrite.json'
        Set-LinkRegistryEntry -Path $reg -Target 'C:\a\t1' -Source 'C:\r\s1' -LinkType 'HardLink'
        Set-LinkRegistryEntry -Path $reg -Target 'C:\a\t1' -Source 'C:\r\s1' -LinkType 'Copy'
        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 1
        $entries[0].LinkType | Should -Be 'Copy'
    }

    It '不同目标逐条追加' {
        $reg = Join-Path $root 'multi.json'
        Set-LinkRegistryEntry -Path $reg -Target 'C:\a\t1' -Source 'C:\r\s1' -LinkType 'HardLink'
        Set-LinkRegistryEntry -Path $reg -Target 'C:\a\t2' -Source 'C:\r\s2' -LinkType 'Junction'
        @(Get-LinkRegistryEntries $reg).Count | Should -Be 2
    }
}

Describe 'Get-ManagedLinkState 判定规则' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-state-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '目标不存在时返回未管理' {
        $state = Get-ManagedLinkState (Join-Path $root 'src.txt') (Join-Path $root 'no-such-target.txt') "$root\reg.json"
        $state.IsManaged | Should -BeFalse
    }

    It 'HardLink 关系判定为受管' {
        $case = Join-Path $root 'hardlink'
        $src = Join-Path $case 'src.txt'
        $tgt = Join-Path $case 'tgt.txt'
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        Set-Content -Path $src -Value 'v1'
        $null = New-Item -ItemType HardLink -Path $tgt -Target $src
        $state = Get-ManagedLinkState $src $tgt "$case\reg.json"
        $state.IsManaged | Should -BeTrue
        $state.LinkType | Should -Be 'HardLink'
    }

    It 'Junction 指向仓库源判定为受管' {
        $case = Join-Path $root 'junction'
        $src = Join-Path $case 'srcdir'
        $tgt = Join-Path $case 'tgtdir'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $null = New-Item -ItemType Junction -Path $tgt -Target $src
        $state = Get-ManagedLinkState $src $tgt "$case\reg.json"
        $state.IsManaged | Should -BeTrue
        $state.LinkType | Should -Be 'Junction'
    }

    It 'Junction 指向别处不算受管' {
        $case = Join-Path $root 'junction-foreign'
        $src = Join-Path $case 'srcdir'
        $other = Join-Path $case 'otherdir'
        $tgt = Join-Path $case 'tgtdir'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType Directory -Path $other -Force | Out-Null
        $null = New-Item -ItemType Junction -Path $tgt -Target $other
        $state = Get-ManagedLinkState $src $tgt "$case\reg.json"
        $state.IsManaged | Should -BeFalse
    }

    It 'Copy 登记且哈希相同判定为受管' {
        $case = Join-Path $root 'copy-ok'
        $src = Join-Path $case 'src.txt'
        $tgt = Join-Path $case 'tgt.txt'
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        Set-Content -Path $src -Value 'same'
        Copy-Item -Path $src -Destination $tgt
        $reg = "$case\reg.json"
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgt; Source = $src; LinkType = 'Copy' }
        )
        $state = Get-ManagedLinkState $src $tgt $reg
        $state.IsManaged | Should -BeTrue
        $state.LinkType | Should -Be 'Copy'
    }

    It 'Copy 登记但内容不同不算受管（等待刷新）' {
        $case = Join-Path $root 'copy-diff'
        $src = Join-Path $case 'src.txt'
        $tgt = Join-Path $case 'tgt.txt'
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        Set-Content -Path $src -Value 'v2'
        Set-Content -Path $tgt -Value 'v1'
        $reg = "$case\reg.json"
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgt; Source = $src; LinkType = 'Copy' }
        )
        $state = Get-ManagedLinkState $src $tgt $reg
        $state.IsManaged | Should -BeFalse
    }

    It '内容恰好相同但未登记的文件不算受管（防误判规则）' {
        $case = Join-Path $root 'copy-unregistered'
        $src = Join-Path $case 'src.txt'
        $tgt = Join-Path $case 'tgt.txt'
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        Set-Content -Path $src -Value 'same'
        Copy-Item -Path $src -Destination $tgt
        $state = Get-ManagedLinkState $src $tgt "$case\reg.json"
        $state.IsManaged | Should -BeFalse
    }

    It 'CopyDirectory 登记且 Source 匹配判定为受管' {
        $case = Join-Path $root 'copydir'
        $src = Join-Path $case 'srcdir'
        $tgt = Join-Path $case 'tgtdir'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Copy-Item -Path $src -Destination $tgt -Recurse
        $reg = "$case\reg.json"
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' }
        )
        $state = Get-ManagedLinkState $src $tgt $reg
        $state.IsManaged | Should -BeTrue
        $state.LinkType | Should -Be 'CopyDirectory'
    }
}

Describe 'ConvertFrom-LegacyLinkRegistry' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-legacy-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'Junction 目标按磁盘 LinkType 识别' {
        $case = Join-Path $root 'junction'
        $repo = Join-Path $case 'repo'
        $src = Join-Path $repo 'srcdir'
        $tgt = Join-Path $case 'tgtdir'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        $null = New-Item -ItemType Junction -Path $tgt -Target $src
        $manifest = @(@{ Target = $tgt; Source = 'srcdir' })
        $txt = Join-Path $case 'legacy.txt'
        Set-Content -Path $txt -Value $tgt
        $entries = ConvertFrom-LegacyLinkRegistry -LegacyTxt $txt -Manifest $manifest -RepoDir $repo
        $entries.Count | Should -Be 1
        $entries[0].LinkType | Should -Be 'Junction'
        $entries[0].Source | Should -Be $src
    }

    It 'HardLink 目标经 fsutil 确认后识别' {
        $case = Join-Path $root 'hardlink'
        $repo = Join-Path $case 'repo'
        $src = Join-Path $repo 'app.toml'
        $tgt = Join-Path $case 'tgt.toml'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        Set-Content -Path $src -Value 'v1'
        $null = New-Item -ItemType HardLink -Path $tgt -Target $src
        $manifest = @(@{ Target = $tgt; Source = 'app.toml' })
        $txt = Join-Path $case 'legacy.txt'
        Set-Content -Path $txt -Value $tgt
        $entries = ConvertFrom-LegacyLinkRegistry -LegacyTxt $txt -Manifest $manifest -RepoDir $repo
        $entries.Count | Should -Be 1
        $entries[0].LinkType | Should -Be 'HardLink'
    }

    It '普通文件按 Copy 降级、普通目录按 CopyDirectory 降级' {
        $case = Join-Path $root 'fallback'
        $repo = Join-Path $case 'repo'
        $srcFile = Join-Path $repo 'app.toml'
        $tgtFile = Join-Path $case 'tgt.toml'
        $srcDir = Join-Path $repo 'srcdir'
        $tgtDir = Join-Path $case 'tgtdir'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        New-Item -ItemType Directory -Path $srcDir -Force | Out-Null
        Set-Content -Path $srcFile -Value 'v1'
        Copy-Item -Path $srcFile -Destination $tgtFile
        Copy-Item -Path $srcDir -Destination $tgtDir -Recurse
        $manifest = @(
            @{ Target = $tgtFile; Source = 'app.toml' }
            @{ Target = $tgtDir; Source = 'srcdir' }
        )
        $txt = Join-Path $case 'legacy.txt'
        Set-Content -Path $txt -Value @($tgtFile, $tgtDir)
        $entries = ConvertFrom-LegacyLinkRegistry -LegacyTxt $txt -Manifest $manifest -RepoDir $repo
        $entries.Count | Should -Be 2
        ($entries | Where-Object { $_.Target -eq $tgtFile }).LinkType | Should -Be 'Copy'
        ($entries | Where-Object { $_.Target -eq $tgtDir }).LinkType | Should -Be 'CopyDirectory'
    }

    It '清单中已不存在的旧条目被放弃迁移' {
        $case = Join-Path $root 'stale'
        $repo = Join-Path $case 'repo'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        $txt = Join-Path $case 'legacy.txt'
        Set-Content -Path $txt -Value 'C:\no\longer\managed\target'
        $entries = ConvertFrom-LegacyLinkRegistry -LegacyTxt $txt -Manifest @() -RepoDir $repo
        $entries | Should -Be @()
    }
}
