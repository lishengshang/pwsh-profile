# PowerShell Profile

模块化的 PowerShell 7 配置，采用类 XDG 的分文件结构，集成现代命令行工具（eza / zoxide / starship / fzf / LazyVim 等）。启动优化后冷启动 ~300ms、热启动 ~120ms。

> **设计原则**：所有外部工具均通过 PATH 解析，不绑定任何包管理器。工具缺失时自动回退到 PowerShell 内置命令，配置始终可加载。

## 目录结构

```
PowerShell/
├── Microsoft.PowerShell_profile.ps1   # 入口：批量探测工具 + 按顺序加载各模块（带计时门控）
├── profile/
│   ├── init-cache.ps1     # 外部工具 init 缓存助手（7 天 TTL + 升级即失效 + 原子写入）
│   ├── env.ps1            # 环境初始化（fnm 缓存、EDITOR/VISUAL=nvim）
│   ├── prompt.ps1         # starship 提示符（缓存 + 原子写入 + 懒加载）
│   ├── psreadline.ps1     # PSReadLine 配置（预测、配色、快捷键；非交互环境自动跳过）
│   ├── modules.ps1        # zoxide 懒加载 + PSCompletions/PSFzf 通过 OnIdle 懒加载
│   ├── aliases.ps1        # 别名与函数
│   └── startup.ps1        # 启动信息（问候/系统信息/键位速查）
├── Scripts/
│   └── wallpaper.ps1      # 壁纸自动下载脚本
├── windows-terminal/      # Windows Terminal 主题（Solarized Dark + 使用说明）
├── setup.ps1              # 一键安装脚本（符号链接/复制 + 自动备份 + 工具/模块安装）
├── bootstrap.ps1          # 全新机器引导脚本（PS 5.1 可跑：装 pwsh/git + 克隆 + setup）
└── powershell.config.json
```

## 快速开始（新机器 / 给别人用）

三种用法，按自动化程度从高到低：

**方式一：一行引导（推荐，全新 Windows 机器）**

在 PowerShell 7 或系统自带的 Windows PowerShell 5.1 窗口里直接执行（已装 pwsh 的用户跑它也不会报错，bootstrap 会自动跳过已装项继续）：

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force; irm https://raw.githubusercontent.com/lishengshang/pwsh-profile/main/bootstrap.ps1 | Out-File "$env:TEMP\pwsh-profile-bootstrap.ps1" -Encoding utf8; & "$env:TEMP\pwsh-profile-bootstrap.ps1"
```

> 这是从远程执行脚本，请确认来源可信后再运行。`bootstrap.ps1` 会自动完成：装 PowerShell 7 → 装 Git → 克隆本仓库到 `$HOME\Documents\PowerShell`（pwsh 的 `$PROFILE` 目录，profile 直接生效）→ 自动安装全部依赖工具与模块。
> 新版写法在当前窗口直接执行，不再拉起新的 powershell.exe 进程；若在旧版写法（`powershell -Command "irm ... | iex"`）下遇到 `ResourceUnavailable` 报错或杀软报毒，见文末「常见问题」。

**方式二：标准安装（已有 pwsh / 想装到其他目录）**

见下方「安装」章节：`git clone` 到任意目录 → `.\setup.ps1`，文件通过符号链接（或复制）挂到 `$PROFILE`。

**方式三：克隆到 `$PROFILE` 目录直用（仓库即配置）**

把仓库克隆到 `$HOME\Documents\PowerShell` 后无需任何链接，`setup.ps1` 会自动检测到这一情况并跳过文件安装、只装工具与模块。作者本人就是这么用的。

## 前置条件

| 条件 | 要求 |
|---|---|
| PowerShell | **7+**（`pwsh`）。配置使用 `& ` 调用、`??`、`?.` 等 PS7 语法 |
| 执行策略 | `RemoteSigned`（`setup.ps1` 会自动写入 `powershell.config.json`）|
| Git | 用于克隆本仓库 |
| winget | Windows 10 1809+ 自带（App Installer），用于安装依赖工具 |

> Windows PowerShell 5.1（`powershell.exe`）不支持，请用 `pwsh`。

## 安装

### 1. 克隆仓库

```powershell
git clone https://github.com/lishengshang/pwsh-profile.git ~/repos/pwsh-profile
cd ~/repos/pwsh-profile
```

### 2. 运行安装脚本

```powershell
.\setup.ps1
```

脚本会：

1. 把 `Microsoft.PowerShell_profile.ps1` / `profile/` / `Scripts/` / `powershell.config.json` 链接（或复制）到 `$PROFILE` 所在目录，并自动备份原配置到 `backup-<时间戳>` 子目录；
2. **自动安装全部依赖**：用 winget 装齐 10 个命令行工具（见下方表格），用 `Install-Module` 装 PSCompletions / PSFzf。

不想自动装工具时加 `-SkipTools` 跳过；装完**新开一个终端**让 winget 注入的 PATH 生效。

> 符号链接需要开发者模式或管理员权限；未开启时脚本自动回退到复制模式。
> 若仓库目录本身就是 `$PROFILE` 所在目录（本机直用仓库），脚本会跳过文件链接，只安装工具与模块。

### 3. （可选）手动安装 PowerShell 模块

上一步已自动完成，需要手动执行时：

```powershell
Install-Module PSCompletions, PSFzf -Scope CurrentUser
```

### 4. （可选）手动安装命令行工具（winget）

上一步已自动完成，需要手动执行时（一行装齐全部依赖）：

```powershell
winget install --id Starship.Starship -e `
  && winget install --id eza-community.eza -e `
  && winget install --id ajeetdsouza.zoxide -e `
  && winget install --id BurntSushi.ripgrep.MSVC -e `
  && winget install --id sharkdp.fd -e `
  && winget install --id sharkdp.bat -e `
  && winget install --id 7zip.7zip -e `
  && winget install --id junegunn.fzf -e `
  && winget install --id Schniz.fnm -e `
  && winget install --id Neovim.Neovim -e
```

