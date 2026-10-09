<#
.SYNOPSIS
    校验提交信息格式与注释/文档交叉引用的真实性（规则见 AGENTS.md 规则 6、8）。
.DESCRIPTION
    入口可单用：-MessageFile <path>（commit-msg hook）、-Range <gitrev>（CI / 提交前自查）、
    -CheckRefs（扫描 .ps1/.md 的交叉引用）。都不给时校验 HEAD~1..HEAD 并查引用。
    引用检查宁可漏报不误报：只认「顶层目录名/路径.扩展名」形式的斜杠路径，以及
    文件名紧贴「章节」的写法（如 README「设计说明」）；运行时文件名与隔了汉字的
    写法一律跳过。违规以 throw 报出，hook 因此非零退出。
#>
#Requires -Version 5.1
# 须在帮助块之后：放在首位会让 Get-Help / -? 读不到本块
[CmdletBinding()]
param(
    # git 提交区间，如 origin/main..HEAD
    [string]$Range,
    # 待校验的提交信息文件（hook 传入 .git/COMMIT_EDITMSG）
    [string]$MessageFile,
    # 只做交叉引用检查
    [switch]$CheckRefs,
    # 仓库根目录，默认取本脚本上级
    [string]$RepoRoot = (Split-Path $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

$validTypes     = @('feat', 'fix', 'docs', 'refactor', 'perf', 'test', 'chore', 'ci', 'build', 'revert')
$subjectMaxWidth = 60
$bodyMaxWidth    = 72

# 全角/CJK 按 2 列计宽：git log --oneline 的截断发生在显示列宽上而非字符数，
# 中文 subject 60 字实际占 120 列，必须按列宽判。这是 Unicode East Asian Wide
# 的近似分类（不含 Ambiguous 类，如 —— 与 ° 按 1 列算）。
function __Get-DisplayWidth {
    param([string]$Text)
    $width = 0
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        $wide = ($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE6F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6)
        if ($wide) { $width += 2 } else { $width += 1 }
    }
    return $width
}

# 单条提交信息 → 问题数组（空数组 = 合格）
function __Test-CommitMessage {
    param(
        [string]$Message,
        [string]$Label = '提交信息'
    )
    $problems = @()
    # hook 收到的是完整模板：丢弃 # 注释行与 diff 行
    $lines = @($Message -split "\r?\n" | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^diff --git' })
    while ($lines.Count -gt 0 -and $lines[0] -match '^\s*$') {
        $lines = @($lines | Select-Object -Skip 1)
    }
    if ($lines.Count -eq 0) {
        return @("$Label：提交信息为空")
    }
    $subject = $lines[0].Trim()

    # merge / revert 沿用 git 默认文案（AGENTS.md 规则 8），不套格式
    if ($subject -match '^(Merge|Revert)\s') { return @() }

    if ($subject -notmatch '^(?<t>[a-zA-Z]+)(\((?<s>[a-z0-9._/-]+)\))?!?: (?<rest>.+)$') {
        # 单独识别中文 type，给出可直接照抄的改法（历史上 13 种前缀混用主要源于此）
        if ($subject -match '^(?<cn>[^:：()]{1,12})[：:]') {
            $cn = $Matches['cn']
            if ($cn -match '[\u4e00-\u9fff]') {
                $problems += "$Label：中文 type「${cn}」不合规范——改用英文 type（$($validTypes -join ' / ')），受影响的模块写进 scope，如 fix(profile): 修复 xxx"
                return $problems
            }
        }
        $problems += "$Label：subject 缺合法前缀，应为 <$type>(<scope>): <描述>，type ∈ $($validTypes -join ' / ')"
        return $problems
    }
    $type = $Matches['t']
    $desc = $Matches['rest']
    if ($validTypes -notcontains $type) {
        $problems += "$Label：type「$type」不在允许清单内（$($validTypes -join ' / ')）"
    }
    if ($desc -match '[。；;.]\s*$') {
        $problems += "$Label：subject 结尾不要加句号/分号"
    }
    if ($desc -match '——|；') {
        $problems += "$Label：subject 不要用 —— / ； 塞多段内容，原因与影响面写进正文"
    }
    $sw = __Get-DisplayWidth $subject
    if ($sw -gt $subjectMaxWidth) {
        $problems += "$Label：subject 宽 ${sw} 列（上限 $subjectMaxWidth），git log --oneline 会被截断"
    }

    # subject 与正文之间必须空一行（git 的 --format=%s/%b 切分依赖它）
    if ($lines.Count -gt 1 -and $lines[1] -match '\S') {
        $problems += "$Label：subject 与正文之间需要空行"
    }
    for ($i = 2; $i -lt $lines.Count; $i++) {
        $bw = __Get-DisplayWidth $lines[$i]
        if ($bw -gt $bodyMaxWidth) {
            $problems += "$Label：正文第 $($i - 1) 行宽 ${bw} 列（上限 $bodyMaxWidth）——「$($lines[$i].Substring(0, [Math]::Min(24, $lines[$i].Length)))…」"
        }
    }
    return $problems
}

# 把注释里的引用 token 解析成仓库内真实路径；解析不到返回 $null（不当作引用）
function __Resolve-RepoPath {
    param(
        [string]$Token,
        [string]$FromDir,
        [string]$RepoRoot
    )
    $t = $Token -replace '^\.\/', '' -replace '^\.\.\/', ''
    $candidates = @()
    if ($t -match '\.(ps1|md|toml|yml|json|lua)$') {
        $candidates += (Join-Path $RepoRoot $t)
        $candidates += (Join-Path $FromDir $t)
    } else {
        # 无扩展名的 README / AGENTS / TODO 指代仓库根目录同名 .md
        $candidates += (Join-Path $RepoRoot "$t.md")
    }
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c -PathType Leaf) { return (Resolve-Path -LiteralPath $c).Path }
    }
    return $null
}

