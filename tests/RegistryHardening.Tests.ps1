# Pester 5/6 兼容测试：注册表加固（阶段 2 registry-hardening）
# 覆盖：Restore-LinkRegistry 损坏自愈（.corrupt 备份 + 磁盘证据重建）、
#       命名 Mutex 并发锁（执行/释放/超时降级）、备份目录治理（严格命名 + 保留 3 份）。
# 运行：pwsh -NoProfile -Command "Invoke-Pester tests/RegistryHardening.Tests.ps1"
# 不需要管理员权限：Junction / HardLink 无特权即可创建；符号链接需特权，不测。

Describe 'Restore-LinkRegistry 损坏自愈' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-restore-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '注册表缺失时返回空且不产生任何文件' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        $reg = Join-Path $case 'linked-targets.json'
        $manifest = @(@{ Target = (Join-Path $case 't.txt'); Source = 's.txt' })
        Restore-LinkRegistry -Path $reg -Manifest $manifest -RepoDir $case | Should -Be @()
        Test-Path $reg | Should -BeFalse
    }

    It '正常注册表原样返回、不改写不备份' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        $reg = Join-Path $case 'linked-targets.json'
        Save-LinkRegistryEntries -Path $reg -Entries @(
            [pscustomobject]@{ Target = 'C:\a\t1'; Source = 'C:\r\s1'; LinkType = 'Copy' }
        )
        $before = Get-Content $reg -Raw
        $entries = @(Restore-LinkRegistry -Path $reg -Manifest @(
                @{ Target = 'C:\a\t1'; Source = 's1' }
            ) -RepoDir $case)
        $entries.Count | Should -Be 1
        $entries[0].LinkType | Should -Be 'Copy'
        (Get-Content $reg -Raw) | Should -Be $before
    }

    It '损坏注册表：备份 .corrupt-<时间戳> 并按磁盘证据重建' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $case 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'plugdir') -Force | Out-Null
        Set-Content -Path (Join-Path $repo 'app.toml') -Value 'v1'
        Set-Content -Path (Join-Path $repo 'plain.txt') -Value 'x'
        # 有磁盘证据的：HardLink 文件 + 指向仓库源的 Junction
        $tgtHard = Join-Path $case 'app.toml'
        $null = New-Item -ItemType HardLink -Path $tgtHard -Target (Join-Path $repo 'app.toml')
        $tgtJunc = Join-Path $case 'plugdir'
        $null = New-Item -ItemType Junction -Path $tgtJunc -Target (Join-Path $repo 'plugdir')
        # 无磁盘证据的：普通文件副本（内容相同 ≠ 受管）、与仓库无关的目录
        $tgtPlain = Join-Path $case 'plain.txt'
        Copy-Item (Join-Path $repo 'plain.txt') $tgtPlain
        $tgtForeign = Join-Path $case 'foreign'
        New-Item -ItemType Directory -Path $tgtForeign -Force | Out-Null

        $manifest = @(
            @{ Target = $tgtHard;    Source = 'app.toml' }
            @{ Target = $tgtJunc;    Source = 'plugdir' }
            @{ Target = $tgtPlain;   Source = 'plain.txt' }
            @{ Target = $tgtForeign; Source = 'no-such' }
        )
        $reg = Join-Path $case 'linked-targets.json'
        Set-Content -Path $reg -Value '{ not valid json !!!'

        $entries = @(Restore-LinkRegistry -Path $reg -Manifest $manifest -RepoDir $repo)

        # 只认领有磁盘证据的两条
        $entries.Count | Should -Be 2
        ($entries | Where-Object { $_.Target -eq $tgtHard }).LinkType | Should -Be 'HardLink'
        ($entries | Where-Object { $_.Target -eq $tgtJunc }).LinkType | Should -Be 'Junction'
        # 损坏文件已按严格命名备份
        $corrupt = @(Get-ChildItem $case -Filter 'linked-targets.json.corrupt-*' -File)
        $corrupt.Count | Should -Be 1
        $corrupt[0].Name | Should -Match '^linked-targets\.json\.corrupt-\d{8}-\d{6}$'
        # 注册表已重建为可解析 JSON，且内容与返回值一致
        @(Get-LinkRegistryEntries $reg).Count | Should -Be 2
    }

    It '指向别处的 Junction 不被认领（用户自有配置不碰）' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        $repo = Join-Path $case 'repo'
        New-Item -ItemType Directory -Path (Join-Path $repo 'srcdir') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $case 'otherdir') -Force | Out-Null
        $tgt = Join-Path $case 'tgtdir'
        $null = New-Item -ItemType Junction -Path $tgt -Target (Join-Path $case 'otherdir')
        $reg = Join-Path $case 'linked-targets.json'
        Set-Content -Path $reg -Value '{ broken !!!'

        $entries = @(Restore-LinkRegistry -Path $reg -Manifest @(
                @{ Target = $tgt; Source = 'srcdir' }
            ) -RepoDir $repo)
        $entries | Should -Be @()
    }
}

