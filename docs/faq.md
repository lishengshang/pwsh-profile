# 常见问题

## 一行命令报 `ResourceUnavailable` 或被杀软报毒？

旧版 `irm ... | iex` 形式（绕过执行策略 + 下载即执行）是无文件攻击的典型特征，Defender / 360 / 火绒会在进程创建层拦截——**机器没中毒，拦截前未执行任何代码**。改用 README 里的新版一行命令（先落盘再执行），或先下载人工确认后本地运行。文件已被隔离的，从隔离区恢复 `bootstrap.ps1` 即可。

## 已经装了 pwsh，还需要跑一行引导吗？

不需要，直接 `git clone` + `.\setup.ps1`。误跑也不报错：bootstrap 检测到 pwsh 已存在会跳过安装，用当前实例继续。

## 升级/重装模块后 `psc` 报错（`__need_update_data`、null 调用等）？

旧终端会话残留的旧版 `$PSCompletions` 变量（常量，无法清除）会让新版模块跳过初始化。**新开一个终端**即可；一般规律：任何模块升级后都建议新开终端（`wum` 更新完也会提示）。

## 支持 Windows PowerShell 5.1 吗？

支持，**安装与使用全链路可用**（兼容模式）：`bootstrap.ps1` / `setup.ps1`（含向导）可直接在 5.1 下运行，部署目标按运行时 `$PROFILE` 自动解析到 `Documents\WindowsPowerShell\`，与 PS7 的部署互不影响。边界：

- 脚本语法保持 5.1 可解析（禁用 `?.` / `??`；`.ps1` 一律 UTF-8 带 BOM）。
- 5.1 执行策略默认 Restricted 时，`setup.ps1` 自动将当前用户放开为 RemoteSigned；模块装进 5.1 自己的模块目录。
- 完整体验以 PS7 为准，随时可 `.\bootstrap.ps1` 补装；只想在 5.1 部署：`bootstrap.ps1 -SkipPwsh`。
- 启动提示：纯 5.1 机器默认静默；装了 pwsh 7 却用 `powershell` 启动会轻提一句，`setx PWSH_PROFILE_QUIET 1` 关闭。

## yazi 提示找不到 `file` 做 MIME 检测？

profile 启动时自动探测 Git 自带的 `file.exe` 并设置 `YAZI_FILE_ONE`。确认：`echo $env:YAZI_FILE_ONE` 应指向 Git 目录下 `usr\bin\file.exe`；Git 装在非常规位置探测不到时手动设置该变量。
