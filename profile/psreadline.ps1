# ==============================================================
# PSReadLine 配置
# ==============================================================
# 非交互环境（输出被重定向）下跳过，避免 PSReadLine 抛出 VT 相关错误；
# 宿主未加载 PSReadLine（精简宿主/无控制台）时同样跳过——只探测
# Set-PSReadLineOption 一个命令即可（同模块导出，KeyHandler 必然同在）。
if ([Console]::IsOutputRedirected) { return }
$psrlOption = Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue
if (-not $psrlOption) { return }

# 各版本均支持的核心参数
Set-PSReadLineOption `
    -HistoryNoDuplicates `
    -MaximumHistoryCount 10000 `
    -Colors @{
        Command                = '#268BD2'
        Member                 = '#268BD2'
        Operator               = '#859900'
        Number                 = '#D33682'
        Type                   = '#B58900'
        Variable               = '#CB4B16'
        Parameter              = '#657B83'
        Default                = '#839496'
        InlinePrediction       = '#93A1A1'
        ListPrediction         = '#2AA198'
        ListPredictionSelected = '#073642'
    }

# 能力检测：旧版 PSReadLine 不认识的新参数逐项降级，
# 避免一个参数错误中断整个 profile 加载链
if ($psrlOption.Parameters.ContainsKey('PredictionSource')) {
    Set-PSReadLineOption -PredictionSource History
    if ($psrlOption.Parameters.ContainsKey('PredictionViewStyle')) {
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
}
if ($psrlOption.Parameters.ContainsKey('HistorySearchCursorMovesToEnd')) {
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
}

Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+d    -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z    -Function Undo
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key Alt+Enter -Function AddLine
