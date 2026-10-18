# 配置参考

本文定义安装选择、依赖、环境开关及配置管理边界。安装步骤见[项目首页](../README.md)，日常命令见[使用速查](usage.md)，文档分工见[文档导航](README.md)。

## 组件

`setup.ps1` 按组件决定本轮安装的工具、模块及首次部署的外部配置。Core 条目始终部署，包括 profile 入口、`profile/`、`Scripts/`，以及仅 PowerShell 7 使用的 `powershell.config.json`。

组件选择不负责卸载工具、删除既有配置或关闭已安装功能。运行时按实际可用工具探测；未选择的组件如果以前已安装，其功能仍可能生效。安装结束时还会检查历史登记的受管目标，处理方式见[配置保护与修复](#配置保护与修复)。

| 组件 | 工具与模块 | 外部配置 |
|---|---|---|
| `core` | Starship、eza、zoxide、ripgrep、fd、bat、7-Zip、fnm、Terminal-Icons | `starship.toml` |
| `completion` | fzf、PSCompletions、PSFzf | 无 |
| `editor` | Neovim、WinLibs gcc | `nvim/`，基于 LazyVim |
| `files` | Yazi、ffmpeg、jq、poppler、ImageMagick | `yazi/theme.toml`；另安装 Solarized flavor |
| `gitui` | lazygit | `lazygit/config.yml` |

预设：Minimal = `core`；Standard = `core,completion,gitui`；Full = 全部。没有显式组件参数时，交互终端默认进入向导；非交互运行或指定 `-Yes` 时使用 Standard。向导允许不选组件，此时只部署 Core 条目。

### 参数一览

以下参数属于 `setup.ps1`；bootstrap 的专用参数以 `Get-Help .\bootstrap.ps1 -Detailed` 为准。

| 参数 | 作用与限制 |
|---|---|
| `-Minimal` / `-Full` | 选择预设；两者互斥 |
| `-Components core,gitui` | 显式组件集合，优先于预设；未知项告警并忽略，全部无效时报错 |
| `-SkipComponents gitui` | 从当前选择中剔除；仅传此参数时以 Standard 为基础，剔空时报错 |
| `-ExcludeTools fnm,ffmpeg` | 按工具清单的 Name 排除本轮安装；不排除模块、配置，也不卸载已有工具 |
| `-Yes` | 跳过默认向导；不改变组件预设 |
| `-Wizard` | 没有显式组件选择时强制进入向导，优先于 `-Yes`；不覆盖显式组件参数 |
| `-SkipTools` | 跳过工具、模块与 flavor 下载；仍部署配置和检查历史链接 |

多值参数推荐逗号分隔，兼容 `pwsh -File`；在 PowerShell 会话中调用脚本也可传字符串数组。不要写成 `-Components core gitui`，它会因多余的位置参数而报错。

```powershell
.\setup.ps1 -Components core,gitui -Yes
.\setup.ps1 -Full -SkipComponents editor -Yes
.\setup.ps1 -Wizard -SkipTools
```

向导取消会在部署与下载之前结束。bootstrap 的 setup 子进程非零退出时，引导报错并停止，不显示“引导完成”；可选工具安装失败可能只产生告警，完成提示不代表每项可选依赖都已安装成功。

## 依赖工具

PowerShell 7+ 提供完整体验；Windows PowerShell 5.1 提供兼容模式。Git 用于克隆与同步，bootstrap 可安装它。其余工具和模块均可选，缺失行为如下。

| 工具及 winget ID | 组件 | 用途 | 缺失行为 |
|---|---|---|---|
| Starship（`Starship.Starship`） | core | 提示符 | 无可用初始化时使用默认提示符 |
| eza（`eza-community.eza`） | core | 文件列表 | 列表函数使用 `Get-ChildItem` |
| zoxide（`ajeetdsouza.zoxide`） | core | 智能跳转 | 不创建 `z` / `zi`，请使用 `cd` |
| ripgrep（`BurntSushi.ripgrep.MSVC`） | core | 内容搜索 | 优先保留已有 `grep`；否则使用 `Select-String` |
| fd（`sharkdp.fd`） | core | 文件查找 | 不创建 `find` 别名；系统 `find.exe` 是文本搜索工具，语义不同 |
| bat（`sharkdp.bat`） | core | 文件高亮 | 保留 `cat` 对 `Get-Content` 的内置别名 |
| 7-Zip（`7zip.7zip`） | core | 解压 | `unzip` 使用 `Expand-Archive`，仅支持 ZIP |
| fnm（`Schniz.fnm`） | core | Node.js 版本管理 | 不创建其占位函数，命令由系统 PATH 决定 |
| fzf（`junegunn.fzf`） | completion | 模糊查找 | 不启用 PSFzf 快捷键 |
| Neovim（`Neovim.Neovim`） | editor | 编辑器 | 不自动将 `$EDITOR` 设置为 nvim |
| WinLibs gcc（`BrechtSanders.WinLibs.POSIX.UCRT`） | editor | treesitter 编译器 | 相关编译功能需自行提供可用编译器 |
| Yazi（`sxyazi.yazi`） | files | 文件管理器 | 不创建 `y` |
| ffmpeg（`Gyan.FFmpeg`） | files | 视频缩略图 | 对应预览能力不可用 |
| jq（`jqlang.jq`） | files | JSON 预览 | 对应预览能力受限 |
| poppler（`oschwartz10612.Poppler`） | files | PDF 预览 | 对应预览能力不可用 |
| ImageMagick（`ImageMagick.ImageMagick`） | files | 图像与字体预览 | 对应预览能力受限 |
| lazygit（`JesseDuffield.lazygit`） | gitui | Git 界面 | 不创建 `lg` |
| Terminal-Icons（`Install-Module`） | core | 内置列表图标 | 使用普通列表 |
| PSCompletions（`Install-Module`） | completion | 命令补全 | `psc` 提示安装或重开终端 |
| PSFzf（`Install-Module`） | completion | fzf 交互集成 | 对应快捷键不可用 |

`7z` 按 PATH 中实际可执行文件探测，可以来自 NanaZip 等兼容实现；安装清单中的 7-Zip 是新机器的默认安装选项。Git、VS Code 等仍可由用户自行安装。

## 配置路径与链接模式

profile 安装目录以运行时 `$PROFILE` 为准，不假设 Documents 的固定位置。仓库恰好位于该目录时，Core 条目跳过自链接；外部配置仍按组件处理。

| 仓库源 | 默认目标 |
|---|---|
| `starship.toml` | `$HOME\.config\starship.toml` |
| `lazygit/config.yml` | `$env:APPDATA\lazygit\config.yml` |
| `yazi/theme.toml` | `$env:APPDATA\yazi\config\theme.toml` |
| `nvim/` | `$env:LOCALAPPDATA\nvim` |

路径与组件归属由 `Scripts/Get-ManagedLinks.ps1` 统一维护。外部配置首次部署采用 SkipIfExists：未受本仓库管理的现有目标保留，不强制接管。

| 模式 | 适用对象与条件 | 同步行为 |
|---|---|---|
| SymbolicLink | 文件或目录；需可用符号链接权限 | 指向仓库源路径，通常实时生效 |
| Junction | 本地目录；符号链接不可用时回退 | 目录内容随仓库变化 |
| HardLink | 同卷文件；符号链接不可用时回退 | 共享文件内容，但 git 或编辑器原子替换后可能失联 |
| Copy | 文件；链接均不可用时回退 | 不实时同步，修复时按哈希刷新 |
| CopyDirectory | 目录；链接均不可用时回退 | 不实时同步，修复时使用 robocopy `/MIR` 镜像 |

`CopyDirectory` 是仓库源的镜像：刷新会删除目标侧多出的文件。不要把个人文件或运行时产物存入受管镜像目录；需要独立配置时先自行完整备份，再停止该目标的管理。

## 配置保护与修复

链接注册表位于 `$env:LOCALAPPDATA\pwsh-profile\linked-targets.json`，记录 Target、Source、LinkType。它是本机状态，不入库。`psync` 拉取成功及 setup 部署结束后自动执行 `Scripts/Repair-ConfigLinks.ps1`。

- 未登记目标不由 Repair 接管。已登记目标缺失或链接失效时，按原类型恢复；原类型不可用时降级为副本并更新登记。
- 原链接被普通目录替代，或被改成指向别处的有效链接时，保留目标并告警。旧登记保留，等待用户处理冲突，重复运行不会递归删除该目录。
- 失联文件与源内容不同时，重建链接前保留原文件副本；Copy 内容不同时也先备份。备份失败会跳过该项，不继续替换。
- 冲突备份位于原文件同目录，命名为 `<文件名>.conflict-<时间戳>-<随机标识>`，不自动清理。确认内容后手动归档或删除；恢复步骤见[常见问题](faq.md#修复提示配置冲突或生成-conflict-文件怎么办)。
- 每项修复失败会告警并继续处理其余目标。配置同步提示仅代表 Git 拉取成功，不能代替检查修复告警。

setup 接管 Core 条目的旧配置时按需生成 `backup-<yyyyMMdd-HHmmss>` 目录，仅保留最近 3 份严格匹配名称的备份；其他命名不自动清理。重要备份应另行归档。

注册表损坏自愈及副本登记丢失的边界见[常见问题](faq.md#链接注册表损坏或丢失了怎么办)。

## 环境变量开关

开关在加载 profile 前设置，非空字符串即启用，字符串 `0` 也会启用。关闭开关应移除变量；运行期修改后通常需重新加载或新开终端。

| 变量 | 作用 |
|---|---|
| `PROFILE_QUIET` | 关闭问候与总耗时显示，不屏蔽诊断和所有依赖输出 |
| `PROFILE_NO_TIME` | 关闭总耗时显示 |
| `PROFILE_NO_STARTUP` | 关闭启动问候与速查信息 |
| `PROFILE_NO_COMPLETIONS` | 跳过 PSCompletions 导入，不关闭 PSFzf |
| `PROFILE_NO_FZF_TAB` | 不启用 PSFzf 的 TabExpansion，不关闭其其他快捷键 |
| `PROFILE_NO_FNM` | 跳过 fnm 初始化，node/npm 等由系统 PATH 解析 |
| `PROFILE_KEEP_PARENT_PATH` | 保留父进程 PATH，避免丢弃 IDE、虚拟环境等注入的路径 |
| `PROFILE_DEBUG` | 输出模块耗时及加载失败信息 |
| `PWSH_PROFILE_QUIET` | 关闭 5.1 下“已安装 PowerShell 7”的兼容提示 |

```powershell
$env:PROFILE_KEEP_PARENT_PATH = '1'
. $PROFILE
Remove-Item Env:PROFILE_KEEP_PARENT_PATH
```

输出重定向或无用户会话时，默认不显示问候与耗时；未重定向的 `pwsh -Command` 仍可能显示。默认启动会从 Windows 注册表重建 PATH。fnm、fzf、Yazi 等环境设置另见对应脚本；`EDITOR`、`FZF_DEFAULT_OPTS`、`YAZI_FILE_ONE` 已有设置优先保留。

## 加载与补全边界

Starship 初始化延迟到首次提示符，zoxide 延迟到首次 `z` / `zi`，fnm 延迟到首次 node/npm/npx/corepack。Starship 与 zoxide 初始化脚本使用 7 天缓存，工具修改时间更新时失效；fnm 输出包含进程独立路径，不跨会话缓存。

PSReadLine 提供编辑、历史搜索与基础 Tab 绑定；PSCompletions 在顶层导入；PSFzf 在首次空闲时导入，并可设置自己的 TabExpansion。多个组件均可能设置 Tab，实际效果取决于模块版本与初始化顺序；本项目尚未统一这部分职责。排障见[常见问题](faq.md#tab-补全或-fzf-快捷键不符合预期)。

显示的 `Profile loaded in ...` 从工具探测前开始计时，不包含前面的仓库发现、PATH 重建，也不包含首次提示符和空闲加载。性能验收方法见[维护与验证](maintenance.md#启动性能与交互验收)。

## 仓库结构与定制

逐文件职责和开发约束见 [AGENTS.md](../AGENTS.md)。Neovim 只管理配置声明与 `nvim/lazy-lock.json`；插件本体、Mason LSP、treesitter 产物在各设备的 `nvim-data` 中重建，不纳入本仓库。

深入定制可查各工具官方文档：[Starship](https://starship.rs)、[PSFzf](https://github.com/kelleyma49/PSFzf)、[PSCompletions](https://github.com/abgox/PSCompletions)、[LazyVim](https://www.lazyvim.org/)、[Yazi](https://yazi-rs.github.io/)。
