# 管理链接清单（唯一事实来源，setup.ps1 与 Repair-ConfigLinks.ps1 共用）
# Source 相对仓库根。
#   Core：核心条目（$PROFILE 本体）。目标存在但非本仓库管理时备份接管；
#         仓库即 $PROFILE 目录时整组跳过（源与目标同路径，无法自链）。
#   SkipIfExists：目标已存在时不动它（用户自有配置优先），仅缺失时引入仓库默认。
@(
    # ---- 核心条目：始终是 profile 本体，任何组件选择都部署 ----
    @{ Source = 'Microsoft.PowerShell_profile.ps1'; Target = $PROFILE; Core = $true }
    @{ Source = 'profile'; Target = Join-Path (Split-Path $PROFILE) 'profile'; Core = $true }
    @{ Source = 'Scripts'; Target = Join-Path (Split-Path $PROFILE) 'Scripts'; Core = $true }
    @{ Source = 'powershell.config.json'; Target = Join-Path (Split-Path $PROFILE) 'powershell.config.json'; Core = $true }
    # ---- 外部配置：按组件选择部署（SkipIfExists 仍生效：用户自有配置优先） ----
    @{ Source = 'starship.toml'; Target = Join-Path $HOME '.config\starship.toml'; Component = 'core'; SkipIfExists = $true }
    @{ Source = 'lazygit\config.yml'; Target = Join-Path $env:APPDATA 'lazygit\config.yml'; Component = 'gitui'; SkipIfExists = $true }
    @{ Source = 'yazi\theme.toml'; Target = Join-Path $env:APPDATA 'yazi\config\theme.toml'; Component = 'files'; SkipIfExists = $true }
    @{ Source = 'nvim'; Target = Join-Path $env:LOCALAPPDATA 'nvim'; Component = 'editor'; SkipIfExists = $true }
)
