# ==============================================================
# PSReadLine 配置
# ==============================================================
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistoryNoDuplicates -MaximumHistoryCount 10000
Set-PSReadLineOption -Colors @{
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
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Ctrl+d    -Function DeleteCharOrExit
Set-PSReadLineKeyHandler -Key Ctrl+z    -Function Undo
Set-PSReadLineKeyHandler -Key Tab       -Function MenuComplete
Set-PSReadLineKeyHandler -Key Alt+Enter -Function AddLine
