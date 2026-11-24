# Pester 5/6 兼容测试：链接修复（Scripts/Repair-ConfigLinks.ps1）
# 覆盖五类链接的修复/跳过/降级语义，以及「未登记目标永远不碰」的边界。
# 说明 1：SymbolicLink 的建链需要管理员权限或开发者模式——CI（管理员）走真实
#         重建分支，本地非管理员走降级分支，两组分支都断言，保证两边都绿。
# 说明 2：Pester 6 中每个块运行在独立 script scope，$script: 变量不再跨块共享，
#         因此全部使用普通变量（动态作用域在 Pester 5/6 均成立）。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/Repair-ConfigLinks.Tests.ps1"

Describe 'Repair-ConfigLinks 五类链接修复' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repoRoot = Get-TestRepoRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $repairScript = Join-Path $repoRoot 'Scripts\Repair-ConfigLinks.ps1'
        $root = New-TestTempRoot 'pester-repair'

        # 按登记类型写一条注册表记录并运行修复（显式传参，不依赖跨块作用域）
        function Invoke-TestRepair {
            param([hashtable]$Entry, [string]$RegistryPath, [string]$ScriptPath, [switch]$PassThru)
            Save-LinkRegistryEntries -Path $RegistryPath -Entries @(
                [pscustomobject]@{
                    Target   = $Entry.Target
                    Source   = $Entry.Source
                    LinkType = $Entry.LinkType
                }
            )
            & $ScriptPath -Registry $RegistryPath -PassThru:$PassThru
        }
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    BeforeEach {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $src = Join-Path $case 'src'
        $tgt = Join-Path $case 'tgt'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $tgt) -Force | Out-Null
        $reg = Join-Path $case 'reg\linked-targets.json'
    }

    It 'Junction：目标被删除后重建' {
        Set-Content -Path (Join-Path $src 'settings.toml') -Value 'v2'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'Junction' } -RegistryPath $reg -ScriptPath $repairScript
        Test-Path $tgt | Should -BeTrue
        (Get-Item $tgt -Force).LinkType | Should -Be 'Junction'
        Get-Content (Join-Path $tgt 'settings.toml') | Should -Be 'v2'
    }

    It 'Junction：指向正确时跳过不重建' {
        Set-Content -Path (Join-Path $src 'settings.toml') -Value 'v1'
        $null = New-Item -ItemType Junction -Path $tgt -Target $src
        $created = (Get-Item $tgt -Force).CreationTime

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'Junction' } -RegistryPath $reg -ScriptPath $repairScript

        # 若被错误重建，CreationTime 会变化
        (Get-Item $tgt -Force).CreationTime | Should -Be $created
        (Get-LinkTargetPath $tgt) | Should -Be ([System.IO.Path]::GetFullPath($src).TrimEnd('\'))
    }

    It 'Junction：断链（源被删）后重建到现源' {
        Set-Content -Path (Join-Path $src 'settings.toml') -Value 'v1'
        $ghost = Join-Path $case 'ghost'
        New-Item -ItemType Directory -Path $ghost -Force | Out-Null
        $null = New-Item -ItemType Junction -Path $tgt -Target $ghost
        Remove-Item $ghost -Recurse -Force

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'Junction' } -RegistryPath $reg -ScriptPath $repairScript

        (Get-Item $tgt -Force).LinkType | Should -Be 'Junction'
        Get-Content (Join-Path $tgt 'settings.toml') | Should -Be 'v1'
    }

    It 'HardLink：源被替换（git pull 模拟）后重新硬链接' {
        # 第一代源与硬链接
        $srcFile = Join-Path $src 'app.toml'
        Set-Content -Path $srcFile -Value 'v1'
        $null = New-Item -ItemType HardLink -Path $tgt -Target $srcFile
        # 模拟 git pull：新 inode 替换源文件，目标成为孤儿副本
        Remove-Item $srcFile -Force
        Set-Content -Path $srcFile -Value 'v2'
        Get-Content $tgt | Should -Be 'v1'   # 前置确认：目标已是旧内容

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'HardLink' } -RegistryPath $reg -ScriptPath $repairScript

        Get-Content $tgt | Should -Be 'v2'
        (Get-Item $tgt -Force).LinkType | Should -Be 'HardLink'
        # 仓库即实体：两边共享同一 inode
        $srcNorm = ((Get-Item $srcFile).FullName.TrimEnd('\')) -replace '^[A-Za-z]:', ''
        (fsutil hardlink list $tgt 2>$null) |
            ForEach-Object { ($_ -replace '^[A-Za-z]:', '').Trim() } |
            Should -Contain $srcNorm
    }

    It 'HardLink：已硬链接时跳过不重建' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content -Path $srcFile -Value 'v1'
        $null = New-Item -ItemType HardLink -Path $tgt -Target $srcFile
        $created = (Get-Item $tgt -Force).CreationTime

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'HardLink' } -RegistryPath $reg -ScriptPath $repairScript

        (Get-Item $tgt -Force).CreationTime | Should -Be $created
    }

    It 'Junction：旧登记不能接管后来创建的个人目录' {
        New-Item -ItemType Directory -Path $tgt | Out-Null
        Set-Content (Join-Path $tgt 'personal.lua') 'personal'

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'Junction' } -RegistryPath $reg -ScriptPath $repairScript

        (Get-Item $tgt -Force).LinkType | Should -BeNullOrEmpty
        Get-Content (Join-Path $tgt 'personal.lua') | Should -Be 'personal'
    }

    It 'Junction：保留用户重新指向的有效链接' {
        $personal = Join-Path $case 'personal'
        New-Item -ItemType Directory -Path $personal | Out-Null
        Set-Content (Join-Path $personal 'keep.txt') 'personal'
        $null = New-Item -ItemType Junction -Path $tgt -Target $personal

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'Junction' } -RegistryPath $reg -ScriptPath $repairScript

        Get-LinkTargetPath $tgt | Should -Be $personal
        Get-Content (Join-Path $tgt 'keep.txt') | Should -Be 'personal'
    }

    It 'HardLink：重建前备份与源不同的失联文件' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content $srcFile 'repo'
        Set-Content $tgt 'personal'

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'HardLink' } -RegistryPath $reg -ScriptPath $repairScript

        Get-Content $tgt | Should -Be 'repo'
        $backups = @(Get-ChildItem -LiteralPath $case -Filter 'tgt.conflict-*')
        $backups.Count | Should -Be 1
        Get-Content -LiteralPath $backups[0].FullName | Should -Be 'personal'
        & $repairScript -Registry $reg
        @(Get-ChildItem -LiteralPath $case -Filter 'tgt.conflict-*').Count | Should -Be 1
    }

    It 'Copy：刷新前备份原内容' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content $srcFile 'repo'
        Set-Content $tgt 'personal'

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'Copy' } -RegistryPath $reg -ScriptPath $repairScript

        Get-Content $tgt | Should -Be 'repo'
        $backups = @(Get-ChildItem -LiteralPath $case -Filter 'tgt.conflict-*')
        $backups.Count | Should -Be 1
        Get-Content -LiteralPath $backups[0].FullName | Should -Be 'personal'
    }

    It '<Type>：备份失败时保留原文件并继续处理后续目标' -ForEach @(
        @{ Type = 'HardLink' }
        @{ Type = 'Copy' }
    ) {
        $srcFile = Join-Path $src 'app.toml'
        $nextTarget = Join-Path $case 'next.toml'
        Set-Content $srcFile 'repo'
        Set-Content $tgt 'personal'
        Mock Copy-Item { [IO.File]::Copy($Path, $Destination, $true) }
        Mock Copy-Item { throw '备份不可写' } -ParameterFilter { $Destination -like '*.conflict-*' }
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgt; Source = $srcFile; LinkType = $Type }
            [pscustomobject]@{ Target = $nextTarget; Source = $srcFile; LinkType = 'Copy' }
        )

        & $repairScript -Registry $reg

        Get-Content $tgt | Should -Be 'personal'
        Get-Content $nextTarget | Should -Be 'repo'
        Should -Invoke Copy-Item -Times 1 -Exactly -ParameterFilter { $Destination -like '*.conflict-*' }
    }

    It 'Copy：源更新后按哈希刷新副本' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content -Path $srcFile -Value 'v1'
        Copy-Item -Path $srcFile -Destination $tgt
        Set-Content -Path $srcFile -Value 'v2'

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'Copy' } -RegistryPath $reg -ScriptPath $repairScript

        Get-Content $tgt | Should -Be 'v2'
        (Get-Item $tgt -Force).LinkType | Should -BeNullOrEmpty
    }

    It 'Copy：内容一致时不重写' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content -Path $srcFile -Value 'same'
        Copy-Item -Path $srcFile -Destination $tgt
        # 目标时间戳留在过去、源更新——若被错误重写，目标时间会被刷新为源时间
        $old = (Get-Date).AddHours(-2)
        (Get-Item $tgt -Force).LastWriteTime = $old
        (Get-Item $srcFile -Force).LastWriteTime = (Get-Date)

        Invoke-TestRepair @{ Target = $tgt; Source = $srcFile; LinkType = 'Copy' } -RegistryPath $reg -ScriptPath $repairScript

        (Get-Item $tgt -Force).LastWriteTime | Should -Be $old
    }

    It 'CopyDirectory：旧登记保留既有文件，仅跟踪新复制的文件' {
        $newSource = Join-Path $src 'shared\new.txt'
        $newTarget = Join-Path $tgt 'shared\new.txt'
        New-Item -ItemType Directory -Path (Split-Path $newSource), $tgt | Out-Null
        Set-Content -LiteralPath $newSource -Value 'version 1'
        Set-Content -LiteralPath (Join-Path $src 'equal.txt') -Value 'same'
        Set-Content -LiteralPath (Join-Path $tgt 'equal.txt') -Value 'same'
        Set-Content -LiteralPath (Join-Path $src 'edited.txt') -Value 'repo'
        Set-Content -LiteralPath (Join-Path $tgt 'edited.txt') -Value 'personal'
        Set-Content -LiteralPath (Join-Path $tgt 'extra.txt') -Value 'untracked'
        $blockedSource = Join-Path $src 'blocked'
        New-Item -ItemType Directory -Path $blockedSource | Out-Null
        Set-Content -LiteralPath (Join-Path $blockedSource 'nested.txt') -Value 'repo'
        Set-Content -LiteralPath (Join-Path $tgt 'blocked') -Value 'personal file'

        $result = Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript -PassThru
        $result.Unresolved | Should -Contain $tgt

        Get-Content -LiteralPath (Join-Path $tgt 'edited.txt') | Should -Be 'personal'
        Get-Content -LiteralPath (Join-Path $tgt 'extra.txt') | Should -Be 'untracked'
        Get-Content -LiteralPath (Join-Path $tgt 'blocked') | Should -Be 'personal file'
        Get-Content -LiteralPath $newTarget | Should -Be 'version 1'
        $copyFiles = @(Get-LinkRegistryEntries $reg)[0].CopyFiles
        @($copyFiles).Count | Should -Be 1
        $copyFiles[0].Path | Should -BeExactly 'shared/new.txt'
        $copyFiles[0].Hash | Should -Be (Get-FileHash -LiteralPath $newSource -Algorithm SHA256).Hash

        Set-Content -LiteralPath $newSource -Value 'version 2'
        Set-Content -LiteralPath (Join-Path $src 'equal.txt') -Value 'changed by repo'
        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -Contain $tgt
        Get-Content -LiteralPath $newTarget | Should -Be 'version 2'
        Get-Content -LiteralPath (Join-Path $tgt 'equal.txt') | Should -Be 'same'
        Remove-Item -LiteralPath (Join-Path $src 'equal.txt') -Force
        & $repairScript -Registry $reg
        Get-Content -LiteralPath (Join-Path $tgt 'equal.txt') | Should -Be 'same'
    }

    It 'CopyDirectory：首次部署登记文件，后续更新和删除未改动的副本' {
        $srcFile = Join-Path $src 'nested\settings.txt'
        $srcGone = Join-Path $src 'gone.txt'
        $tgtFile = Join-Path $tgt 'nested\settings.txt'
        $tgtGone = Join-Path $tgt 'gone.txt'
        New-Item -ItemType Directory -Path (Split-Path $srcFile) | Out-Null
        Set-Content -LiteralPath $srcFile -Value 'first'
        Set-Content -LiteralPath $srcGone -Value 'delete me'

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript

        $copyFiles = @(Get-LinkRegistryEntries $reg)[0].CopyFiles
        @($copyFiles).Count | Should -Be 2
        ($copyFiles | Where-Object Path -CEQ 'nested/settings.txt').Hash | Should -Be (Get-FileHash -LiteralPath $srcFile -Algorithm SHA256).Hash
        ($copyFiles | Where-Object Path -CEQ 'gone.txt').Hash | Should -Be (Get-FileHash -LiteralPath $srcGone -Algorithm SHA256).Hash
        Set-Content -LiteralPath $srcFile -Value 'second'
        Remove-Item -LiteralPath $srcGone -Force

        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -BeNullOrEmpty
        Test-Path -LiteralPath $tgtGone | Should -BeFalse
        Get-Content -LiteralPath $tgtFile | Should -Be 'second'
        $entry = @(Get-LinkRegistryEntries $reg)[0]
        @($entry.CopyFiles).Count | Should -Be 1
        $entry.CopyFiles[0].Path | Should -BeExactly 'nested/settings.txt'
        $entry.CopyFiles[0].Hash | Should -Be (Get-FileHash -LiteralPath $srcFile -Algorithm SHA256).Hash

        (Get-Item -LiteralPath $reg).LastWriteTimeUtc = [DateTime]::UtcNow.AddMinutes(-10)
        $oldRegistryTime = (Get-Item -LiteralPath $reg).LastWriteTimeUtc
        $oldRegistryHash = (Get-FileHash -LiteralPath $reg).Hash
        $result = & $repairScript -Registry $reg -PassThru
        $result.Unresolved | Should -BeNullOrEmpty
        (Get-Item -LiteralPath $reg).LastWriteTimeUtc | Should -Be $oldRegistryTime
        (Get-FileHash -LiteralPath $reg).Hash | Should -Be $oldRegistryHash
    }

    It 'CopyDirectory：保留用户对跟踪文件的<Change>并报告冲突' -ForEach @(
        @{ Change = '修改'; RemoveLocal = $false }
        @{ Change = '删除'; RemoveLocal = $true }
    ) {
        $srcFile = Join-Path $src 'settings.txt'
        $tgtFile = Join-Path $tgt 'settings.txt'
        Set-Content -LiteralPath $srcFile -Value 'original'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript
        $originalHash = (Get-FileHash -LiteralPath $srcFile).Hash

        if ($RemoveLocal) {
            Remove-Item -LiteralPath $tgtFile -Force
        }
        else {
            Set-Content -LiteralPath $tgtFile -Value 'personal edit'
        }
        Set-Content -LiteralPath (Join-Path $tgt 'extra.txt') -Value 'personal file'
        Set-Content -LiteralPath $srcFile -Value 'repo edit'

        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -Contain $tgt
        Get-Content -LiteralPath (Join-Path $tgt 'extra.txt') | Should -Be 'personal file'
        if ($RemoveLocal) {
            Test-Path -LiteralPath $tgtFile | Should -BeFalse
        }
        else {
            Get-Content -LiteralPath $tgtFile | Should -Be 'personal edit'
        }
        @(Get-LinkRegistryEntries $reg)[0].CopyFiles[0].Hash | Should -Be $originalHash
    }

    It 'CopyDirectory：拒绝可越界删除的历史相对路径且保持目录内容' {
        $copySource = Join-Path $src '源码 目录'
        New-Item -ItemType Directory -Path $copySource, $tgt | Out-Null
        $outsideName = '外部 [保留].txt'
        $outside = Join-Path $case $outsideName
        $validName = '同目录 [配置].txt'
        $validTarget = Join-Path $tgt $validName
        # 两个根的父目录不同，越界路径在源侧缺失而在目标侧存在。
        Set-Content -LiteralPath $outside -Value 'outside'
        Set-Content -LiteralPath $validTarget -Value 'original'
        Set-Content -LiteralPath (Join-Path $copySource $validName) -Value 'repo edit'
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{
                Target    = $tgt
                Source    = $copySource
                LinkType  = 'CopyDirectory'
                CopyFiles = @(
                    [pscustomobject]@{ Path = $validName; Hash = (Get-FileHash -LiteralPath $validTarget).Hash }
                    [pscustomobject]@{ Path = "../$outsideName"; Hash = (Get-FileHash -LiteralPath $outside).Hash }
                )
            }
        )

        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -Contain $tgt
        Get-Content -LiteralPath $outside | Should -Be 'outside'
        Get-Content -LiteralPath $validTarget | Should -Be 'original'
    }

    It 'CopyDirectory：源未更新时保留已跟踪的本地修改且不告警' {
        $relative = '嵌套 [配置]\本地 文件.txt'
        $srcFile = Join-Path $src $relative
        $tgtFile = Join-Path $tgt $relative
        $null = [IO.Directory]::CreateDirectory((Split-Path $srcFile))
        Set-Content -LiteralPath $srcFile -Value 'original'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript
        $originalHash = (Get-FileHash -LiteralPath $srcFile).Hash
        Set-Content -LiteralPath $tgtFile -Value 'personal edit'

        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -BeNullOrEmpty
        Get-Content -LiteralPath $tgtFile | Should -Be 'personal edit'
        $copyFiles = @(Get-LinkRegistryEntries $reg)[0].CopyFiles
        $copyFiles[0].Path | Should -BeExactly '嵌套 [配置]/本地 文件.txt'
        $copyFiles[0].Hash | Should -Be $originalHash

        Set-Content -LiteralPath $srcFile -Value 'repo edit'
        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -Contain $tgt
        Get-Content -LiteralPath $tgtFile | Should -Be 'personal edit'
    }

    It 'CopyDirectory：目标的嵌套 Junction 不接收源更改' {
        $srcNested = Join-Path $src 'outer\inner'
        $tgtNested = Join-Path $tgt 'outer\inner'
        $personal = Join-Path $case 'personal'
        New-Item -ItemType Directory -Path $srcNested, $personal | Out-Null
        Set-Content -LiteralPath (Join-Path $srcNested 'tracked.txt') -Value 'original'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript

        Remove-Item -LiteralPath (Join-Path $tgtNested 'tracked.txt') -Force
        Remove-Item -LiteralPath $tgtNested -Force
        Set-Content -LiteralPath (Join-Path $personal 'tracked.txt') -Value 'original'
        $null = New-Item -ItemType Junction -Path $tgtNested -Target $personal
        Set-Content -LiteralPath (Join-Path $srcNested 'tracked.txt') -Value 'repo edit'
        Set-Content -LiteralPath (Join-Path $srcNested 'new.txt') -Value 'repo addition'

        $result = & $repairScript -Registry $reg -PassThru

        $result.Unresolved | Should -Contain $tgt
        Get-LinkTargetPath $tgtNested | Should -Be $personal
        Get-Content -LiteralPath (Join-Path $personal 'tracked.txt') | Should -Be 'original'
        Test-Path -LiteralPath (Join-Path $personal 'new.txt') | Should -BeFalse
    }

    It 'CopyDirectory：源的嵌套 Junction 不造成外部复制或删除已登记文件' {
        $srcNested = Join-Path $src 'outer\inner'
        $tgtNested = Join-Path $tgt 'outer\inner'
        $personal = Join-Path $case 'outside-source'
        New-Item -ItemType Directory -Path $srcNested, $personal | Out-Null
        Set-Content -LiteralPath (Join-Path $srcNested 'tracked.txt') -Value 'original'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript

        Remove-Item -LiteralPath (Join-Path $srcNested 'tracked.txt') -Force
        Remove-Item -LiteralPath $srcNested -Force
        Set-Content -LiteralPath (Join-Path $personal 'external.txt') -Value 'outside'
        $null = New-Item -ItemType Junction -Path $srcNested -Target $personal

        & $repairScript -Registry $reg

        Get-Content -LiteralPath (Join-Path $tgtNested 'tracked.txt') | Should -Be 'original'
        Test-Path -LiteralPath (Join-Path $tgtNested 'external.txt') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $personal 'external.txt') | Should -Be 'outside'
    }

    It 'CopyDirectory：目标被降级成文件时清理重建' {
        Set-Content -Path (Join-Path $src 'a.txt') -Value 'a'
        Set-Content -Path $tgt -Value 'i-am-a-file'   # 目标应为目录却是文件

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript

        (Get-Item $tgt -Force).PSIsContainer | Should -BeTrue
        Test-Path (Join-Path $tgt 'a.txt') | Should -BeTrue
    }

    It '未登记目标（注册表为空）永远不碰' {
        $stray = Join-Path $case 'stray.txt'
        Set-Content -Path $stray -Value 'user-own-data'
        # 不写注册表，直接运行修复
        & $repairScript -Registry $reg
        Get-Content $stray | Should -Be 'user-own-data'
    }

    It '未知链接类型不碰目标' {
        Set-Content -Path $tgt -Value 'user-own-data'
        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'FutureType' } -RegistryPath $reg -ScriptPath $repairScript
        Get-Content $tgt | Should -Be 'user-own-data'
    }

    # 回归：调用方 setup.ps1 设了 $ErrorActionPreference=Stop 并以 & 调用修复脚本，
    # 单条链接的任何变更失败必须被逐条 catch 住——否则整轮修复中断、setup 连带失败，
    # 排在后面的条目停留在"半修复"状态。
    It '单条修复失败不中断其余条目，也不向 Stop 语义的调用方抛出' {
        $srcFile = Join-Path $src 'app.toml'
        Set-Content -Path $srcFile -Value 'v3'
        $okTarget = Join-Path $case 'ok\app.toml'
        # 必然失败的条目排在前面：其目标的父目录路径上是个普通文件，建目录与复制都做不到
        $blocker = Join-Path $case 'blocked'
        Set-Content -Path $blocker -Value 'not-a-dir'
        $poisonTarget = Join-Path (Join-Path $blocker 'sub') 'app.toml'

        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $poisonTarget; Source = $srcFile; LinkType = 'Copy' }
            [pscustomobject]@{ Target = $okTarget; Source = $srcFile; LinkType = 'Copy' }
        )

        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'
        try {
            $result = & $repairScript -Registry $reg -PassThru
            $result.Total | Should -Be 2
            $result.Unresolved | Should -Be @($poisonTarget)
        }
        finally {
            $ErrorActionPreference = $prev
        }

        # 失败条目被跳过，其后条目照常修复完成
        Test-Path $okTarget | Should -BeTrue
        Get-Content $okTarget | Should -Be 'v3'
    }
}

