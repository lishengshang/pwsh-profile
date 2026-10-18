<#
.SYNOPSIS
    文档防漂移校验：代码 ⊆ 文档的单向覆盖检查（TODO 阶段 3）。
.DESCRIPTION
    AST 提取 profile/aliases.ps1 的函数与别名、setup.ps1 的 $wingetTools 清单，
    校验三类单向覆盖及文档结构（文档多余的条目不算漂移，允许放说明性内容）：
      1. 别名与未被别名代表的函数 → docs/usage.md
      2. winget 工具 Name 与 Component → docs/reference.md
      3. README「快速上手」中出现的 profile 命令 → usage.md 已收录（子集关系）
      4. docs 下 Markdown 的单一一级标题、本地链接与标题锚点
    被 Set-Alias/New-Alias 映射的函数由别名代表接受检查（用户可见名是别名），
    __ 前缀的 profile 私有函数不参与校验。
    匹配为词边界 + 忽略大小写；已知局限：短名可能被更长的点号名（.. / ....）
    覆盖判定，实际文档三者相邻收录，影响可忽略。
    CI 在 pwsh 作业运行；本地可随时手动执行。
.PARAMETER RepoRoot
    仓库根目录（默认取脚本上级；测试时指向临时仓库树）。
.NOTES
    退出码：0 = 检查通过；1 = 存在漂移或规范问题（清单随异常消息输出）。
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RepoRoot
)

# 5.1 以 -File 启动时，参数默认值求值阶段的 PSScriptRoot 可能尚未初始化。
if (-not $RepoRoot) { $RepoRoot = Split-Path $PSScriptRoot }

# ===== AST 提取 =====

# 提取 AST 元素的静态字面量文本；非字符串字面量（变量等动态形态）超出静态
# 分析能力，返回 $null 由调用方决定跳过——宁漏检动态形态也不误报
function __ArgText {
    param($Element)
    if ($Element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return [string]$Element.Value
    }
    return $null
}

# aliases.ps1 → 用户可见命令清单。函数名（排除 __ 前缀私有）与别名分别收集：
# 别名必须出现在 usage.md（用户实际敲的名字）；被别名代表的函数由别名代表，
# 不单独要求文档（ps-lock/Get-PublicIP 等实现名不该强迫用户文档收录）。
function Get-ProfileCommand {
    param([Parameter(Mandatory)][string]$Path)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $Path), [ref]$null, [ref]$errors)
    if ($errors) {
        throw "解析失败，无法提取命令清单: $Path -> $($errors[0].Message)"
    }
    $functions = @()
    foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        if ($f.Name -notlike '__*') { $functions += $f.Name }
    }
    $aliases = @()
    $aliasTargets = @()
    foreach ($c in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)) {
        if ($c.GetCommandName() -notin 'Set-Alias', 'New-Alias') { continue }
        # 兼容命名与位置两种传参：-Name X -Value Y [其他开关] 与 X Y
        $named = @{}
        $positional = @()
        $pending = $null
        foreach ($el in $c.CommandElements | Select-Object -Skip 1) {
            if ($el -is [System.Management.Automation.Language.CommandParameterAst]) {
                if ($el.Argument) { $named[$el.ParameterName] = __ArgText $el.Argument }
                else { $pending = $el.ParameterName }
                continue
            }
            if ($pending) {
                $named[$pending] = __ArgText $el
                $pending = $null
                continue
            }
            $positional += __ArgText $el
        }
        $aliasName = $named['Name']
        if (-not $aliasName) { $aliasName = $positional[0] }
        $targetName = $named['Value']
        if (-not $targetName) { $targetName = $positional[1] }
        # 名称解析不出来（动态值）无法静态校验，跳过该条
        if (-not $aliasName) { continue }
        $aliases += $aliasName
        if ($targetName) { $aliasTargets += $targetName }
    }
    [pscustomobject]@{
        Functions    = @($functions)
        Aliases      = @($aliases)
        AliasTargets = @($aliasTargets)
    }
}

