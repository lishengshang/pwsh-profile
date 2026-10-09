# AGENTS.md — 多 Agent 开发约定

本仓库是 PowerShell 7+ 的模块化 profile（dotfiles 类项目），由多个 agent 会话
（ZCode / Codex / Claude Code / Trae / DeepSeek harness 等混用）并行开发。
任何 agent 在动手前必须读完本文件。本文件是项目约定的唯一事实来源。

## 项目结构

```
Microsoft.PowerShell_profile.ps1   入口：重建 PATH → File.Exists 探测工具 → 按序加载 profile/*.ps1
profile/init-cache.ps1             工具 init 缓存助手（必须最先加载）
profile/env.ps1                    fnm（静态兜底+懒加载）、EDITOR/VISUAL、fzf 配色
profile/prompt.ps1                 starship 提示符（懒加载）
profile/psreadline.ps1             PSReadLine 配置
profile/modules.ps1                zoxide 懒加载；PSCompletions 同步导入 / PSFzf OnIdle
profile/aliases.ps1                全部别名与函数
profile/startup.ps1                启动信息
setup.ps1                          一键安装（链接 + winget 工具 + Install-Module；-Minimal/-Full/-Components）
bootstrap.ps1                      全新系统引导（装 pwsh/git → 克隆 → setup）
starship.toml / lazygit/ / yazi/   外部配置，SkipIfExists 链接到各自配置目录（详见 Scripts/Get-ManagedLinks.ps1）
nvim/                              LazyVim 配置（链接到 $env:LOCALAPPDATA\nvim）
Scripts/                           Get-ManagedLinks（链接清单唯一事实来源）· LinkRegistry（注册表读写/自愈/锁）
                                   Deploy-ConfigLinks（部署循环，供 Pester 测试）· Repair-ConfigLinks（断链修复）
                                   Invoke-SetupWizard（向导）· Compare-PsaBaseline · Check-CommitMsg · wallpaper
tests/                             Pester 套件       .github/workflows/ci.yml  CI（解析/幂等/冒烟/Pester/PSA/规范）
docs/                              usage 速查 · reference 参考 · faq      TODO.md  长期维护事项
```

**nvim/ 约定**：只入库配置声明（lua/、lazyvim.json、lazy-lock.json）；插件本体、
Mason LSP、treesitter 产物在各设备 `$env:LOCALAPPDATA\nvim-data` 自动重建，不碰它们。
改插件/键位 = 改 `nvim/` 内文件并提交，其他设备 `psync` 后重开 nvim 对齐。

## 硬性约定（改代码时必须遵守）

1. **启动性能红线**：profile 启动必须保持在几百毫秒内。禁止在启动路径同步
   `Import-Module` 重量级模块——参照现有做法：懒加载（`modules.ps1`）、延迟到首次调用
   （`aliases.ps1` 的 `__Ensure-TerminalIcons`）、缓存（`init-cache.ps1`）。新工具探测
   一律走入口文件的 `File.Exists` 循环，不要用 `Get-Command`。
   例外：PSCompletions 官方要求全局作用域直接导入（禁止嵌套 `Import-Module`），
   但 v7.3.0 起模块内置懒初始化（首次按 Tab 才加载重活），同步导入已很轻，
   勿再自己包一层 OnIdle。
2. **三处同步**：新增/移除外部工具时，以下三处必须同时改，缺一不可：
   - `setup.ps1` 的 `$wingetTools` 列表（**并标注 `Component`**，决定它属于哪个安装组件）
   - `docs/reference.md` 的「组件」小节与「依赖工具」表
   - 若 profile 需要探测：入口文件的工具名循环
   外部配置（starship/lazygit/yazi/nvim）的组件归属在 `Scripts/Get-ManagedLinks.ps1` 的 `Component` 字段

   新增命令别名/函数时同步更新 `docs/usage.md` 使用速查表（README 的「快速上手」只保留高频子集）。
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
4. **兼容性**：PowerShell 7+ 是主力支持版本；Windows PowerShell 5.1
   为兼容模式（降级加载，setup/bootstrap/向导全链路 5.1 可运行）。因此
   所有脚本必须保持 5.1 可解析：禁用 `?.` / `??` / 三元等 PS7 新语法；
   `.ps1` 一律保存为 UTF-8 **带 BOM**（无 BOM 时 5.1 按 ANSI/GBK 误读，
   中文注释会破坏解析）；可选依赖缺失时优雅降级。