Describe 'Repair-ConfigLinks SymbolicLink 分支（按环境二选一断言）' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'TestHelper.ps1')
        $repoRoot = Get-TestRepoRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $repairScript = Join-Path $repoRoot 'Scripts\Repair-ConfigLinks.ps1'
        $root = New-TestTempRoot 'pester-repair-sl'
        $symlinkAvailable = Test-SymlinkAvailable
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'SymbolicLink：目标缺失时重建符号链接（符号链接可用环境）' {
        if (-not $symlinkAvailable) {
            Set-ItResult -Skipped -Because '当前环境无符号链接权限'
            return
        }
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $srcFile = Join-Path $case 'src\app.toml'
        $tgtFile = Join-Path $case 'tgt\app.toml'
        New-Item -ItemType Directory -Path (Split-Path $srcFile) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $tgtFile) -Force | Out-Null
        Set-Content -Path $srcFile -Value 'v2'
        $reg = Join-Path $case 'reg\linked-targets.json'

        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgtFile; Source = $srcFile; LinkType = 'SymbolicLink' }
        )
        & $repairScript -Registry $reg

        (Get-Item $tgtFile -Force).LinkType | Should -Be 'SymbolicLink'
        Get-Content $tgtFile | Should -Be 'v2'
    }

    It 'SymbolicLink：无权限时降级为 Copy 并更新注册表（非管理员环境）' {
        if ($symlinkAvailable) {
            Set-ItResult -Skipped -Because '当前环境有符号链接权限，走不到降级分支'
            return
        }
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $srcFile = Join-Path $case 'src\app.toml'
        $tgtFile = Join-Path $case 'tgt\app.toml'
        New-Item -ItemType Directory -Path (Split-Path $srcFile) -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path $tgtFile) -Force | Out-Null
        Set-Content -Path $srcFile -Value 'v2'
        $reg = Join-Path $case 'reg\linked-targets.json'

        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = $tgtFile; Source = $srcFile; LinkType = 'SymbolicLink' }
        )
        & $repairScript -Registry $reg

        # 降级为普通副本，且注册表类型被改写，下次不再徒劳重试
        (Get-Item $tgtFile -Force).LinkType | Should -BeNullOrEmpty
        Get-Content $tgtFile | Should -Be 'v2'
        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 1
        $entries[0].LinkType | Should -Be 'Copy'
    }
}