> PowerShell 中 `&&` 需 PS7+。装完后**新开一个终端**让 winget 注入的 PATH 生效。

### 5. （可选）安装 LazyVim

```powershell
# 需要 Neovim >= 0.9
git clone https://github.com/LazyVim/starter $env:LOCALAPPDATA\nvim
Remove-Item $env:LOCALAPPDATA\nvim\.git -Recurse -Force   # 改成自己的仓库
```

### 6. 重新打开 PowerShell

执行 `pwsh`，或 `. $PROFILE` 重新加载配置。

## 依赖工具

| 工具 | winget ID | 用途 | 缺失时回退 |
|---|---|---|---|
| starship | `Starship.Starship` | 提示符（懒加载） | 默认 prompt |
| eza | `eza-community.eza` | 文件列表（图标 + git） | `Get-ChildItem` |
| zoxide | `ajeetdsouza.zoxide` | 智能目录跳转（`z`） | `cd` |
| ripgrep | `BurntSushi.ripgrep.MSVC` | 内容搜索 | `Select-String` |
| fd | `sharkdp.fd` | 文件查找（别名 `find`） | `find.exe` |
| bat | `sharkdp.bat` | 查看文件（高亮） | `Get-Content` |
| 7zip | `7zip.7zip` | 解压 | `Expand-Archive` |
| fzf | `junegunn.fzf` | 模糊查找（Ctrl+t 文件 / Ctrl+r 历史 / Ctrl+g 前缀 git 和弦：+b 分支、+f 文件、+h 提交、+t tag；Tab 补全 fzf-tab 式） | - |
| fnm | `Schniz.fnm` | Node 版本管理 | - |
| Neovim | `Neovim.Neovim` | 默认编辑器（`$EDITOR`/`$VISUAL`） | - |
| PSCompletions | （`Install-Module`）| 命令补全（git/winget 等，OnIdle 懒加载） | - |
| PSFzf | （`Install-Module`）| fzf 与 PSReadLine 集成 | - |

> 所有工具均为可选。配置启动时一次性探测（`Get-Command` 批量调用），缺失的工具其别名/函数自动跳过或回退到内置命令，profile 不会因缺工具而报错。
> `setup.ps1`（不加 `-SkipTools`）会自动安装上表全部工具与模块。

## 启动性能

| 场景 | 耗时 | 说明 |
|---|---|---|
| 冷启动 | ~150ms | 无任何缓存，仅 fnm env 需现场生成 |
| 热启动 | ~40ms | 缓存命中（日常场景） |

优化点：
- **工具探测轻量化**：用 `File.Exists` 遍历 PATH（`.exe/.cmd/.bat`）替代 `Get-Command`，11 个名字约 37ms（`Get-Command` 对缺失名字做 PATH×PATHEXT 全展开约 190ms）
- **PATH 重建前置**：入口先按注册表重建 PATH 再探测工具，避免父进程 PATH 不完整时探测不到已安装工具
- **fnm env 缓存化**：7 天 TTL + 升级即失效 + 原子写入，热启动免调用外部进程
- **starship 全懒加载**：缓存 `--print-full-init` 完整脚本（dot-source 零进程调用），且**缓存生成延迟到首次 prompt**
- **zoxide 全懒加载**：init 生成与加载延迟到首次 `z`/`zi` 调用
- **Terminal-Icons 按需加载**：仅在 eza 缺失且首次执行 `ls` 时加载（模块加载本身 ~100ms+）
- **PSCompletions / PSFzf 懒加载**：通过 `PowerShell.OnIdle` 事件在首个 prompt 渲染后加载，不阻塞首屏
- **PSReadLine 非交互保护**：stdout 被重定向时跳过配置，避免 VT 报错
- **启动日志门控**：仅 `$env:PROFILE_DEBUG=1` 时打印各模块耗时，默认安静

