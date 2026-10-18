# 维护与验证

本文说明如何取得可复查的维护证据。开发硬约束、分支和提交规范以 [AGENTS.md](../AGENTS.md) 为准；文档组织方式见[文档导航](README.md)。以下命令默认从仓库根目录运行。

## 开始维护

先查看工作区、近期提交与远端关系。获取远端引用不会替用户合并或推送。

```powershell
git status --short --branch
git log --oneline -5
git fetch origin --prune
git rev-list --left-right --count origin/main...HEAD
```

最后一项左右两列分别是远端独有、本地独有的提交数。工作区干净只说明没有未提交内容，不能证明本地与远端一致。远端 CI 通过也只证明它检查的提交，必须核对 SHA。

维护前按项目约定创建任务分支；遇到他人未提交的改动先协商，不覆盖。提交和推送须有明确授权。长期计划记入 [TODO.md](../TODO.md)，不要把短期排查记录写成永久约束。

## 变更对应的文档

| 变更 | 同步检查 |
|---|---|
| 用户命令、别名或缺失依赖行为 | `usage.md`，必要时更新首页高频命令 |
| 外部工具、模块或组件 | `reference.md`，以及 AGENTS.md 规定的实现清单 |
| 配置路径、链接类型、保护或恢复行为 | `reference.md` 与 `faq.md` |
| 安装参数 | setup 参数更新 `reference.md`；bootstrap 专用参数更新脚本帮助 |
| 开发硬约束 | 修改根目录 AGENTS.md，其他文档只引用 |
| 文档改名或标题重构 | 更新本地链接与注释引用，运行文档门禁 |

## 自动化检查

语法、profile 冒烟、setup 幂等性、Pester、文档漂移、PSA 和提交规范共同构成验证范围，具体 CI 实现在 `.github/workflows/ci.yml`。本地按变更范围运行，不能以单项成功替代其他相关检查。

```powershell
pwsh -NoProfile -File Scripts\Check-DocsDrift.ps1
pwsh -NoProfile -File Scripts\Check-CommitMsg.ps1 -CheckRefs
pwsh -NoProfile -File Scripts\Check-CommitMsg.ps1 -Range origin/main..HEAD
pwsh -NoProfile -File Scripts\Compare-PsaBaseline.ps1 -BaseSha origin/main
```

PSA 对受版本控制的提交差异做增量比对；未提交修改应另行对修改后的文件运行 `Invoke-ScriptAnalyzer` 并采用相同项目豁免。增量门禁通过不等于所有规则均无历史违规。

Pester 需要 5.0 或更新版本。显式导入后取得结果对象，并同时检查测试与容器失败，避免发现阶段错误被当成通过：

```powershell
Import-Module Pester -MinimumVersion 5.0
$config = [PesterConfiguration]::Default
$config.Run.Path = 'tests'
$config.Run.PassThru = $true
$result = Invoke-Pester -Configuration $config
$badContainers = @($result.Containers | Where-Object Result -eq 'Failed')
if ($null -eq $result -or $result.TotalCount -eq 0 -or
    $result.FailedCount -gt 0 -or $badContainers.Count -gt 0) {
    throw 'Pester 检查失败或没有取得有效测试结果'
}
```

报告实际运行的引擎版本、测试数、失败及跳过项。依赖权限而提前返回的测试也应说明未覆盖的分支，不把它算作真实场景已验收。

## 安装与配置保护验收

本机仓库就是日常 profile，运行 setup 会影响本机配置；`-SkipTools` 仅跳过下载。常规安装回归先在测试夹具隔离的目录和子进程中执行，确认没有访问真实用户目标。

```powershell
Invoke-Pester -Path tests\InstallFlow.Tests.ps1,tests\Repair-ConfigLinks.Tests.ps1
```

安装流程应覆盖显式选择与向导选择的一致性、连续安装的状态稳定，以及 bootstrap 的成功和失败出口。链接流程应覆盖各类型的重建、缺失依赖降级、历史登记冲突、文件备份和逐项失败隔离。

提交前仍须按 AGENTS.md 运行真实 profile 冒烟及 `setup.ps1 -SkipTools`，先检查本机目标和备份。冒烟只调用无副作用的功能，重启、关机、杀进程、清理分支及设置壁纸等操作仅检查命令定义或使用明确支持的预览模式。

配置操作失败时验证原内容仍在、备份可读、后续目标继续处理；不能只看警告文本或退出码。CopyDirectory 的 `/MIR` 验收只在可丢弃的隔离目录运行。

## 启动性能与交互验收

分开记录进程启动、完整 profile 加载、首次提示符、首次工具调用和空闲初始化。注明 PowerShell 版本、交互或重定向宿主、外部依赖和缓存是否存在，多次采样后报告范围。

profile 内置耗时从工具探测前开始，不含更早的仓库发现与 PATH 重建。仅查看 `Profile loaded in ...` 不能证明首次可输入时间，也不能证明首次 `z`、Node 或补全响应速度。

在真实终端另行检查 Tab、Ctrl+t、Ctrl+r、Git 选择快捷键、首次提示符、重复加载，以及工具缺失后的行为。PSReadLine 和空闲事件在非交互环境中的路径不同，CI 冒烟不覆盖完整交互体验。

## 交付记录

报告改动目的、可观察行为、验证命令及结果、未覆盖场景和剩余限制。说明当前分支、与远端的关系，以及是否已经提交、推送、创建 PR；未经授权不执行后面这些动作。

文档描述当前行为，待办描述尚未实现的工作；不在使用文档中长期保存“最近一次 CI 全绿”“当前测试全部通过”等会随提交失效的状态。
