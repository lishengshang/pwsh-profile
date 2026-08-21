# pwsh-profile

模块化 PowerShell 配置：一条命令装好新机器，冷启动 ~300ms，所有工具可选、缺失自动降级，仓库即配置。

> PowerShell 7+ 完整体验；Windows PowerShell 5.1 兼容模式全链路可用（安装 / 向导 / profile，差异见 [FAQ](docs/faq.md)）。

## 安装

**一行引导**（全新 Windows 机器，在 PowerShell 窗口直接执行）：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; irm https://raw.githubusercontent.com/lishengshang/pwsh-profile/main/bootstrap.ps1 | Out-File "$env:TEMP\pwsh-profile-bootstrap.ps1" -Encoding utf8; & "$env:TEMP\pwsh-profile-bootstrap.ps1"
```

> 远程脚本，请确认来源可信。引导流程：装 pwsh 7（5.1 下会询问，可选）→ 装 Git → 克隆仓库 → 进安装向导。报 `ResourceUnavailable` / 杀软拦截见 [FAQ](docs/faq.md)。

**手动安装**（已装 pwsh 7 与 Git）：

```powershell
git clone https://github.com/lishengshang/pwsh-profile.git <目录>   # 克隆到 $HOME\Documents\PowerShell 即“仓库即配置”（作者用法）
cd <目录>; .\setup.ps1
```

> 符号链接需开发者模式或管理员权限，未开启自动回退复制模式，已有配置备份到 `backup-<时间戳>`；`starship.toml` 等外部配置 SkipIfExists——你的存量配置优先，不会被覆盖。

**装完 3 件事**：

1. **Nerd Font**（图标字体）：`winget install -e --id DEVCOM.JetBrainsMonoNerdFont` → 终端字体改为 `JetBrainsMono Nerd Font Mono`
2. **终端主题**（可选）：按 [windows-terminal/README.md](windows-terminal/README.md) 加 Solarized Dark 配色
3. **重开终端**让 PATH 生效（装了 editor 组件时，首次打开 nvim 自动装插件，需几分钟）

## 快速上手

| 命令 | 说明 |
|---|---|
| `ll` / `lt` | eza 长格式 / 树形列表（图标 + git 状态） |
| `z <目录>` | zoxide 智能跳转 |
| `gs` / `gcm <msg>` / `gp` | git status / commit / push |
| `lg` | lazygit 终端 git UI |
| `y` | yazi 文件管理器（退出时 cd 到浏览目录） |
| `grep` / `find` / `cat` | ripgrep / fd / bat（缺失自动回退内置命令） |
| `myip` / `wup` / `wum` | 公网 IP / winget 升级工具 / 更新模块 |
| `psync` | 拉取本仓库最新配置（多设备同步） |
| `ep` / `ch` | 编辑 profile / 当前目录打开 VS Code |

全部 60+ 别名与函数见 [使用速查](docs/usage.md)。

## 文档

| 文档 | 内容 |
|---|---|
| [使用速查](docs/usage.md) | 全部命令、多设备同步 |
| [配置参考](docs/reference.md) | 组件选择、依赖工具、环境变量开关、仓库结构 |
| [常见问题](docs/faq.md) | 杀软拦截、模块更新、5.1 兼容边界 |

## 致谢

站在开源社区肩膀上：[Starship](https://starship.rs) · [fzf](https://github.com/junegunn/fzf) · [PSCompletions](https://github.com/abgox/PSCompletions) · [LazyVim](https://www.lazyvim.org/) · [eza](https://github.com/eza-community/eza) / [zoxide](https://github.com/ajeetdsouza/zoxide) / [lazygit](https://github.com/JesseDuffield/lazygit) / [yazi](https://github.com/sxyazi/yazi) / [bat](https://github.com/sharkdp/bat) / [fd](https://github.com/sharkdp/fd) / [ripgrep](https://github.com/BurntSushi/ripgrep) · [Nerd Fonts](https://www.nerdfonts.com) / [Solarized](https://ethanschoonover.com/solarized/)。
