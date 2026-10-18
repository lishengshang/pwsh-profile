# 使用速查

本文列出用户命令与日常操作。先完成[安装](../README.md#安装)并重开终端；命令是否创建及缺失依赖时的行为，以[依赖工具](reference.md#依赖工具)为准。安装参数见[配置参考](reference.md#参数一览)。

## 文件与导航

| 命令 | 说明 |
|---|---|
| `ls` / `ll` / `la` / `lt` / `llt` | eza 图标列表 / 长格式与 Git 状态 / 含隐藏项的长格式 / 两层树形 / 含 Git 状态的长格式树形；缺失时使用内置列表 |
| `..` / `...` / `....` | 向上跳 1 / 2 / 3 级目录 |
| `mkcd <dir>` | 新建目录并进入 |
| `z <目录>` / `zi` | zoxide 智能跳转 / 交互选择；缺失时请使用 `cd` |
| `y` | 打开 Yazi，退出后进入最后浏览的目录 |
| `lg` | 打开 lazygit；LazyVim 中也可通过 `<leader>gg` 调用 |
| `cat` / `grep` / `find` | 优先使用 bat / ripgrep / fd；参数语义随实际工具变化，不能视为内置命令的完全替代 |
| `touch <file>` | 文件不存在时创建，已存在时只更新时间戳，不清空内容；多个路径使用数组传入 |
| `which <cmd>` | 显示外部命令路径、别名目标或函数来源 |
| `unzip <file>` | 使用 PATH 中的 `7z` 解压到当前目录；缺失时仅支持 ZIP |
| `hashcheck <file> [期望哈希]` | 按期望值长度识别算法并比较；无期望值时计算 SHA256 并复制到剪贴板，`-Algorithm` 可指定算法 |
| `hashadd <file...> [-Algorithm md5]` | 为匹配文件生成 GNU 格式旁挂校验文件；多个路径使用数组传入，默认 SHA256，支持通配符 |

`hashcheck` 的自动识别长度为 MD5 32、SHA1 40、SHA256 64、SHA384 96、SHA512 128。它用于人工核验文件，输出匹配结果，不作为依靠退出码判断结果的自动化接口。

```powershell
touch -Path 'notes.txt','draft.txt'
hashadd -Path '.\*.zip' -Algorithm SHA256
hashcheck '.\package.zip' '<期望的 SHA256 值>'
```

`7z` 解压会允许覆盖同名文件；`Expand-Archive` 降级也使用覆盖模式。请先确认当前目录。`find.exe` 始终可显式调用，但它是 Windows 文本搜索工具，与 fd 的文件查找功能不同。

## Git

| 命令 | 说明 |
|---|---|
| `gs` / `ga` / `gaa` | status / add / add --all |
| `gpl` / `gup` | pull / pull --rebase |
| `glog` | 带图形、日期和作者的日志 |
| `gd` / `gds` | 工作区差异 / 暂存区差异 |
| `gco` / `gb` / `gbn` | checkout / branch / 当前分支名 |
| `gst` / `grs` | stash / restore |
| `gclean` | 删除已合并到当前分支的本地分支；保留当前分支及名称中含 main/master/dev/develop 保护词的分支，支持 `-WhatIf` / `-Confirm` |
| `gquick <msg> [-Push]` | add --all → commit；失败即停止，只有指定 `-Push` 才推送 |

Git 命令需要已安装 Git。`gquick` 会暂存未跟踪文件，执行前先用 `gs` 和 `gd` 检查范围；在本仓库中提交信息还需遵守 [AGENTS.md](../AGENTS.md)。`grs` 会丢弃相应工作区修改，执行前确认目标。

不提供 `gcm` / `gc` / `gp` / `gl` / `gcb`：这些名字与 PowerShell 内置别名冲突。请直接使用 `git commit`、`git push`、`git checkout -b`，或使用 `gquick`。

## 系统与网络

| 命令 | 说明 |
|---|---|
| `myip` | 查询公网 IP，逐个尝试备用 API |
| `wup` | 用 winget 升级全部可升级的已安装工具，包括本仓库以外的工具 |
| `wum` | 更新已安装的 PSCompletions、PSFzf、Terminal-Icons；完成后重开终端 |
| `portof <port>` | 查询 TCP 端口关联进程 |
| `killport <port>` | 终止 TCP 端口关联进程，支持 `-WhatIf` / `-Confirm` |
| `ps-reboot [delay]` / `ps-shutdown [delay]` | 重启 / 关机，延迟单位为秒 |
| `ps-hibernate` / `ps-suspend` / `lock` | 调用系统休眠 / 挂起 / 锁屏接口；实际电源状态取决于系统能力与设置 |

先用 `killport 3000 -WhatIf` 或 `gclean -WhatIf` 预览有影响的操作。系统电源命令不属于常规冒烟测试，不要为了验证命令存在而实际调用。

## 编辑器与补全

| 命令或按键 | 说明 |
|---|---|
| `ep` | 编辑当前 `$PROFILE`，优先 VS Code，缺失时使用 `$EDITOR` |
| `ch` | 在当前目录打开 VS Code，缺失时使用 `$EDITOR` |
| `psc` | PSCompletions 管理入口；模块未加载时显示指引 |
| `Ctrl+t` / `Ctrl+r` / `Ctrl+g` 前缀 | PSFzf 文件选择 / 历史搜索 / Git 选择，需要 fzf 与 PSFzf 成功初始化 |
| `wallpaper` | 下载并设置壁纸；waifu2x 超分工具需自行安装，缺失时默认使用原图 |

`EDITOR` 含空格的可执行路径需用双引号包裹；复杂的参数引用建议放进独立 wrapper 脚本。wallpaper 参数以 `Get-Help .\Scripts\wallpaper.ps1 -Detailed` 为准。Tab 的组件关系与关闭开关见[补全边界](reference.md#加载与补全边界)。

## 多设备同步

| 命令 | 说明 |
|---|---|
| `psync` | 在发现的 profile 仓库中执行 git pull --rebase，成功后检查并修复已登记的配置目标 |

1. 在一台设备修改仓库内的配置，检查差异、验证并提交，然后推送。
2. 在其他设备运行 `psync`，检查 Git 结果及链接修复告警。
3. 重开终端；Neovim 配置变化时重开 nvim，让插件管理器按声明与锁文件对齐。

`psync` 不会推送本地提交，也不能取得尚未推送的其他设备改动。首次创建的功能分支若没有上游，需要先由维护者明确其同步目标。

Neovim 插件声明在 `nvim/lua/plugins/` 中维护；`nvim/lazy-lock.json` 随配置提交。插件本体、Mason LSP、treesitter 产物由各设备重建。输入法切换配置位于 `nvim/lua/plugins/ime.lua`，其中 `switch_key` 需与本机系统设置一致。

外部配置首次部署保留用户已有目标；受管目标以登记及磁盘状态决定修复行为，不保证所有同路径内容永远不变。尤其 CopyDirectory 会镜像删除多余文件，具体限制见[配置保护与修复](reference.md#配置保护与修复)。
