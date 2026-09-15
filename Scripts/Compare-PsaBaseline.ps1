#Requires -Version 5.1
<#
.SYNOPSIS
    PSScriptAnalyzer 新增违规门禁：与基线提交比对，仅新增违规失败。
.DESCRIPTION
    阶段 1「ci/psa-baseline」的实现。SSA 没有原生 baseline 参数，本脚本以
    基线提交（BASE_SHA）的文件内容作为快照来源：对 git diff 变更过的 .ps1
    逐个分析「当前版本」与「基线版本」的违规（按规则计数），任一规则的
    违规数增加即判失败。
    - 存量违规不阻塞：基线提交里已有的违规全部放行，避免一次性修几百处
      风格问题；清理存量后增量自然为负，永远只拦新增。
    - 无需入库快照文件：快照即基线提交的代码状态，零维护、不会过期。
    - CI（仅 pwsh 矩阵作业）：PR 以目标分支 tip 为基线、push 以
      github.event.before 为基线；无基线（首次推送）时放行并提示。
    豁免规则（profile 既定风格，见 AGENTS.md）：Write-Host / 短别名 /
    全局变量 / 未批准动词 / ShouldProcess。
#>
param(
    # 基线提交 SHA（CI 传入 github.event.pull_request.base.sha 或 event.before）
    [Parameter(Mandatory)][string]$BaseSha,
    # 仓库根目录（默认取脚本上级）
    [string]$RepoRoot = (Split-Path $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module PSScriptAnalyzer -ListAvailable)) {
    Install-Module PSScriptAnalyzer -Force -Scope CurrentUser
}
Import-Module PSScriptAnalyzer

# 项目约定豁免（新增规则豁免需同步更新此清单与 CI 日志说明）
$excludedRules = @(
    'PSAvoidUsingWriteHost',
    'PSAvoidUsingCmdletAliases',
    'PSAvoidGlobalVars',
    'PSUseShouldProcessForStateChangingFunctions',
    'PSUseApprovedVerbs'
)

function Get-ViolationCountByRule {
    param([string]$Path)
    $records = Invoke-ScriptAnalyzer -Path $Path -ExcludeRule $excludedRules -ErrorAction SilentlyContinue
    $counts = @{}
    foreach ($r in @($records)) {
        if (-not $r.RuleName) { continue }
        if (-not $counts.ContainsKey($r.RuleName)) { $counts[$r.RuleName] = 0 }
        $counts[$r.RuleName]++
    }
    return $counts
}

# 变更过的 .ps1（排除第三方 Modules/；已删除文件不参与比对）
$changed = @(git diff --name-only "$BaseSha" HEAD -- '*.ps1' |
    Where-Object { $_ -and $_ -notmatch '^Modules/' })
if (-not $changed.Count) {
    Write-Host 'PSA 基线比对：无 .ps1 变更，跳过'
    exit 0
}

$newTotal = 0
foreach ($rel in $changed) {
    $abs = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $abs)) { continue }

    $current = Get-ViolationCountByRule -Path $abs

    # 取基线提交里的文件版本到临时文件（保留原文件名以辅助解析器）
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("psa-base-" + [guid]::NewGuid().ToString('N') + '-' + (Split-Path $rel -Leaf))
    $base = @{}
    # ls-tree 命中时输出路径（真值），未命中时无输出——cat-file -e 成功时无输出，用输出做条件恒为假
    if (git ls-tree --name-only "$BaseSha" -- "$rel") {
        git show "$($BaseSha):$rel" | Out-File -FilePath $tmp -Encoding utf8
        $base = Get-ViolationCountByRule -Path $tmp
    }
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue

    foreach ($rule in $current.Keys) {
        $before = 0
        if ($base.ContainsKey($rule)) { $before = $base[$rule] }
        if ($current[$rule] -gt $before) {
            $delta = $current[$rule] - $before
            Write-Host ("新增违规: {0} [{1}] +{2}" -f $rel, $rule, $delta)
            $newTotal += $delta
        }
    }
}

if ($newTotal -gt 0) {
    throw ("PSScriptAnalyzer 门禁：检测到 {0} 处新增违规（详见上方清单）。请修复，或确认属于项目既定风格后加入豁免规则清单。" -f $newTotal)
}
Write-Host ("PSA 基线比对通过：{0} 个变更文件无新增违规" -f $changed.Count)