5. **`setup.ps1` 幂等**：已安装的工具/模块、已存在的链接必须跳过，重复运行无副作用。
6. **注释**：中文，只写代码看不出来的**原因**（隐藏约束、微妙不变量、针对具体 bug
   的绕行）；删掉不困惑读者的注释就别写。禁止三种写法：修复日志式（`# ✅ 修复：改成 X`）、
   个人/会话标记（`# ponytail:`、`# added for issue #123`）、随 diff 腐烂的指代
   （`本次改动` / `见 issue N`；同文件内可写「上方/下方」，跨文件必须写文件名）。
   交叉引用必须指向真实位置（`docs/reference.md`「依赖工具」表，而不是已删除的
   `README` 里那个「设计说明」小节）——`Scripts/Check-CommitMsg.ps1 -CheckRefs` 会拦失效项。
7. **命名与文件头**：参数 PascalCase、局部变量 camelCase（禁 `$API_URL` 式全大写）；
   面向用户的命令用短小写名（`gs` / `psync` / `hashcheck`），脚本与内部函数用
   `Verb-Noun`（`__` 前缀 = profile 私有，不写进 `docs/usage.md`）。丢弃输出统一
   `| Out-Null` / `$null =`，不写裸 `> $null`（cmd 下会生成字面量 `$null` 文件）；
   只有需要吞掉非成功流时才 `*> $null` 并注释说明原因。
   入口脚本（可被 `-File` / `&` 直接执行的）用 comment-based help 作文件头，且
   **帮助块必须是文件第一项**——前面有任何注释（含 `#Requires -Version 5.1`）都会让
   `Get-Help` / `-?` 读不到整块，变成死文档；顺序为 帮助块 → `#Requires`（守卫仍生效）
   → `[CmdletBinding()]` → `param()`。被 dot-source 的片段（`profile/*.ps1`、
   `LinkRegistry.ps1`）用 `# ====` 横幅头说明职责，不写 `.SYNOPSIS`。分节一律
   `# ===== 小节名 =====`。帮助文本单源：`-h` 走 `Get-Help $PSCommandPath`，不要手写
   一份 usage；参数说明只写一处（comment-based help 或 docs/reference.md 表格二选一）。
8. **commit message**：Conventional Commits，type 英文、正文中文。
   ```
   <type>(<scope>)?: <中文一句话，≤ 60 列，无句号>

   <正文：为什么这么改、关键取舍、影响面；每行 ≤ 72 列（中文按 2 计）>
   ```
   type ∈ `feat` `fix` `docs` `refactor` `perf` `test` `chore` `ci` `build` `revert`；
   目录/模块写进 scope（`fix(profile):`），不要发明中文 type 或把 `profile:` 当 type。
   subject 不要用 `——` / `；` 塞多段内容（历史最长 228 列，`git log --oneline` 全截断）。
   一次提交只做一件事；合并提交沿用 git 默认文案。
   校验 `pwsh -File Scripts\Check-CommitMsg.ps1 -Range origin/main..HEAD`；
   本地强制（可选）`git config core.hooksPath .githooks`。

## 多 agent 工作流

- **一任务一分支**：分支名 `<type>/<slug>`，如 `feat/yazi-keybinds`、`fix/readme-font-id`、
  `docs/usage`。不要在 main 上直接开发。
- **避免撞车**：动手前先 `git log --oneline -5` + `git status` 了解当前状态。
  `profile/aliases.ps1` 和 `README.md` 是撞车热点，改动尽量小而聚焦，不重排无关内容，
  不做与任务无关的格式化。
- **提交前验证**（必做，与 CI 一一对应）：
  ```powershell
  pwsh -NoProfile -Command ". $PROFILE; <冒烟验证本次改动引入的函数/别名>"
  pwsh -NoProfile -File setup.ps1 -SkipTools        # 语法与链接逻辑不报错
  pwsh -NoProfile -Command "Invoke-Pester tests"     # 改了 Scripts/ 链接链路必跑
  pwsh -NoProfile -File Scripts\Check-CommitMsg.ps1 -Range origin/main..HEAD  # 提交信息 + 引用真实性
  ```
  最后一项在本地与 CI 都跑；PSA 违规门禁见 `Scripts/Compare-PsaBaseline.ps1`
  （与基线提交比对，只拦新增违规，存量放行）。
- **不自动 commit/push**：除非用户明确要求。改动完成后报告改了什么、验证结果如何。
- **有冲突先停**：发现工作区有他人未提交的改动时不要覆盖，先向用户说明。

## 本机（用户日常机）注意点

- 仓库目录即 `$PROFILE` 目录，`setup.ps1` 会自动跳过文件链接——在这台机器上改
  profile 文件即时生效，新开终端即可验证。
- `7z` 在本机实际是 NanaZip（商店版），代码里对 7z 的判断以 PATH 探测为准，
  不要假设版本。
