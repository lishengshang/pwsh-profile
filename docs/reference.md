# 配置参考

安装粒度、依赖清单、环境变量开关与仓库结构。安装步骤见 [README](../README.md)。

## 组件

`setup.ps1` 按组件控制安装范围。profile 本体（Core）始终部署；未安装的工具运行时自动降级（对应别名/函数不创建），「选组件」即「选装哪些工具」，无需改代码。

预设：`-Minimal`（仅 core）→ 默认 **Standard**（core + completion + gitui）→ `-Full`（全部）。

| 组件 | 内容 |
|---|---|
| `core` | profile 本体 + 基础工具（见下表） |
| `completion` | PSCompletions、PSFzf（依赖 fzf） |
| `editor` | Neovim + LazyVim（含 WinLibs gcc，供 treesitter 编译） |
| `files` | yazi 及预览依赖（ffmpeg / jq / poppler / ImageMagick） |
| `gitui` | lazygit |

参数一览：

| 参数 | 作用 |
|---|---|
| `-Minimal` / `-Full` | 预设粒度（互斥） |
| `-Components core,gitui` | 显式指定组件（优先于预设；**必须逗号分隔**，空格分隔会报错） |
| `-SkipComponents editor` | 从解析结果剔除 |
| `-ExcludeTools fnm,ffmpeg` | 按名称剔除单个工具（功能运行时自动降级） |
| `-Yes` / `-Wizard` | 跳过 / 强制进入交互式向导（默认：交互终端且无组件参数时进向导） |
| `-SkipTools` | 跳过全部工具/模块下载，仅部署配置 |

示例：只装核心与 lazygit → `.\setup.ps1 -Components core,gitui`；全量但不要编辑器 → `.\setup.ps1 -Full -SkipComponents editor`。

## 依赖工具

必需：**PowerShell 7+**（完整体验；5.1 兼容模式见 [FAQ](faq.md)）、**Git**（bootstrap 自动安装）。以下均可选，启动时按 PATH 探测，缺失自动回退：

| 工具 | 组件 | 用途 | 缺失回退 |
|---|---|---|---|
| starship（`Starship.Starship`） | core | 提示符（懒加载） | 默认 prompt |
| eza（`eza-community.eza`） | core | 文件列表（图标 + git） | `Get-ChildItem` |
| zoxide（`ajeetdsouza.zoxide`） | core | 智能跳转 `z` | `cd` |
| ripgrep（`BurntSushi.ripgrep.MSVC`） | core | 内容搜索 `grep` | `Select-String` |
| fd（`sharkdp.fd`） | core | 文件查找 `find` | `find.exe` |
| bat（`sharkdp.bat`） | core | 文件高亮 `cat` | `Get-Content` |
| 7-Zip（`7zip.7zip`） | core | 解压 `unzip` | `Expand-Archive` |
| fnm（`Schniz.fnm`） | core | Node 版本管理 | - |
| fzf（`junegunn.fzf`） | completion | 模糊查找（Ctrl+t 文件 / Ctrl+r 历史 / Ctrl+g git） | - |
| lazygit（`JesseDuffield.lazygit`） | gitui | 终端 git UI（`lg`） | - |
| Neovim（`Neovim.Neovim`） | editor | 默认编辑器 `$EDITOR` | - |
| WinLibs gcc（`BrechtSanders.WinLibs.POSIX.UCRT`） | editor | treesitter 编译 | - |
| yazi（`sxyazi.yazi`） | files | 文件管理器（`y`） | - |
| ffmpeg / jq / poppler / ImageMagick | files | yazi 视频 / JSON / PDF / 字体预览 | - |
| PSCompletions / PSFzf / Terminal-Icons（`Install-Module`） | completion / core | 补全 / fzf 集成 / 图标兜底 | - |

更新：命令行工具 `wup`（winget），模块 `wum`（更新后需新开终端）。

## 环境变量开关

| 变量 | 作用 |
|---|---|
| `PROFILE_QUIET` | 强制静默（不显示问候/耗时） |
| `PROFILE_NO_TIME` / `PROFILE_NO_STARTUP` | 关闭耗时行 / 启动信息 |
| `PROFILE_NO_COMPLETIONS` | 跳过 PSCompletions 导入（离线/CI 用） |
| `PROFILE_NO_FZF_TAB` | 恢复默认 Tab 补全 |
| `PROFILE_KEEP_PARENT_PATH` | 保留父进程 PATH（默认从注册表重建，会丢弃 IDE/venv 注入的 PATH） |
| `PROFILE_DEBUG` | 打印各模块耗时与加载错误 |
| `PWSH_PROFILE_QUIET` | 5.1 兼容模式：关闭「建议用 pwsh」轻提示 |

输出被重定向（管道/CI）或无用户会话时自动静默；终端里 `pwsh -Command`（未重定向）仍显示横幅，CI 需绝对无输出时显式设 `PROFILE_QUIET=1`。

## 仓库结构

```
Microsoft.PowerShell_profile.ps1   入口：重建 PATH → 探测工具 → 按序加载 profile/*.ps1
profile/init-cache.ps1             工具 init 缓存（7 天 TTL + 升级即失效 + 原子写入）
profile/env.ps1                    fnm 初始化、EDITOR/VISUAL、fzf 配色
profile/prompt.ps1                 starship 提示符（缓存懒加载到首次 prompt）
profile/psreadline.ps1             PSReadLine（历史搜索、配色、快捷键）
profile/modules.ps1                zoxide 懒加载；PSCompletions / PSFzf
profile/aliases.ps1                全部别名与函数（即使用速查）
profile/startup.ps1                启动信息
starship.toml / lazygit/ / yazi/   外部配置（SkipIfExists 链接，已有配置优先）
nvim/                              LazyVim 配置（链接到 $env:LOCALAPPDATA\nvim）
Scripts/                           独立脚本（链接管理、修复、壁纸）
windows-terminal/                  终端配色与说明
docs/                              文档（速查 / 参考 / FAQ）
```

## 自定义

本仓库只做「接线」，深入定制请看官方文档：提示符 [Starship](https://starship.rs) · 模糊查找 [fzf](https://github.com/junegunn/fzf) / [PSFzf](https://github.com/psfzf/PSFzf) · 补全 [PSCompletions](https://github.com/abgox/PSCompletions) · 编辑器 [LazyVim](https://www.lazyvim.org/) · 终端 [Windows Terminal](https://github.com/microsoft/terminal)。改动仓库内配置后 commit/push，其他设备 `psync` 对齐。