function __Test-ReferenceIntegrity {
    param([string]$RepoRoot)

    $problems = @()
    $topDirs = @()
    foreach ($d in (Get-ChildItem -LiteralPath $RepoRoot -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -in '.git', 'node_modules') { continue }
        $topDirs += [regex]::Escape($d.Name)
    }
    $pathPattern = '(?<![\w./-])(?:\.\./|\./)?(?:' + ($topDirs -join '|') + ')/[\w./-]+\.(?:ps1|md|toml|yml|json|lua)'
    $sectionPattern = '([A-Za-z0-9_./-]{2,})「([^」]{1,24})」'

    # 只扫 git 跟踪的 .ps1/.md：Modules/ 下的第三方模块不入库，扫它是噪声
    $files = @(& git -C $RepoRoot ls-files -- '*.ps1' '*.md') | Where-Object { $_ }
    foreach ($rel in $files) {
        $full = Join-Path $RepoRoot $rel
        if ((Split-Path $full -Leaf) -eq 'Check-CommitMsg.ps1') { continue }
        $text = Get-Content -LiteralPath $full -Raw -ErrorAction SilentlyContinue
        if (-not $text) { continue }
        $dir = Split-Path $full -Parent

        # 1. 斜杠路径必须存在。开头的 (?<![\w./-]) 是必需的：README 的 bootstrap
        #    下载 URL 里有 pwsh-profile/main/bootstrap.ps1，不锚定就会把 URL 片段
        #    当成仓库路径 profile/main/bootstrap.ps1 报成失效引用
        foreach ($m in [regex]::Matches($text, $pathPattern)) {
            $p = $m.Value
            $candidate = Join-Path $RepoRoot $p
            if (-not (Test-Path -LiteralPath $candidate)) {
                $ln = ($text.Substring(0, $m.Index) -split "\r?\n").Count
                $problems += "$rel 第 $ln 行：引用的文件不存在——$p"
            }
        }
        # 2. `X.md「章节」` 里的章节必须是该文件真实标题
        foreach ($m in [regex]::Matches($text, $sectionPattern)) {
            $token = $m.Groups[1].Value
            $section = $m.Groups[2].Value
            $target = __Resolve-RepoPath -Token $token -FromDir $dir -RepoRoot $RepoRoot
            if (-not $target) { continue }
            if ($target -notmatch '\.md$') { continue }
            $targetText = Get-Content -LiteralPath $target -Raw
            if ($targetText -notmatch ('(?m)^[^\S\r\n]{0,3}#{1,6}[^\r\n]*' + [regex]::Escape($section))) {
                $ln = ($text.Substring(0, $m.Index) -split "\r?\n").Count
                $problems += "$rel 第 $ln 行：引用 $token「$section」，但目标文件里没有这个标题（文档重构后未回改注释）"
            }
        }
    }
    return $problems
}

function __Write-ProblemReport {
    param([string[]]$Problems, [string]$Header)
    $lines = @($Problems)
    if ($lines.Count -eq 0) { return }
    Write-Host $Header -ForegroundColor Red
    foreach ($p in $lines) {
        Write-Host "  - $p" -ForegroundColor Red
        if ($env:GITHUB_ACTIONS -eq 'true') { Write-Host "::error::$p" }
    }
    throw "$Header（$($lines.Count) 处）"
}

# ================= 执行 =================
if (-not $Range -and -not $MessageFile -and -not $CheckRefs) {
    $Range = 'HEAD~1..HEAD'
    $CheckRefs = $true
}

$allProblems = @()

if ($MessageFile) {
    if (-not (Test-Path -LiteralPath $MessageFile)) { throw "提交信息文件不存在: $MessageFile" }
    $msg = Get-Content -LiteralPath $MessageFile -Raw
    $allProblems += __Test-CommitMessage -Message $msg -Label '本次提交'
}

if ($Range) {
    $revs = @(& git -C $RepoRoot rev-list --no-merges $Range 2>$null) | Where-Object { $_ }
    if ($LASTEXITCODE -ne 0) { throw "无法解析提交区间 $Range（浅克隆？CI 需 fetch-depth: 0）" }
    foreach ($sha in $revs) {
        $short = (& git -C $RepoRoot log -1 --format=%h $sha)
        $body = @(& git -C $RepoRoot log -1 --format=%B $sha) -join "`n"
        $allProblems += __Test-CommitMessage -Message $body -Label "提交 $short"
    }
}

if ($CheckRefs) {
    $allProblems += __Test-ReferenceIntegrity -RepoRoot $RepoRoot
}

if (@($allProblems).Count -eq 0) {
    $scope = '提交信息'
    if ($Range -and $CheckRefs) { $scope = "提交区间 $Range + 交叉引用" }
    elseif ($Range) { $scope = "提交区间 $Range" }
    elseif ($CheckRefs) { $scope = '交叉引用' }
    Write-Host "规范校验 OK：$scope" -ForegroundColor Green
}
else {
    __Write-ProblemReport -Problems $allProblems -Header '规范校验未通过（AGENTS.md 规则 6 / 7 / 8）'
}
