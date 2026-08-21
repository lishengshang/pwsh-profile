# PowerShell Profile

模块化的 PowerShell 7 配置：一条命令完成新机器安装，性能优先（冷启动 ~300ms、热启动 ~270ms），所有工具可选、缺失自动降级，仓库即配置。

> **设计原则**：所有外部工具均通过 PATH 解析，不绑定任何包管理器。工具缺失时自动回退到 PowerShell 内置命令，配置始终可加载。

## 快速开始

**方式一：一行引导（推荐，全新 Windows 机器）**

在 PowerShell 7 或系统自带的 Windows PowerShell 5.1 窗口里直接执行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; irm https://raw.githubusercontent.com/lishengshang/pwsh-profile/main/bootstrap.ps1 | Out-File "$env:TEMP\pwsh-profile-bootstrap.ps1" -Encoding utf8; & "$env:TEMP\pwsh-profile-bootstrap.ps1"
```

> 这是从远程执行脚本，请确认来源可信后再运行。`bootstrap.ps1` 会自动完成：装 PowerShell 7 → 装 Git → 克隆仓库到 `$HOME\Documents\PowerShell` → 安装全部依赖工具与模块。已装过 pwsh 的用户直接跑也不会报错，会自动跳过已装项。
> 若遇到 `ResourceUnavailable` 报错或杀软报毒，见文末「常见问题」。

**方式二：标准安装（已有 pwsh / 想装到其他目录）**

```powershell
git clone https://github.com/lishengshang/pwsh-profile.git ~/repos/pwsh-profile
cd ~/repos/pwsh-profile
.\setup.ps1
```

**方式三：克隆到 `$PROFILE` 目录直用（仓库即配置，作者本人用法）**

```powershell
git clone https://github.com/lishengshang/pwsh-profile.git $HOME\Documents\PowerShell
.\setup.ps1
```

> 推荐 PowerShell 7+（完整体验）；Windows PowerShell 5.1 也能以兼容模式加载配置（部分功能精简，见「常见问题」）。需要 Git；winget 需 Windows 10 1809+（自带 App Installer）。机器上只有自带 5.1 时直接执行方式一即可，会自动装好 pwsh 7。
> 符号链接需要开发者模式或管理员权限，未开启时 `setup.ps1` 自动回退到复制模式；已有配置自动备份到 `backup-<时间戳>` 目录。
> `starship.toml` 只在 `~/.config/starship.toml` **不存在时**才引入仓库默认——你有自己的主题配置时不会被覆盖。

### 装完后手动做 3 件事（每件 1 分钟）

1. **Nerd Font 字体**（提示符 / 文件列表图标需要）：
   ```powershell
   winget install -e --id DEVCOM.JetBrainsMonoNerdFont --source winget
   ```
   然后在 Windows Terminal 设置里把字体换成 `JetBrainsMono Nerd Font Mono`，重开终端生效。
2. **Windows Terminal 主题**（Solarized Dark 配色 + 半透明）：按 [`windows-terminal/README.md`](windows-terminal/README.md) 把配色加进 settings.json。
3. **LazyVim 已自动化**：`setup.ps1` 会把 LazyVim starter 引入仓库 `nvim/` 并链接到 `$env:LOCALAPPDATA\nvim`——**首次打开 nvim 时自动安装全部插件**（需要几分钟）。官方文档：<https://www.lazyvim.org/>。

装完**新开一个终端**让 winget 注入的 PATH 生效。

## 使用速查

### 文件与导航

| 命令 | 说明 |
|---|---|
| `ls` / `ll` / `la` / `lt` / `llt` | eza 图标列表 / 长格式+git / 长格式+隐藏+git / 树形 / 长格式+树形+git（eza 缺失时回退 `Get-ChildItem`） |
| `..` / `...` / `....` | 向上跳 1/2/3 级目录 |
| `mkcd <dir>` | 新建目录并进入 |
| `y` | yazi 文件管理器（退出时 cd 到最后浏览的目录） |
| `lg` | lazygit 终端 git UI（LazyVim 内 `<leader>gg` 调起浮窗） |
| `psync` | 拉取本仓库最新配置（多设备同步；重开终端/nvim 生效） |
| `cat` / `grep` / `find` | bat / ripgrep / fd（缺失时依次回退内置命令；`find.exe` 仍可显式调用） |
| `touch <file>` / `which <cmd>` / `unzip <file>` | 新建文件 / 查命令路径 / 7z 解压 |

### Git

| 命令 | 说明 |
|---|---|
| `gs` / `ga` / `gaa` | status / add / add --all |
| `gcm <msg>` / `gc` | commit -m / commit |
| `gp` / `gpl` / `gup` | push / pull / pull --rebase |
| `gl` / `glog` | 日志（图形+装饰）/ 详细日志（颜色+日期/作者） |
| `gd` / `gds` | diff / diff --staged |
| `gco` / `gcb` / `gb` / `gbn` | checkout / checkout -b / branch / 当前分支名 |
| `gst` / `grs` / `gclean` | stash / restore / 清理已合并分支（保护 main/master/dev；支持 `-WhatIf` 预览、`-Confirm` 逐个确认） |
| `gquick <msg>` | add --all → commit（失败即中止；默认不推送，`-Push` 才推送） |

### 系统与网络

| 命令 | 说明 |
|---|---|
| `myip` | 查询公网 IP（多 API 备用链） |
| `wup` | winget 一键升级全部已安装工具 |
| `wum` | 一键更新 PSGallery 模块（PSCompletions/PSFzf 等；更新后需新开终端） |
| `portof <port>` / `killport <port>` | 查询占用端口的进程 / 终止它（支持 `-WhatIf` 预览、`-Confirm` 确认） |
| `ps-reboot [delay]` / `ps-shutdown [delay]` | 重启 / 关机（不覆盖系统 `shutdown.exe`） |
| `ps-hibernate` / `ps-suspend` / `lock` | 休眠 / 睡眠 / 锁屏 |

### 编辑器与配置

| 命令 | 说明 |
|---|---|
| `ep` | 用 VS Code 编辑 profile（未装 VS Code 时回退 `$EDITOR`） |
| `ch` | 在当前目录打开 VS Code（回退 `$EDITOR`） |
| `wallpaper` | 下载并设置随机壁纸（见 `Scripts/wallpaper.ps1`） |

## 配置说明

```
Microsoft.PowerShell_profile.ps1   入口：重建 PATH → 探测工具 → 按序加载 profile/*.ps1
profile/init-cache.ps1             工具 init 缓存助手（7 天 TTL + 升级即失效 + 原子写入）
profile/env.ps1                    fnm 初始化（每次现场执行）、EDITOR/VISUAL、fzf 配色
profile/prompt.ps1                 starship 提示符（缓存懒加载到首次 prompt）
profile/psreadline.ps1             PSReadLine（历史搜索、配色、快捷键）
profile/modules.ps1                zoxide 懒加载；PSCompletions 同步加载 / PSFzf OnIdle 懒加载
profile/aliases.ps1                全部别名与函数（即上方速查表）
profile/startup.ps1                启动信息（问候 / 系统信息）
starship.toml                      提示符主题（链接到 ~/.config/starship.toml）
lazygit/config.yml                 lazygit 主题 Solarized Dark（链接到 %APPDATA%\lazygit\）
yazi/theme.toml                    yazi 主题（链接到 %APPDATA%\yazi\config\，flavor 由 setup 安装）
nvim/                              LazyVim 配置（链接到 $env:LOCALAPPDATA\nvim）
powershell.config.json             执行策略 RemoteSigned
```

### 多设备同步

仓库管理的四份外部配置（starship / lazygit / yazi / LazyVim）决定了「改一处、全设备一致」：

- **加 Neovim 插件**：在 `nvim/lua/plugins/` 新建一个 `.lua` 文件 → commit/push → 其他设备 `psync` 后重开 nvim，lazy.nvim 自动安装。
- **改键位/选项/主题**：改 `nvim/lua/config/`、`lazyvim.json`（extras）、`lazygit/config.yml` → commit/push → `psync`。
- **插件版本对齐**：`nvim/lazy-lock.json` 随仓库提交，各设备按锁定版本自动补装。
- **每设备本地生成、不入库**：插件本体（`nvim-data/lazy/`）、Mason 的 LSP 服务器、treesitter 编译产物——首次打开 nvim 时按仓库声明自动重建。
- **链接自愈**：git 的原子写入会弄断文件类硬链接，`psync` 拉取后会自动重链（`Scripts/Repair-ConfigLinks.ps1`）；只修复 setup 创建过的链接，你自己的存量配置（如原有 starship.toml）不会被碰。
- **输入法自动切换**（`nvim/lua/plugins/ime.lua`，smart-ime.nvim）：进插入模式自动切中文、退出切英文；若你改过系统的中/英切换键，同步改文件里的 `switch_key`。


环境变量开关：`PROFILE_QUIET`（强制静默，不显示问候/耗时）、`PROFILE_NO_TIME`（关闭耗时行）、`PROFILE_NO_STARTUP`（关闭启动信息）、`PROFILE_NO_COMPLETIONS`（跳过 PSCompletions 导入，离线/CI 用）、`PROFILE_NO_FZF_TAB`（恢复默认 Tab 补全）、`PROFILE_DEBUG`（打印各模块耗时与加载错误）、`PROFILE_KEEP_PARENT_PATH`（保留父进程 PATH）。

> 输出被重定向（管道捕获、CI 日志）或无用户会话时自动静默，不会污染 JSON/CSV/脚本输出。注意：终端里直接跑 `pwsh -Command`（输出未重定向）仍会显示横幅——脚本/CI 中需要绝对无输出时请显式设 `PROFILE_QUIET=1`。

> **想自定义？** 本仓库只做"接线"：提示符 → [Starship 官方文档](https://starship.rs)；模糊查找 → [fzf](https://github.com/junegunn/fzf) / [PSFzf](https://github.com/psfzf/PSFzf)；命令补全 → [PSCompletions](https://github.com/abgox/PSCompletions)；编辑器 → [LazyVim](https://www.lazyvim.org/)；终端 → [Windows Terminal](https://github.com/microsoft/terminal)。

## 依赖工具

### 必需依赖

| 工具 | 用途 | 备注 |
|---|---|---|
| PowerShell 7+ | 完整体验的运行时（5.1 可兼容模式降级使用） | `bootstrap.ps1` 自动安装 |
| Git | `psync` 同步、bootstrap 克隆、LazyVim starter 引入；yazi 的 MIME 检测也用其自带的 `file.exe`（`YAZI_FILE_ONE` 自动探测） | `bootstrap.ps1` 自动安装 |

### 可选工具（缺失时自动降级）

| 工具 | winget ID | 用途 | 缺失时回退 |
|---|---|---|---|
| starship | `Starship.Starship` | 提示符（懒加载） | 默认 prompt |
| eza | `eza-community.eza` | 文件列表（图标 + git） | `Get-ChildItem` |
| zoxide | `ajeetdsouza.zoxide` | 智能目录跳转（`z`） | `cd` |
| ripgrep | `BurntSushi.ripgrep.MSVC` | 内容搜索 | `Select-String` |
| fd | `sharkdp.fd` | 文件查找（别名 `find`） | `find.exe` |
| bat | `sharkdp.bat` | 查看文件（高亮） | `Get-Content` |
| 7-Zip | `7zip.7zip` | 解压 | `Expand-Archive` |
| fzf | `junegunn.fzf` | 模糊查找（Ctrl+t 文件 / Ctrl+r 历史 / Ctrl+g git） | - |
| fnm | `Schniz.fnm` | Node 版本管理 | - |
| Neovim | `Neovim.Neovim` | 默认编辑器（`$EDITOR`/`$VISUAL`） | - |
| yazi | `sxyazi.yazi` | 终端文件管理器（`y`，退出时 cd 到浏览目录） | - |
| ffmpeg | `Gyan.FFmpeg` | yazi 视频缩略图 | - |
| jq | `jqlang.jq` | yazi JSON 预览 | - |
| poppler | `oschwartz10612.Poppler` | yazi PDF 预览 | - |
| ImageMagick | `ImageMagick.ImageMagick` | yazi 字体/HEIC/JPEG XL 预览 | - |
| lazygit | `JesseDuffield.lazygit` | 终端 git UI（`lg`，LazyVim `<leader>gg`） | - |
| WinLibs gcc | `BrechtSanders.WinLibs.POSIX.UCRT` | LazyVim treesitter 解析器编译 | - |
| PSCompletions | （`Install-Module`）| 命令补全（git/winget 等，同步加载） | - |
| PSFzf | （`Install-Module`）| fzf 与 PSReadLine 集成 | - |
| Terminal-Icons | （`Install-Module`）| eza 缺失时 `ls` 图标兜底 | - |

> 上表可选工具：启动时用 `File.Exists` 遍历 PATH 一次性探测，缺失的工具其别名/函数自动跳过或回退，profile 不会因缺工具而报错。`setup.ps1`（不加 `-SkipTools`）自动安装上表全部工具与模块。
> 更新：命令行工具用 `wup`（winget），PowerShell 模块用 `wum`（`Update-Module`），**更新模块后需新开终端生效**。

## 常见问题

### 一行命令报 `ResourceUnavailable: Program 'powershell.exe' failed to run: ...` 或被杀软报毒？

旧版一行命令 `powershell -ExecutionPolicy Bypass -Command "irm ... | iex"` 以「绕过执行策略 + 下载远程脚本直接执行」的方式再拉起一个 powershell.exe，是无文件攻击的经典特征，Defender / 360 / 火绒等会在进程创建层拦截（报错文案随杀软而异）。这是安全软件的正常行为，**机器没有中毒，被拦截前没有执行任何代码**。

解决：改用新版一行命令（当前窗口直接执行）；或先下载、人工确认后再本地执行：

```powershell
irm https://raw.githubusercontent.com/lishengshang/pwsh-profile/main/bootstrap.ps1 -OutFile "$env:TEMP\bootstrap.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap.ps1"
```

仓库已在本机时直接 `.\bootstrap.ps1` 即可。若杀软已隔离文件，从隔离区恢复 `bootstrap.ps1` 即可。

### 已经装了 pwsh，还需要跑方式一吗？

不需要。方式一只面向全新机器；已装 pwsh 的用户用方式二或方式三即可。误跑方式一也不会报错：bootstrap 检测到 pwsh 已存在会跳过安装，并直接用当前实例继续执行 setup。

### 升级/重装模块后 `psc` 报错（如 `__need_update_data`、"不能对 null 调用方法"）？

PSCompletions 用全局变量 `$PSCompletions` + 固定 guid 判断是否已初始化——**旧终端会话里残留的旧版变量会让新版本模块跳过初始化**，导致函数对旧数据结构执行而报错。解决：

- **新开一个终端**（最稳，推荐）。已加载的损坏模块 + 常量变量 `$PSCompletions` 无法在当前会话清除（`Remove-Variable -Force` 对常量无效），只有新进程能干净导入。

一般规律：**任何模块升级后都建议新开终端**（`wum` 更新完也会提示）。

### 支持 Windows PowerShell 5.1 吗？

支持，以功能精简的「兼容模式」：全部脚本语法保持 5.1 可解析（不使用 `?.` / `??` 等 PS7 新语法），入口守卫在 5.1 下不再退出，而是加载可用功能子集（别名/函数、PSReadLine 基础配置、starship/eza/zoxide 等已装工具），启动时显示兼容提示。差异与建议：

- 完整体验（性能优化与新特性）以 PowerShell 7+ 为准；装 PS7 只需在仓库目录执行 `.\bootstrap.ps1`（或方式一）。
- 5.1 的 profile 目录是 `Documents\WindowsPowerShell\`，本仓库默认部署在 `Documents\PowerShell\`（PS7 专属），两者天然互不影响；兼容模式只在你把 5.1 指到本仓库入口文件时生效。
- 仅为 PS7 安装的模块（如 PSCompletions / PSFzf）在 5.1 下探测不到时自动跳过，不会报错。

### yazi 提示 `Cannot find 'file' to detect the file's MIME type`？

yazi 依赖 GNU `file` 做 MIME 检测。profile 启动时会自动探测 Git for Windows 自带的 `file.exe` 并设置 `YAZI_FILE_ONE` 环境变量指向它（官方推荐做法；Git 的 `usr\bin` 不在 PATH 里，所以 Git Bash 外看不到这个命令）。确认：新开终端执行 `echo $env:YAZI_FILE_ONE` 应输出 Git 目录下的 `usr\bin\file.exe` 路径。若 Git 装在非常规位置且探测不到，手动设置该变量即可。

## 参考与致谢

本配置站在以下开源项目的肩膀上（官方文档入口）：

| 项目 | 用途 | 官方链接 |
|---|---|---|
| PowerShell | 配置的运行环境（PS7） | <https://github.com/PowerShell/PowerShell> |
| Starship | 提示符 | <https://starship.rs> |
| eza | 文件列表 | <https://github.com/eza-community/eza> |
| zoxide | 智能目录跳转 | <https://github.com/ajeetdsouza/zoxide> |
| ripgrep | 内容搜索 | <https://github.com/BurntSushi/ripgrep> |
| fd | 文件查找 | <https://github.com/sharkdp/fd> |
| bat | 文件预览 | <https://github.com/sharkdp/bat> |
| fzf | 模糊查找 | <https://github.com/junegunn/fzf> |
| PSFzf | fzf × PSReadLine | <https://github.com/psfzf/PSFzf> |
| PSCompletions | 命令补全 | <https://github.com/abgox/PSCompletions> |
| Terminal-Icons | 回退列表图标 | <https://github.com/devblackops/Terminal-Icons> |
| fnm | Node 版本管理 | <https://github.com/Schniz/fnm> |
| Neovim / LazyVim | 默认编辑器 | <https://neovim.io> / <https://www.lazyvim.org/> |
| Nerd Fonts | 终端图标字体 | <https://www.nerdfonts.com> |
| JetBrains Mono | 终端字体 | <https://www.jetbrains.com/lp/mono/> |
| Solarized | 配色方案 | <https://ethanschoonover.com/solarized/> |
| Tokyo Night | fzf 配色 | <https://github.com/folke/tokyonight.nvim> |
| Windows Terminal | 终端 | <https://github.com/microsoft/terminal> |

## 设计说明

- **只使用 winget 安装**：所有工具通过 PATH 解析（运行时不绑定任何包管理器），安装统一走 `setup.ps1` 内置的 winget，不引入 scoop / chocolatey 等其它包管理器，避免多余的 shim 与报错；手动安装同样兼容。
- **避免覆盖系统命令**：`shutdown`/`reboot`/`hibernate`/`suspend` 改用 `ps-` 前缀，`find` 改用别名（`find.exe` 仍可显式调用）。
- **缓存原子写入**：starship/zoxide/fnm 的 init 缓存统一由 `profile/init-cache.ps1` 处理（7 天 TTL + 工具升级即失效，先写 `.tmp` 再 Move，失败回退旧缓存）。
- **PATH 重建的取舍**：启动时从注册表重建 PATH（避免继承父进程的陈旧 PATH），代价是丢弃父进程注入的 PATH（如 IDE 启动器、venv 激活后的入口），需要保留时设 `PROFILE_KEEP_PARENT_PATH=1`。
- **性能**：工具探测用 `File.Exists` 遍历 PATH（~37ms，比 `Get-Command` 快约 5 倍）；外部工具 init 懒加载 + 缓存；PSCompletions 因官方要求全局作用域直接导入（禁止嵌套调用 `Import-Module`，见[官方文档](https://pscompletions.abgox.com)与 #155/#143），无法懒加载，冷启动 +~200ms 为官方约束的代价。