### 调试启动

```powershell
$env:PROFILE_DEBUG = 1    # 开启耗时打印
pwsh                      # 开新终端查看
```

缓存文件位于 `$env:TEMP\{fnm,zoxide}-init-cache.ps1` 与 `$env:TEMP\starship-init-cache-v2.ps1`。缓存同时以「7 天 TTL」和「工具二进制更新时间」两个条件失效：**工具升级后下次启动自动重新生成，无需手动删除**。

## 启动行为

新开终端时显示 4 行启动信息（带 Nerd Font 图标与 Solarized 配色，均为毫秒级轻量读取，不拖慢启动）：

```
 Hi lishe · 2026-08-14 星期五
 Windows 10 Pro 23H2 ·  PS 7.6.4 ·  16 核
 Ctrl+t 文件 · Ctrl+r 历史 · Ctrl+g git · gs 状态 · z 跳转 · .. 上级
 Profile loaded in 36ms
```

> 图标依赖 Nerd Font 字体（安装见 `windows-terminal/README.md`）；无 Nerd Font 的环境会显示为方块，但功能不受影响。

## fzf 界面（Solarized）

- **UI 美化**：通过 `FZF_DEFAULT_OPTS` 设置 Solarized 配色 + 40% 高度 + 反向布局 + 圆角边框 + 右侧预览窗（`profile/env.ps1`，已自行设置该变量时不会覆盖）
- **fzf-tab 式 Tab 补全**：Tab 弹出 fzf 选择器（带右侧实时预览），类似 Linux zsh 的 fzf-tab；与 PSCompletions 的补全项兼容
- 与 PSCompletions 菜单冲突时恢复默认 Tab：`$env:PROFILE_NO_FZF_TAB = 1`

- 关闭耗时行：`$env:PROFILE_NO_TIME = 1`
- 关闭信息行（问候/系统信息/键位速查）：`$env:PROFILE_NO_STARTUP = 1`
- 信息行的键位部分在 fzf 未安装时自动省略
- **setup 完成横幅**：运行 `setup.ps1` 安装完成时显示点阵大字 `PWSH`（Solarized 渐变）

## 常用别名与函数

### Profile 管理

| 命令 | 说明 |
|---|---|
| `ep` | 用 VS Code 编辑 profile（未装 VS Code 时回退 `$EDITOR`） |

### 导航

| 命令 | 说明 |
|---|---|
| `..` / `...` / `....` | 向上跳目录 |
| `mkcd <dir>` | 新建目录并进入 |

> 注：PowerShell 原生支持 `cd ~`，无需额外别名。
> eza 缺失时 `ls` 家族回退 `Get-ChildItem`，若装有 Terminal-Icons 模块则自动启用图标。

### 文件列表（基于 eza）

| 命令 | 说明 |
|---|---|
| `ls` | 图标列表 |
| `ll` | 长格式 + git 状态 |
| `la` | 长格式 + 隐藏文件 + git 状态 |
| `lt` | 树形（2 层） |
| `llt` | 长格式 + 树形 + git 状态 |

### Git 快捷命令

| 命令 | 说明 |
|---|---|
| `gs` / `ga` / `gaa` | status / add / add --all |
| `gcm <msg>` / `gc` | commit -m / commit |
| `gp` / `gpl` | push / pull |
| `gl` | 日志（图形 + 装饰） |
| `gd` / `gds` | diff / diff --staged |
| `gco` / `gcb` | checkout / checkout -b |
| `gb` / `gst` / `grs` | branch / stash / restore |
| `gbn` | 当前分支名 |
| `gquick <msg>` | add --all -> commit -> push（失败即中止） |
| `glog` | 详细日志（图形 + 颜色 + 日期/作者） |
| `gup` | pull --rebase |
| `gclean` | 清理已合并的本地分支（保护 main/master/dev） |

### 系统与网络

