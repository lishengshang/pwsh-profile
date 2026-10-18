# 常见问题

本文按症状提供检查与恢复步骤。安装入口见[项目首页](../README.md)，参数和配置保护边界见[配置参考](reference.md)。命令示例默认在仓库根目录执行。

## 引导报 ResourceUnavailable 或被安全软件拦截

先保留完整报错、被拦文件路径和安全软件记录。仅凭一条拦截提示，不能判断脚本是否已部分执行，也不能据此认定机器感染或未感染。

从项目首页确认下载来源，检查落盘的 `bootstrap.ps1` 后再决定如何处理；也可手动克隆仓库并运行 setup。不要将关闭安全防护或直接恢复未知文件作为默认排障步骤。

## 已经安装 PowerShell 7 是否还要运行 bootstrap

不需要。已有 Git 时直接克隆并运行 `.\setup.ps1`。bootstrap 主要服务新机器，会跳过已探测到的工具；仓库目标已存在且不是可识别仓库时，它会提示换目录，不覆盖原目录。

`-SkipPwsh` 只跳过 PowerShell 7 的安装步骤：如果机器已经存在可发现的 pwsh，引导仍优先用它执行 setup。需要明确在 5.1 中部署时，直接在 Windows PowerShell 5.1 中运行 setup。

## 安装失败后如何重试

先区分三类情况：

1. 参数或配置部署错误：处理错误后重跑相同安装命令，检查备份位置。
2. 某个可选工具或模块失败：检查日志中的工具名与错误码，网络恢复后重跑；已有可探测安装会跳过。
3. bootstrap 报 setup 非零退出：安装未完成，不应只重开终端就认为恢复；先处理子进程上方的错误。

```powershell
.\setup.ps1 -Components core,gitui -Yes
```

不要为了排障盲目改用 `-Full`，以免扩大安装范围。`-SkipTools` 仍会部署配置并修复历史目标，不能当成纯检查模式。

## 升级模块后 psc 报错

PSCompletions 等模块可能在旧会话残留初始化状态。先关闭并新开终端，不要仅重复导入。如果仍报错，确认模块位置和版本：

```powershell
Get-Module -ListAvailable PSCompletions,PSFzf,PSReadLine |
    Select-Object Name,Version,Path
```

把新会话中的完整报错与版本一起用于定位。`wum` 会更新已有相关模块，更新后也需要新会话。

## Windows PowerShell 5.1 的兼容范围

安装脚本、向导和 profile 保持 5.1 可解析，按当前进程 `$PROFILE` 部署。5.1 与 PS7 的 profile 安装目录通常不同，但 Starship、lazygit、Yazi、Neovim 等外部配置和本机链接注册表可能共享，不能视为完全隔离。

第三方模块是否提供相同能力取决于其版本与支持范围；本项目不保证 5.1 获得 PS7 的全部补全体验。脚本统一使用 UTF-8 带 BOM，避免 5.1 用系统代码页误读中文。

5.1 的 setup 仅在其策略检查判为默认 Restricted 时尝试设置当前用户 RemoteSigned；组策略仍可能限制执行。先查看实际策略，不要反复覆盖：

```powershell
$PSVersionTable.PSVersion
$PROFILE
Get-ExecutionPolicy -List
```

装了 pwsh 却使用 5.1 时可能显示兼容提示，关闭方式见参考文档的[环境变量开关](reference.md#环境变量开关)。

## Tab 补全或 fzf 快捷键不符合预期

在新开的交互终端中等待空闲初始化，然后查看实际绑定：

```powershell
Get-PSReadLineKeyHandler -Chord Tab,'Ctrl+t','Ctrl+r'
Get-Module PSReadLine,PSCompletions,PSFzf
```

PSReadLine、PSCompletions、PSFzf 都可能影响补全。需要排除 PSFzf TabExpansion 时，在加载前设置 `PROFILE_NO_FZF_TAB=1`；排除 PSCompletions 时设置 `PROFILE_NO_COMPLETIONS=1`。两者职责不同，具体说明见[加载与补全边界](reference.md#加载与补全边界)。

开关非空即启用，设成 `0` 并不会关闭。移除变量后重开终端复查。非交互测试会跳过部分键位设置，不能证明真实终端中的绑定正确。

## Yazi 找不到 file 做 MIME 检测

profile 会探测 Git for Windows 常见安装位置中的 `usr\bin\file.exe`，在未显式设置 `YAZI_FILE_ONE` 时补充它。检查当前结果：

```powershell
$env:YAZI_FILE_ONE
if ($env:YAZI_FILE_ONE) { Test-Path -LiteralPath $env:YAZI_FILE_ONE }
```

Git 位于非常规目录且未被探测到时，找到实际的 `file.exe` 后显式设置该变量，再重开 Yazi。不要将文件名同为 `file.exe` 视为已验证 MIME 检测可用。

## 修复提示配置冲突或生成 conflict 文件怎么办

普通目录替代了历史链接，或者有效链接被用户重新指向别处时，Repair 会保留现状并告警。若要继续使用个人配置，可以保持现状；相关旧登记仍在，后续修复会重复提醒。

若要重新使用仓库配置，先完整备份并将冲突目标移到其他位置，再在仓库中运行：

```powershell
.\Scripts\Repair-ConfigLinks.ps1
```

失联文件或 Copy 文件需要刷新且内容不同时，原内容保存到同目录的 `<文件名>.conflict-<时间戳>-<随机标识>`。这些备份不自动删除。需要恢复时，先比较源、当前目标和备份，决定合并到仓库还是改用独立个人配置，不要把备份直接覆盖到仍共享内容的硬链接上。

CopyDirectory 是按登记管理的目录镜像，仍会清理目标中源不存在的文件。修改目录副本前先完整备份，并阅读[链接模式](reference.md#配置路径与链接模式)。

## 链接注册表损坏或丢失了怎么办

状态文件为 `$env:LOCALAPPDATA\pwsh-profile\linked-targets.json`。建议在重跑 setup 前单独运行修复脚本：JSON 解析失败时会先保存 `.corrupt-<时间戳>` 副本，再按链接清单与磁盘证据重建。

重建只认领有证据的 SymbolicLink、Junction、HardLink；普通副本不能仅因内容相同就被认领。注册表丢失时也不能自动恢复 Copy/CopyDirectory 的归属。外部目标仍存在时，setup 的 SkipIfExists 可能继续保留它，不能保证重跑就自动接管。

已确认需要重新管理副本时，先自行完整备份并移走目标，再按原组件运行 setup。setup 部署阶段可能先写入登记，因此不要把“setup 结束时会修复”当作任何损坏状态都必然已保留原注册表的保证。

## 加载变慢或 IDE 中找不到工具

先打开诊断加载，查看各模块耗时及错误：

```powershell
$env:PROFILE_DEBUG = '1'
. $PROFILE
Remove-Item Env:PROFILE_DEBUG
```

重复加载是定位手段，不能当作冷启动性能数据。首次提示符、第一次智能跳转及第一次 Node 调用还会有延迟初始化，计时范围见[启动性能与交互验收](maintenance.md#启动性能与交互验收)。

默认 profile 从 Windows 注册表重建 PATH，可能丢弃 IDE 或虚拟环境注入的路径。确需保留父进程 PATH 时，在加载 profile 前启用 `PROFILE_KEEP_PARENT_PATH`，再检查工具路径；不要只因一次未找到命令就重装工具。
