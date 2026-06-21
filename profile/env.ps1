# ==============================================================
# 环境初始化
# ==============================================================

# fnm (Node 版本管理)
fnm env --use-on-cd --shell powershell 2>$null | Out-String | Invoke-Expression

# Scoop（PSCompletions 的 scoop hooks 依赖此变量）
if (-not $env:SCOOP -and (Get-Command scoop -ErrorAction SilentlyContinue)) {
    $env:SCOOP = Split-Path (Split-Path (Get-Command scoop).Source)
}