Describe '__Invoke-WithLinkRegistryLock 并发锁' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
    }

    It '锁内脚本块正常执行并透传返回值' {
        $result = __Invoke-WithLinkRegistryLock -Body { 'ok' }
        $result | Should -Be 'ok'
    }

    It '执行结束后锁已释放（可再次获取）' {
        $null = __Invoke-WithLinkRegistryLock -Body { $null }
        $probe = New-Object System.Threading.Mutex($false, 'Global\pwsh-profile-linkregistry')
        try {
            $probe.WaitOne(0) | Should -BeTrue
        }
        finally {
            $null = $probe.ReleaseMutex()
            $probe.Dispose()
        }
    }

    It '锁被其他线程持有时超时降级：告警并仍执行脚本块' {
        $marker = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-mutex-" + [guid]::NewGuid().ToString('N') + '.flag')
        # 后台 runspace 持锁 3 秒，拿到锁后写标记文件（测试轮询等待，避免竞态）
        $ps = [powershell]::Create()
        $ps.AddScript(@"
`$m = New-Object System.Threading.Mutex(`$false, 'Global\pwsh-profile-linkregistry')
[void]`$m.WaitOne(5000)
Set-Content -Path '$marker' -Value 1
Start-Sleep -Seconds 3
`$m.ReleaseMutex()
`$m.Dispose()
"@).BeginInvoke() | Out-Null
        try {
            $held = $false
            for ($n = 0; $n -lt 50; $n++) {
                if (Test-Path $marker) { $held = $true; break }
                Start-Sleep -Milliseconds 100
            }
            $held | Should -BeTrue   # 后台确认已持锁

            $warnings = @()
            $ran = __Invoke-WithLinkRegistryLock -TimeoutMs 300 -Body { $true } -WarningVariable +warnings
            $ran | Should -BeTrue           # 超时后降级执行，不阻塞主流程
            $warnings.Count | Should -Be 1  # 降级时有告警
        }
        finally {
            $ps.Stop()
            $ps.Dispose()
            Remove-Item $marker -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'Remove-StaleLinkBackup 备份目录治理' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot
        . (Join-Path $repoRoot 'Scripts\LinkRegistry.ps1')
        . (Join-Path $repoRoot 'Scripts\Deploy-ConfigLinks.ps1')
        $root = Join-Path ([System.IO.Path]::GetTempPath()) ("pester-backup-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $root -Force | Out-Null
    }
    AfterAll {
        Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '严格命名的备份超过 3 份时只保留最新 3 份' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        foreach ($stamp in '20260101-000000', '20260102-000000', '20260103-000000', '20260104-000000', '20260105-000000') {
            New-Item -ItemType Directory -Path (Join-Path $case "backup-$stamp") -Force | Out-Null
            Set-Content -Path (Join-Path $case "backup-$stamp\keep.txt") -Value $stamp
        }
        Remove-StaleLinkBackup -BackupRoot $case
        $left = @(Get-ChildItem $case -Filter 'backup-*' -Directory)
        $left.Count | Should -Be 3
        ($left.Name -contains 'backup-20260105-000000') | Should -BeTrue
        ($left.Name -contains 'backup-20260104-000000') | Should -BeTrue
        ($left.Name -contains 'backup-20260103-000000') | Should -BeTrue
    }

    It '命名不完全一致的 backup-* 目录一律不碰' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        # 手工备份 / 旧版产物 / 命名不严格的各种形态（含大小写不同）
        foreach ($name in 'backup-manual', 'backup-20260101-0000', 'backup-20260101-000000-x',
            'backup-20260101_000000', 'Backup-20260101-000000') {
            New-Item -ItemType Directory -Path (Join-Path $case $name) -Force | Out-Null
        }
        Remove-StaleLinkBackup -BackupRoot $case
        @(Get-ChildItem $case -Directory).Count | Should -Be 5
    }

    It '不足 3 份时不清理任何目录' {
        $case = Join-Path $root ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $case -Force | Out-Null
        foreach ($stamp in '20260101-000000', '20260102-000000') {
            New-Item -ItemType Directory -Path (Join-Path $case "backup-$stamp") -Force | Out-Null
        }
        Remove-StaleLinkBackup -BackupRoot $case
        @(Get-ChildItem $case -Filter 'backup-*' -Directory).Count | Should -Be 2
    }
}
