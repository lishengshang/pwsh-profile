# AGENTS.md — 多 Agent 开发约定

本仓库是 PowerShell 7+ 的模块化 profile（dotfiles 类项目），由多个 agent 会话
（ZCode / Codex / Claude Code / Trae / DeepSeek harness 等混用）并行开发。
任何 agent 在动手前必须读完本文件。本文件是项目约定的唯一事实来源。

## 项目结构

```
Microsoft.PowerShell_profile.ps1   入口：重建 PATH → File.Exists 探测工具 → 按序加载 profile/*.ps1
profile/init-cache.ps1             工具 init 缓存（必须最先加载）
profile/env.ps1                    fnm 缓存、EDITOR/VISUAL、fzf 配色
profile/prompt.ps1                 starship 提示符（懒加载）
profile/psreadline.ps1             PSReadLine 配置
profile/modules.ps1                zoxide 懒加载；PSCompletions / PSFzf
profile/aliases.ps1                全部别名与函数
profile/startup.ps1                启动信息
setup.ps1                          一键安装（符号链接 + winget 工具 + Install-Module；支持 -Minimal/-Full/-Components 组件级选择）
bootstrap.ps1                      全新系统引导（装 pwsh/git → 克隆 → setup）
starship.toml                      提示符主题（SkipIfExists 链接到 ~/.config/）
lazygit/config.yml                 lazygit 主题 Solarized Dark（链接到 %APPDATA%\lazygit\）
yazi/theme.toml                    yazi 主题（链接到 %APPDATA%\yazi\config\，flavor 每设备装不入库）
nvim/                              LazyVim 配置（链接到 $env:LOCALAPPDATA\nvim）
Scripts/                           独立脚本（wallpaper.ps1、Get-ManagedLinks.ps1、LinkRegistry.ps1、Repair-ConfigLinks.ps1）
windows-terminal/                  终端配色与说明
```

**nvim/ 约定**：只入库配置声明（lua/、lazyvim.json、lazy-lock.json）；插件本体、
Mason LSP、treesitter 产物在各设备 `$env:LOCALAPPDATA\nvim-data` 自动重建，不碰它们。
改插件/键位 = 改 `nvim/` 内文件并提交，其他设备 `psync` 后重开 nvim 对齐。

## 硬性约定（改代码时必须遵守）

1. **启动性能红线**：profile 启动必须保持在几百毫秒内。禁止在启动路径同步
   `Import-Module` 重量级模块——参照现有做法：懒加载（`modules.ps1`）、延迟到首次调用
   （`aliases.ps1` 的 `__Ensure-TerminalIcons`）、缓存（`init-cache.ps1`）。新工具探测
   一律走入口文件的 `File.Exists` 循环，不要用 `Get-Command`。
2. **三处同步**：新增/移除外部工具时，以下三处必须同时改，缺一不可：
   - `setup.ps1` 的 `$wingetTools` 列表（**并标注 `Component`**，决定它属于哪个安装组件）
   - `README.md` 的「依赖工具」表与「组件级安装选项」小节
   - 若 profile 需要探测：入口文件的工具名循环
   - 外部配置（starship/lazygit/yazi/nvim）的组件归属在 `Scripts/Get-ManagedLinks.ps1` 的 `Component` 字段

   新增命令别名/函数时同步更新 `README.md` 使用速查表。
   全部管理链接（核心 profile 文件 + starship/lazygit/yazi/nvim 外部配置）的清单
   单源维护在 `Scripts/Get-ManagedLinks.ps1`，setup 与修复脚本都引用它，改链接只改
   这一处。链接注册表（%LOCALAPPDATA%\pwsh-profile\linked-targets.json）记录
   Target/Source/LinkType 三元组，Repair 按原类型修复，勿只记路径。
   注意：git pull 和编辑器原子保存会弄断文件类硬链接，`psync`/`setup.ps1`
   结束时会自动调用 `Scripts/Repair-ConfigLinks.ps1` 修复——改动涉及被链接的
   配置文件后，无需手动处理链接。
3. **优雅降级**：所有外部工具都是可选依赖。引用前用
   `$global:__Tools.ContainsKey('<name>')` 判断，缺失时回退内置命令或静默跳过，
   profile 不得因缺工具报错。
4. **兼容性**：仅支持 PowerShell 7+（可用 `??`、`?.` 等语法）。
5. **`setup.ps1` 幂等**：已安装的工具/模块、已存在的链接必须跳过，重复运行无副作用。
6. **风格**：注释和文档用中文；别名简短小写（`gs`/`wup`），函数避免未批准动词；
   commit message 用中文、前缀分类（`profile:` / `setup:` / `docs:` / `修复:` 等，见 git log）。

## 多 agent 工作流

- **一任务一分支**：分支名 `<type>/<slug>`，如 `feat/yazi-keybinds`、`fix/readme-font-id`、
  `docs/usage`。不要在 main 上直接开发。
- **避免撞车**：动手前先 `git log --oneline -5` + `git status` 了解当前状态。
  `profile/aliases.ps1` 和 `README.md` 是撞车热点，改动尽量小而聚焦，不重排无关内容，
  不做与任务无关的格式化。
- **提交前验证**（必做）：
  ```powershell
  pwsh -NoProfile -Command ". $PROFILE; <冒烟验证本次改动引入的函数/别名>"
  pwsh -NoProfile -File setup.ps1 -SkipTools   # 语法与链接逻辑不报错
  ```
- **不自动 commit/push**：除非用户明确要求。改动完成后报告改了什么、验证结果如何。
- **有冲突先停**：发现工作区有他人未提交的改动时不要覆盖，先向用户说明。

## 本机（用户日常机）注意点

- 仓库目录即 `$PROFILE` 目录，`setup.ps1` 会自动跳过文件链接——在这台机器上改
  profile 文件即时生效，新开终端即可验证。
- `7z` 在本机实际是 NanaZip（商店版），代码里对 7z 的判断以 PATH 探测为准，
  不要假设版本。
