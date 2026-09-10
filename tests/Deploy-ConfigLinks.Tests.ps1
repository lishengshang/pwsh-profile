# Pester 5/6 兼容测试：配置链接部署（Scripts/Deploy-ConfigLinks.ps1）
# 用 -NoSymlink 注入强制走回退链（Junction / HardLink / Copy），
# 覆盖非管理员环境的部署路径，因此不需要管理员权限。
# 注 1：Copy 最终回退需要跨卷场景才能强制触发，单卷测试环境无法覆盖，
#       Copy/CopyDirectory 的刷新逻辑由 Repair-ConfigLinks.Tests.ps1 验证。
# 注 2：Pester 6 中每个块运行在独立 script scope，$script: 变量不再跨块共享，
#       因此全部使用普通变量（动态作用域在 Pester 5/6 均成立）。

Describe 'Invoke-ConfigLinkDeployment' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-deploy-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null

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
        # 每个用例独立的 case 目录：repo（仓库源）/ targets（部署目标）/ backups / reg.json
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $case 'repo'
        $targets = Join-Path $case 'targets'
        New-Item -ItemType Directory -Path $repo -Force | Out-Null
        New-Item -ItemType Directory -Path $targets -Force | Out-Null
        $reg = Join-Path $case 'reg\linked-targets.json'
        $backupRoot = Join-Path $case 'backups'

        # 造一个标准源：文件 app.toml + 目录 plugdir
        Set-Content -Path (Join-Path $repo 'app.toml') -Value 'v1'
        New-Item -ItemType Directory -Path (Join-Path $repo 'plugdir') -Force | Out-Null
        Set-Content -Path (Join-Path $repo 'plugdir\init.lua') -Value 'nvim'
        $items = @(
            @{ Source = 'app.toml'; Target = (Join-Path $targets 'app.toml') }
            @{ Source = 'plugdir';  Target = (Join-Path $targets 'plugdir') }
        )
    }

    It '首次部署：文件走 HardLink、目录走 Junction，并登记注册表' {
        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeFalse
        $result.CopyDeployed | Should -BeFalse

        $tgtFile = Get-Item (Join-Path $targets 'app.toml') -Force
        $tgtFile.LinkType | Should -Be 'HardLink'
        Get-Content (Join-Path $targets 'app.toml') | Should -Be 'v1'

        $tgtDir = Get-Item (Join-Path $targets 'plugdir') -Force
        $tgtDir.LinkType | Should -Be 'Junction'
        Get-Content (Join-Path $targets 'plugdir\init.lua') | Should -Be 'nvim'

        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 2
        ($entries | Where-Object { $_.LinkType -eq 'HardLink' }).Count | Should -Be 1
        ($entries | Where-Object { $_.LinkType -eq 'Junction' }).Count | Should -Be 1
    }

    It '重复部署幂等：已受管目标全部跳过，注册表不增长' {
        $null = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $countBefore = @(Get-LinkRegistryEntries $reg).Count

        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeFalse
        @(Get-LinkRegistryEntries $reg).Count | Should -Be $countBefore
        (Get-Item (Join-Path $targets 'app.toml') -Force).LinkType | Should -Be 'HardLink'
    }

    It '注册表丢失时重跑补登记而不重建链接' {
        $null = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $creationBefore = (Get-Item (Join-Path $targets 'app.toml') -Force).CreationTime
        Remove-Item $reg -Force

        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeFalse
        # HardLink/Junction 由 Get-ManagedLinkState 按磁盘关系识别 → 跳过重建
        $entries = @(Get-LinkRegistryEntries $reg)
        $entries.Count | Should -Be 2
        (Get-Item (Join-Path $targets 'app.toml') -Force).CreationTime | Should -Be $creationBefore
    }

    It '目标为用户已有文件时先备份再接管' {
        $tgtPath = Join-Path $targets 'app.toml'
        Set-Content -Path $tgtPath -Value 'user-data'

        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeTrue

        # 备份目录里保留了用户原文件
        $backupDirs = @(Get-ChildItem $backupRoot -Filter 'backup-*' -Directory)
        $backupDirs.Count | Should -Be 1
        Get-Content (Join-Path $backupDirs[0].FullName 'app.toml') | Should -Be 'user-data'
        # 目标接管为仓库内容
        Get-Content $tgtPath | Should -Be 'v1'
        (Get-Item $tgtPath -Force).LinkType | Should -Be 'HardLink'
    }

    It '断链目标被清理后重建' {
        # 构造断链：junction 指向随后被删除的目录
        $ghost = Join-Path $case 'ghost'
        New-Item -ItemType Directory -Path $ghost -Force | Out-Null
        $dangling = Join-Path $targets 'plugdir'
        $null = New-Item -ItemType Junction -Path $dangling -Target $ghost
        Remove-Item $ghost -Recurse -Force
        # 断链的 Test-Path 表现因 PS 版本而异（5.1 False / 7.x 可能为 True），
        # 用「链接对象仍在 + 链接目标已不存在」做与版本无关的前置确认
        (Get-Item -LiteralPath $dangling -Force).LinkType | Should -Be 'Junction'
        Test-Path -LiteralPath (Get-LinkTargetPath $dangling) | Should -BeFalse

        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeFalse   # 断链不含用户数据，不备份
        Test-Path $dangling | Should -BeTrue
        (Get-Item $dangling -Force).LinkType | Should -Be 'Junction'
        Get-Content (Join-Path $dangling 'init.lua') | Should -Be 'nvim'
    }

    It 'SkipIfExists 目标存在时不接管也不登记' {
        $tgtPath = Join-Path $targets 'app.toml'
        Set-Content -Path $tgtPath -Value 'user-own-config'
        $items = @(
            @{ Source = 'app.toml'; Target = $tgtPath; SkipIfExists = $true }
        )
        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        $result.BackupCreated | Should -BeFalse
        Get-Content $tgtPath | Should -Be 'user-own-config'
        Get-LinkRegistryEntries $reg | Should -Be @()
    }

    It '源不存在时跳过该条目' {
        $items = @(
            @{ Source = 'no-such-file.toml'; Target = (Join-Path $targets 'no-such-file.toml') }
        )
        $result = Invoke-ConfigLinkDeployment -Items $items -RepoDir $repo `
            -RegistryPath $reg -BackupRoot $backupRoot -NoSymlink
        Test-Path (Join-Path $targets 'no-such-file.toml') | Should -BeFalse
        Get-LinkRegistryEntries $reg | Should -Be @()
    }
}
