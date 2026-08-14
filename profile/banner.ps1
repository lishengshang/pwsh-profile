# ==============================================================
# 启动画面（点阵大字 + 版本信息）
# 由 modules.ps1 的 OnIdle 事件在首个 prompt 渲染后调用一次，
# profile 加载时仅定义函数，不阻塞启动路径。
# 设置 $env:PROFILE_NO_BANNER=1 可关闭。
# ==============================================================

# 想换大字内容？改 __BannerText（目前字库只有 P/W/S/H 四字母）
$script:__BannerText = 'PWSH'

# 5x7 点阵字库
$script:__BannerFont = @{
    P = @('#####','#   #','#   #','#####','#    ','#    ','#    ')
    W = @('#   #','#   #','# # #','## ##','## ##','#   #','#   #')
    S = @('#####','#    ','#    ','#### ','    #','    #','#####')
    H = @('#   #','#   #','#   #','#####','#   #','#   #','#   #')
}

function Show-Banner {
    if ([Console]::IsOutputRedirected) { return }
    if ($env:PROFILE_NO_BANNER) { return }

    # 每行渐变色（Solarized 色板，24bit ANSI）
    $colors = @(
        '38;2;38;139;210',   # blue
        '38;2;42;161;152',   # cyan
        '38;2;133;153;0',    # green
        '38;2;181;137;0',    # yellow
        '38;2;203;75;22',    # orange
        '38;2;220;50;47',    # red
        '38;2;108;113;196'   # violet
    )

    # 逐字母取点阵，逐行拼接（字母间 2 空格）
    $rows = @('', '', '', '', '', '', '')
    foreach ($ch in $script:__BannerText.ToCharArray()) {
        $glyph = $script:__BannerFont[[string]$ch]
        if (-not $glyph) { continue }
        for ($i = 0; $i -lt 7; $i++) {
            $rows[$i] += $glyph[$i] + '  '
        }
    }

    for ($i = 0; $i -lt 7; $i++) {
        Write-Host "`e[$($colors[$i])m$($rows[$i])`e[0m"
    }

    $ver = $PSVersionTable.PSVersion.ToString()
    $date = Get-Date -Format 'yyyy-MM-dd'
    Write-Host "`e[38;2;88;110;117mPowerShell v$ver  |  $date`e[0m"
    Write-Host ''
}
