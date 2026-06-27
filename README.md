# PowerShell Profile

模块化的 PowerShell 7 配置，采用类 XDG 的分文件结构，集成现代命令行工具（eza / zoxide / starship / fzf / LazyVim 等）。启动优化后冷启动 ~300ms、热启动 ~120ms。

## 目录结构

```
PowerShell/
├── Microsoft.PowerShell_profile.ps1   # 入口：按顺序加载各模块（带计时门控）
├── profile/
│   ├── env.ps1          # 环境初始化（fnm 缓存、EDITOR/VISUAL=nvim、scoop）
│   ├── prompt.ps1       # starship 提示符（7 天缓存 + 原子写入 + 懒加载）
│   ├── psreadline.ps1   # PSReadLine 配置（预测、配色、快捷键；非交互环境自动跳过）
│   ├── modules.ps1      # zoxide 缓存 + PSCompletions/PSFzf 通过 OnIdle 懒加载
│   └── aliases.ps1      # 别名与函数
├── Scripts/
│   └── wallpaper.ps1    # 壁纸自动下载脚本
└── powershell.config.json
```

## 安装

1. 克隆到 PowerShell 配置目录：

   ```powershell
   git clone <repo-url> $(Split-Path $PROFILE)
   ```

2. 安装依赖模块：

   ```powershell
   Install-Module PSCompletions, PSFzf -Scope CurrentUser
   ```

3. 安装现代命令行工具（推荐用 scoop）：

   ```powershell
   scoop install starship eza zoxide fzf fd ripgrep bat 7zip fnm neovim
   ```

4. 安装 [LazyVim](https://www.lazyvim.org/)（Neovim 配置框架）：

   ```powershell
   # 需要 Neovim >= 0.9
   git clone https://github.com/LazyVim/starter $env:LOCALAPPDATA\nvim
   rm $env:LOCALAPPDATA\nvim\.git -Recurse -Force   # 改成自己的仓库
   ```

5. 重新打开 PowerShell 或执行 `. $PROFILE`（别名 `rp`）。

## 依赖工具

| 工具 | 用途 | 替代的命令 |
|---|---|---|
| starship | 提示符（懒加载） | 默认 prompt |
| eza | 文件列表（图标 + git） | `ls` / `ll` / `la` / `lt` |
| zoxide | 智能目录跳转 | `cd` / `z` |
| fzf + PSFzf | 模糊查找（Ctrl+t / Ctrl+r） | — |
| fd | 文件查找（别名 `find`） | `find` |
| ripgrep | 内容搜索 | `grep` |
| bat | 查看文件（高亮） | `cat` |
| 7zip | 解压 | `unzip` |
| fnm | Node 版本管理 | — |
| Neovim + LazyVim | 默认编辑器（`$EDITOR` / `$VISUAL`） | git commit / npm edit 等 |
| PSCompletions | 命令补全（git / scoop / winget 等，OnIdle 懒加载） | — |

部分工具缺失时会自动回退到 PowerShell 内置命令。

## 启动性能

| 场景 | 耗时 | 说明 |
|---|---|---|
| 冷启动 | ~300ms | 首次或缓存过期，需现场生成 starship/zoxide/fnm 缓存 |
| 热启动 | ~120ms | 缓存命中（日常场景） |

优化点：
- **fnm env 缓存化**：7 天 TTL，热启动免调用外部进程
- **starship / zoxide 缓存**：7 天 TTL + 原子写入（先写 `.tmp` 再 Move，避免半写竞态）
- **PSCompletions / PSFzf 懒加载**：通过 `PowerShell.OnIdle` 事件在首个 prompt 渲染后加载，不阻塞首屏
- **PSReadLine 非交互保护**：stdout 被重定向时跳过配置，避免 VT 报错
- **启动日志门控**：仅 `$env:PROFILE_DEBUG=1` 时打印各模块耗时，默认安静

### 调试启动

```powershell
$env:PROFILE_DEBUG=1    # 开启耗时打印
pwsh                    # 开新终端查看
```

缓存文件位于 `$env:TEMP\{starship,zoxide,fnm}-init-cache.ps1`，工具升级后删除即可强制刷新。

## 常用别名与函数

### Profile 管理

| 命令 | 说明 |
|---|---|
| `rp` | 重新加载 profile |
| `ep` | 用 VS Code 编辑 profile |

### 导航

| 命令 | 说明 |
|---|---|
| `..` / `...` / `....` | 向上跳目录 |
| `mkcd <dir>` | 新建目录并进入 |

> 注：PowerShell 原生支持 `cd ~`，无需额外别名。

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
| `gquick <msg>` | add --all → commit → push（失败即中止） |

### 系统与网络

| 命令 | 说明 |
|---|---|
| `myip` | 查询公网 IP |
| `portof <port>` | 查询占用端口的进程 |
| `killport <port>` | 终止占用端口的进程 |
| `ps-reboot [delay]` | 重启（不覆盖系统 `shutdown.exe`） |
| `ps-shutdown [delay]` | 关机 |
| `ps-hibernate` | 休眠 |
| `ps-suspend` | 睡眠 |
| `lock` | 锁屏 |

> 电源命令使用 `ps-` 前缀以避免覆盖系统 `shutdown.exe`；调用系统原命令请用 `shutdown.exe` / `reboot.exe`。

### 文件工具

| 命令 | 说明 |
|---|---|
| `cat` | bat（高亮，缺失时回退） |
| `grep` | ripgrep（缺失时回退到 Select-String） |
| `find` | fd（别名；`find.exe` 仍可显式调用） |
| `touch <file>` | 新建文件 |
| `which <cmd>` | 查命令路径（找不到时给出反馈） |
| `unzip <file>` | 7z 解压（缺失时回退到 Expand-Archive） |
| `ch` | 在当前目录打开 VS Code |
| `wallpaper` | 下载并设置随机壁纸（见 `Scripts/wallpaper.ps1`） |

## 设计说明

- **避免覆盖系统命令**：`shutdown`/`reboot`/`hibernate`/`suspend` 改用 `ps-` 前缀，`find` 改用别名（`find.exe` 仍可显式调用）。
- **未批准动词规避**：`Edit-Profile`/`Reload-Profile` 改为 `profile-edit`/`profile-reload`，避免 PowerShell 的未批准动词警告。
- **`$LASTEXITCODE` 串联**：`gquick` 在 add/commit 失败时中止，不会盲目 push。
- **缓存原子写入**：所有外部工具 init 缓存（starship/zoxide/fnm）都先写到 `.tmp` 再 Move，校验 `$LASTEXITCODE -eq 0` 且输出非空。