# setup.ps1 → $wingetTools 清单（Name/Component）。只在该赋值语句右侧范围内
# 找哈希表，避免误吃 setup 其他位置的哈希表字面量；找不到赋值即报错——
# 清单被改名/搬走时门禁必须显式失败而不是静默放过
function Get-SetupTool {
    param([Parameter(Mandatory)][string]$Path)
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $Path), [ref]$null, [ref]$errors)
    if ($errors) {
        throw "解析失败，无法提取工具清单: $Path -> $($errors[0].Message)"
    }
    $assign = @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true) |
        Where-Object {
            $_.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $_.Left.VariablePath.UserPath -eq 'wingetTools'
        })
    if (-not $assign) { throw "setup.ps1 未找到 `$wingetTools 清单定义: $Path" }
    $tools = @()
    foreach ($hash in $assign[-1].Right.FindAll({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $true)) {
        $entry = @{}
        foreach ($kv in $hash.KeyValuePairs) {
            $key = $kv.Item1.Value
            $val = __ArgText $kv.Item2
            if (-not $val -and $kv.Item2 -is [System.Management.Automation.Language.PipelineAst]) {
                $val = __ArgText $kv.Item2.PipelineElements[0].Expression
            }
            if ($key) { $entry[$key] = $val }
        }
        if ($entry['Name']) {
            $tools += [pscustomobject]@{ Name = $entry['Name']; Component = $entry['Component'] }
        }
    }
    if (-not $tools) { throw "setup.ps1 的 `$wingetTools 清单为空或无法静态提取: $Path" }
    return $tools
}

# ===== 覆盖匹配 =====

# 词边界匹配：命令名前后不得是字母/数字/连字符，避免 gs 误匹配 gsettings、
# lt 误匹配 llt 之类的假覆盖；忽略大小写（PowerShell 命令名不区分大小写，
# 文档里 Yazi/yazi 这类大小写差异不算漂移）
function Test-DocsWord {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Word
    )
    $pattern = '(?<![A-Za-z0-9-])' + [regex]::Escape($Word) + '(?![A-Za-z0-9-])'
    return [regex]::IsMatch($Text, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

# ===== 文档结构与链接 =====

# 代码示例里的注释与链接不是文档结构，检查前先排除围栏代码块。
function Get-DocsProse {
    param([string]$Text)
    return [regex]::Replace($Text, '(?ms)^ {0,3}(`{3,}|~{3,})[^\r\n]*\r?\n.*?^ {0,3}\1[ \t]*(?:\r?\n|$)', '')
}

function Get-DocsHeadingAnchor {
    param([string]$Text)
    $seen = @{}
    foreach ($heading in [regex]::Matches((Get-DocsProse $Text), '(?m)^ {0,3}#{1,6}[ \t]+([^\r\n]+)')) {
        $anchor = ($heading.Groups[1].Value.Trim() -replace '[^\p{L}\p{N}_\-\s]', '').ToLowerInvariant() -replace '\s', '-'
        if ($seen.ContainsKey($anchor)) {
            $seen[$anchor]++
            "$anchor-$($seen[$anchor])"
        }
        else {
            $seen[$anchor] = 0
            $anchor
        }
    }
}

function Get-DocsIssue {
    param([Parameter(Mandatory)][string]$Root)
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'docs') -Filter '*.md' -File -Recurse) {
        $prose = Get-DocsProse (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
        if ([regex]::Matches($prose, '(?m)^ {0,3}#[ \t]+').Count -ne 1) {
            "$($file.Name) 必须且只能有一个一级标题"
        }
        foreach ($link in [regex]::Matches($prose, '(?<!!)\[[^\]\r\n]+\]\(([^)\s]+)\)')) {
            $target = $link.Groups[1].Value
            # 外部 URL 不在本地门禁联网验证，避免网络波动影响文档检查。
            if ($target -match '^[A-Za-z][A-Za-z0-9+.-]*:' -and $target -notmatch '^[A-Za-z]:') { continue }
            $parts = $target -split '#', 2
            $relative = [Uri]::UnescapeDataString($parts[0])
            if ([IO.Path]::IsPathRooted($relative)) {
                "$($file.Name) 本地链接必须使用相对路径: $target"
                continue
            }
            $local = $file.FullName
            if ($relative) { $local = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $relative)) }
            if (-not (Test-Path -LiteralPath $local -PathType Leaf)) {
                "$($file.Name) 链接目标不存在: $target"
                continue
            }
            if ($parts.Count -gt 1 -and $parts[1] -and $local -match '\.md$') {
                $anchors = @(Get-DocsHeadingAnchor (Get-Content -LiteralPath $local -Raw -Encoding UTF8))
                if ([Uri]::UnescapeDataString($parts[1]) -cnotin $anchors) {
                    "$($file.Name) 标题锚点不存在: $target"
                }
            }
        }
    }
}

