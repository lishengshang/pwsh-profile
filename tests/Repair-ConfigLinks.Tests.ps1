# Pester 5/6 兼容测试：链接修复（Scripts/Repair-ConfigLinks.ps1）
# 覆盖五类链接的修复/跳过/降级语义，以及「未登记目标永远不碰」的边界。
# 说明 1：SymbolicLink 的建链需要管理员权限或开发者模式——CI（管理员）走真实
#         重建分支，本地非管理员走降级分支，两组分支都断言，保证两边都绿。
# 说明 2：Pester 6 中每个块运行在独立 script scope，$script: 变量不再跨块共享，
#         因此全部使用普通变量（动态作用域在 Pester 5/6 均成立）。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/Repair-ConfigLinks.Tests.ps1"

Describe 'Repair-ConfigLinks 五类链接修复' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $repairScript = Join-Path $repoRoot 'Scripts\Repair-ConfigLinks.ps1'
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-repair-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

        # 按登记类型写一条注册表记录并运行修复（显式传参，不依赖跨块作用域）
        function Invoke-TestRepair {
            param([hashtable]$Entry, [string]$RegistryPath, [string]$ScriptPath)
            Save-LinkRegistryEntries -Path $RegistryPath -Entries @(
                [pscustomobject]@{
                    Target   = $Entry.Target
                    Source   = $Entry.Source
                    LinkType = $Entry.LinkType
                }
            )
            & $ScriptPath -Registry $RegistryPath
        }

        # 取链接的第一目标路径（5.1 下 .Target 是 String[]）
        function Get-LinkTargetPath {
            param([string]$Path)
            $prop = @((Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue).Target) |
                Select-Object -First 1
            if (-not $prop) { return $null }
            return ([System.IO.Path]::GetFullPath([string]$prop)).TrimEnd('\')
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

    It 'CopyDirectory：robocopy /MIR 镜像同步' {
        Set-Content -Path (Join-Path $src 'a.txt') -Value 'a'
        Set-Content -Path (Join-Path $src 'b.txt') -Value 'b'
        Copy-Item -Path $src -Destination $tgt -Recurse
        # 目标侧漂移：b.txt 被删、多出 extra.txt
        Remove-Item (Join-Path $tgt 'b.txt') -Force
        Set-Content -Path (Join-Path $tgt 'extra.txt') -Value 'stale'

        Invoke-TestRepair @{ Target = $tgt; Source = $src; LinkType = 'CopyDirectory' } -RegistryPath $reg -ScriptPath $repairScript

        Test-Path (Join-Path $tgt 'b.txt') | Should -BeTrue       # 源有目标无 → 补回
        Test-Path (Join-Path $tgt 'extra.txt') | Should -BeFalse  # 目标有源无 → 清除
        Test-Path (Join-Path $tgt 'a.txt') | Should -BeTrue
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
}

Describe 'Repair-ConfigLinks SymbolicLink 分支（按环境二选一断言）' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $repairScript = Join-Path $repoRoot 'Scripts\Repair-ConfigLinks.ps1'
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-repair-sl-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $symlinkAvailable = Test-SymlinkAvailable
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'SymbolicLink：目标缺失时重建符号链接（符号链接可用环境）' {
        if (-not $symlinkAvailable) {
            Write-Host '跳过：当前环境无符号链接权限'
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
            Write-Host '跳过：当前环境有符号链接权限，走不到降级分支'
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