| 命令 | 说明 |
|---|---|
| `myip` | 查询公网 IP（ifconfig.me / ipify / ipinfo 备用链） |
| `wup` | winget 一键升级全部已安装工具 |
| `portof <port>` | 查询占用端口的进程 |
| `killport <port>` | 终止占用端口的进程 |
| `ps-reboot [delay]` | 重启（不覆盖系统 `shutdown.exe`） |
| `ps-shutdown [delay]` | 关机 |
| `ps-hibernate` | 休眠 |
| `ps-suspend` | 睡眠 |
| `lock` | 锁屏 |

> 电源命令使用 `ps-` 前缀以避免覆盖系统 `shutdown.exe`；调用系统原命令请用 `shutdown.exe`。

### 文件工具

| 命令 | 说明 |
|---|---|
| `cat` | bat（高亮，缺失时回退） |
| `grep` | ripgrep（缺失时回退到 Select-String） |
| `find` | fd（别名；`find.exe` 仍可显式调用） |
| `touch <file>` | 新建文件 |
| `which <cmd>` | 查命令路径（找不到时给出反馈） |
| `unzip <file>` | 7z 解压（缺失时回退到 Expand-Archive） |
| `ch` | 在当前目录打开 VS Code（未装 VS Code 时回退 `$EDITOR`） |
| `wallpaper` | 下载并设置随机壁纸（`-n` 不超分 / `-c` 清理旧图 / `-s` 静默 / `-strict` 缺 waifu2x 时中止，默认降级用原图；见 `Scripts/wallpaper.ps1`） |

## 设计说明

- **不绑定包管理器**：所有工具通过 PATH 解析，winget / 手动安装均可，不依赖 scoop shim（避免 SSH 远程会话下 shim 的 GUI/控制台检测崩溃）。
- **避免覆盖系统命令**：`shutdown`/`reboot`/`hibernate`/`suspend` 改用 `ps-` 前缀，`find` 改用别名（`find.exe` 仍可显式调用）。
- **未批准动词规避**：`Edit-Profile` 改为 `profile-edit`，避免 PowerShell 的未批准动词警告。
- **`$LASTEXITCODE` 串联**：`gquick` 在 add/commit 失败时中止，不会盲目 push。
- **缓存原子写入**：所有外部工具 init 缓存（starship/zoxide/fnm）统一由 `profile/init-cache.ps1` 处理，先写到 `.tmp` 再 Move，校验 `$LASTEXITCODE -eq 0` 且输出非空；缓存因 7 天 TTL 或工具升级自动失效。
- **PATH 重建的取舍**：profile 启动时从注册表重建 PATH（避免继承父进程的陈旧 PATH），代价是丢弃父进程注入的 PATH（如 IDE 启动器、venv 激活后的入口）。需要保留时设置 `$env:PROFILE_KEEP_PARENT_PATH = 1`。
- **`Modules/` 目录**：仓库内的 `Modules/` 是 pwsh 的默认用户模块目录（因为仓库本身就在 `$PROFILE` 目录下），由 `setup.ps1` / `Install-Module` 填充，已 gitignore，不纳入版本管理。

## 常见问题

### 一行命令报 `ResourceUnavailable: Program 'powershell.exe' failed to run: ...` 或被杀软报毒？

**原因**：旧版一行命令是 `powershell -ExecutionPolicy Bypass -Command "irm ... | iex"`——以「绕过执行策略 + 下载远程脚本并直接执行」的方式再拉起一个 powershell.exe 进程。这正是无文件恶意软件的经典特征，Defender / 360 / 火绒等安全软件会在进程创建层拦截，表现为 `ResourceUnavailable` 报错（错误信息可能随杀软不同而不同，如 "The Process object must have the UseShellExecute property set to false..." 或 "拒绝访问"）或报毒弹窗。这是安全软件的正常行为，**机器没有中毒，被拦截前没有执行任何代码**。

**解决**：改用新版一行命令（当前窗口直接执行，不再拉起新进程）；或先下载、人工确认后再本地执行：

```powershell
irm https://raw.githubusercontent.com/lishengshang/pwsh-profile/main/bootstrap.ps1 -OutFile "$env:TEMP\bootstrap.ps1"
powershell -ExecutionPolicy Bypass -File "$env:TEMP\bootstrap.ps1"
```

如果仓库已经在本机，直接 `.\bootstrap.ps1` 即可，完全绕开远程执行。若杀软已隔离文件，从隔离区恢复 `bootstrap.ps1` 即可。

### 已经装了 pwsh，还需要跑方式一吗？

不需要。方式一只面向全新机器；已装 pwsh 的用户直接 `git clone` + `.\setup.ps1`（方式二），或在 `$PROFILE` 目录克隆直用（方式三）。误跑方式一也不会报错：bootstrap 检测到 pwsh 已存在会跳过安装，并直接用当前实例继续执行 setup。