# ===== 主流程 =====

$aliasesPath = Join-Path $RepoRoot 'profile\aliases.ps1'
$setupPath   = Join-Path $RepoRoot 'setup.ps1'
$usagePath   = Join-Path $RepoRoot 'docs\usage.md'
$refPath     = Join-Path $RepoRoot 'docs\reference.md'
$readmePath  = Join-Path $RepoRoot 'README.md'
foreach ($p in $aliasesPath, $setupPath, $usagePath, $refPath, $readmePath) {
    if (-not (Test-Path $p)) { throw "被检文件不存在: $p" }
}

$usage     = Get-Content $usagePath -Raw -Encoding UTF8
$reference = Get-Content $refPath -Raw -Encoding UTF8
$cmd       = Get-ProfileCommand $aliasesPath
$tools     = Get-SetupTool $setupPath

$missing = @(Get-DocsIssue -Root $RepoRoot)

# 1. 别名必须收录（用户实际敲的名字）
foreach ($a in $cmd.Aliases) {
    if (-not (Test-DocsWord $usage $a)) { $missing += "usage.md 缺少别名: $a" }
}
# 2. 未被别名代表的函数必须收录（实现名有别名暴露给用户时由别名代表）
foreach ($f in $cmd.Functions) {
    if ($f -in $cmd.AliasTargets) { continue }
    if (-not (Test-DocsWord $usage $f)) { $missing += "usage.md 缺少函数: $f" }
}
# 3. winget 工具名与组件必须收录进 reference.md
foreach ($t in $tools) {
    if (-not (Test-DocsWord $reference $t.Name)) { $missing += "reference.md 缺少工具: $($t.Name)" }
    if ($t.Component -and -not (Test-DocsWord $reference $t.Component)) {
        $missing += "reference.md 缺少组件: $($t.Component)"
    }
}
# 4. README「快速上手」中的 profile 命令必须是 usage.md 已收录命令的子集
#    （AGENTS.md：README 只保留高频子集）；非 profile 命令（git push、z 等
#    定义在 aliases.ps1 之外的）不在静态提取范围，跳过
$readme = Get-Content $readmePath -Raw -Encoding UTF8
if ($readme -match '(?s)## 快速上手\r?\n(.*?)(?=\r?\n## |\z)') {
    $checkedNames = @($cmd.Functions) + @($cmd.Aliases)
    foreach ($span in [regex]::Matches($Matches[1], '`([^`]+)`')) {
        $token = ($span.Groups[1].Value -split '\s+')[0]
        if (-not $token -or $token -match '[/\\]') { continue }
        if ($token -in $checkedNames -and -not (Test-DocsWord $usage $token)) {
            $missing += "README 快速上手引用了 usage.md 未收录的命令: $token"
        }
    }
}
else {
    throw 'README.md 未找到「## 快速上手」小节'
}

if ($missing.Count) {
    foreach ($m in $missing) { Write-Host "文档漂移: $m" -ForegroundColor Yellow }
    throw "文档防漂移校验失败：$($missing.Count) 处覆盖或规范问题——$($missing -join '；')"
}
Write-Host ("文档防漂移校验通过：{0} 个命令（函数 {1} + 别名 {2}）、{3} 个 winget 工具均有文档覆盖" -f
    (@($cmd.Functions).Count + @($cmd.Aliases).Count), @($cmd.Functions).Count, @($cmd.Aliases).Count, @($tools).Count)
