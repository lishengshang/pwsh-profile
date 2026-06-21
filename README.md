# PowerShell Profile

模块化的 PowerShell 7 配置，采用类 XDG 的分文件结构，集成现代命令行工具（eza / zoxide / starship / fzf 等）。

## 目录结构

```
PowerShell/
├── Microsoft.PowerShell_profile.ps1   # 入口：按顺序加载各模块
├── profile/
│   ├── env.ps1          # 环境初始化（fnm、scoop）
│   ├── prompt.ps1       # starship 提示符（带缓存）
│   ├── psreadline.ps1   # PSReadLine 配置（预测、配色、快捷键）
│   ├── modules.ps1      # 模块加载（zoxide、PSCompletions、PSFzf）
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
   scoop install starship eza zoxide fzf fd ripgrep bat 7zip fnm
   ```

4. 重新打开 PowerShell 或执行 `. $PROFILE`。

## 依赖工具

| 工具 | 用途 | 替代的命令 |
|---|---|---|
| starship | 提示符 | 默认 prompt |
| eza | 文件列表（图标 + git） | `ls` / `ll` / `la` / `lt` |
| zoxide | 智能目录跳转 | `cd` / `z` |
| fzf + PSFzf | 模糊查找（Ctrl+t / Ctrl+r） | — |
| fd | 文件查找 | `find` |
| ripgrep | 内容搜索 | `grep` |
| bat | 查看文件（高亮） | `cat` |
| 7zip | 解压 | `unzip` |
| fnm | Node 版本管理 | — |
| PSCompletions | 命令补全（git / scoop / winget 等） | — |

部分工具缺失时会自动回退到 PowerShell 内置命令。

## 常用别名与函数

| 命令 | 说明 |
|---|---|
| `rp` | 重新加载 profile |
| `ep` | 用 VS Code 编辑 profile |
| `..` / `...` / `....` | 向上跳目录 |
| `mkcd <dir>` | 新建目录并进入 |
| `gs` / `ga` / `gcm` / `gp` / `gl` | Git 快捷命令 |
| `gquick <msg>` | add + commit + push 一条龙 |
| `myip` | 查询公网 IP |
| `portof <port>` / `killport <port>` | 查询 / 终止占用端口的进程 |
| `reboot` / `shutdown` / `lock` | 系统电源管理 |

## 启动耗时

入口文件会打印各模块加载耗时，便于排查启动慢的模块。
