# 使用速查

全部别名与函数。工具缺失时自动回退内置命令（回退明细见[配置参考](reference.md#依赖工具)）。

## 文件与导航

| 命令 | 说明 |
|---|---|
| `ls` / `ll` / `la` / `lt` / `llt` | eza 图标列表 / 长格式+git / 长格式+隐藏+git / 树形 / 长格式+树形+git（eza 缺失时回退 `Get-ChildItem`） |
| `..` / `...` / `....` | 向上跳 1/2/3 级目录 |
| `mkcd <dir>` | 新建目录并进入 |
| `z <目录>` | zoxide 智能目录跳转（缺失时回退 `cd`） |
| `y` | yazi 文件管理器（退出时 cd 到最后浏览的目录） |
| `lg` | lazygit 终端 git UI（LazyVim 内 `<leader>gg` 调起浮窗） |
| `cat` / `grep` / `find` | bat / ripgrep / fd（缺失时依次回退内置命令；`find.exe` 仍可显式调用） |
| `touch <file>` / `which <cmd>` / `unzip <file>` | 新建文件 / 查命令路径 / 7z 解压 |

## Git

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

## 系统与网络

| 命令 | 说明 |
|---|---|
| `myip` | 查询公网 IP（多 API 备用链） |
| `wup` | winget 一键升级全部已安装工具 |
| `wum` | 一键更新 PSGallery 模块（PSCompletions/PSFzf 等；更新后需新开终端） |
| `portof <port>` / `killport <port>` | 查询占用端口的进程 / 终止它（支持 `-WhatIf` 预览、`-Confirm` 确认） |
| `ps-reboot [delay]` / `ps-shutdown [delay]` | 重启 / 关机（不覆盖系统 `shutdown.exe`） |
| `ps-hibernate` / `ps-suspend` / `lock` | 休眠 / 睡眠 / 锁屏 |

## 编辑器与配置

| 命令 | 说明 |
|---|---|
| `ep` | 用 VS Code 编辑 profile（未装 VS Code 时回退 `$EDITOR`） |
| `ch` | 在当前目录打开 VS Code（回退 `$EDITOR`） |
| `wallpaper` | 下载并设置随机壁纸（见 `Scripts/wallpaper.ps1`；超分依赖 waifu2x 需手动装，缺失时自动用原图） |

## 多设备同步

仓库管理的四份外部配置（starship / lazygit / yazi / LazyVim）决定了「改一处、全设备一致」：

- **日常同步**：一台设备改配置 → commit/push → 其他设备 `psync` → 重开终端 / nvim 生效。
- **加 Neovim 插件**：在 `nvim/lua/plugins/` 新建 `.lua` → push → 其他设备 `psync` 后重开 nvim，lazy.nvim 自动安装；插件版本由 `nvim/lazy-lock.json` 锁定对齐。
- **每设备本地生成、不入库**：插件本体、Mason LSP、treesitter 产物——首次打开 nvim 按仓库声明自动重建。
- **链接自愈**：git 的原子写入会弄断文件类硬链接，`psync` / `setup.ps1` 会自动重链（`Scripts/Repair-ConfigLinks.ps1`）；只修复 setup 创建过的链接，你自己的存量配置不会被碰。
- **输入法自动切换**（`nvim/lua/plugins/ime.lua`）：进插入模式自动切中文、退出切英文；改过系统中/英切换键的话同步改文件里的 `switch_key`。
