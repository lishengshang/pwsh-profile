# 外部配置链接清单（唯一事实来源，setup.ps1 与 Repair-ConfigLinks.ps1 共用）
# Source 相对仓库根；SkipIfExists：目标已存在时不动它（用户自有配置优先）。
@(
    @{ Source = 'starship.toml'; Target = Join-Path $HOME '.config\starship.toml'; SkipIfExists = $true }
    @{ Source = 'lazygit\config.yml'; Target = Join-Path $env:APPDATA 'lazygit\config.yml'; SkipIfExists = $true }
    @{ Source = 'yazi\theme.toml'; Target = Join-Path $env:APPDATA 'yazi\config\theme.toml'; SkipIfExists = $true }
    @{ Source = 'nvim'; Target = Join-Path $env:LOCALAPPDATA 'nvim'; SkipIfExists = $true }
)
