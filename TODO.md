# TODO / Roadmap

本文件只记录长期维护事项。临时调试过程、一次性安装问题和具体讨论放在对应的 GitHub Issue 或分支中。

## 优先级说明

- **P0**：阻塞安装、启动、同步或数据安全的问题。
- **P1**：明显功能缺陷、兼容性问题或维护风险。
- **P2**：性能、体验、文档和结构优化。

## P0：阻塞性问题

当前无已知 P0 问题。

## P1：重要改进

当前 P1 全部条目已并入下方「进行中：四阶段维护加固计划」。

## 进行中：四阶段维护加固计划

按阶段推进，每阶段完成后停下确认。已完成阶段 0（仓库卫生：ime.lua 验证提交合并、
过期分支清理）。

- [ ] **阶段 1：测试与 lint 加固**
  - [ ] 提取 setup 链接部署循环为可测试函数（`refactor/extract-link-deploy`，
        新增 `Scripts/Deploy-ConfigLinks.ps1`；`Get-ManagedLinkState` 迁入
        LinkRegistry.ps1；旧 txt 迁移块提取为 `ConvertFrom-LegacyLinkRegistry`）
  - [x] Pester 测试套件：registry 读写 / deploy 幂等与降级 / repair 五类链接
        （`test/link-pester-suite`，CI 仅 pwsh 矩阵作业运行；附带修复断链
        junction 判定跨版本不一致——PS7 下被误备份而非清理）
  - [x] PSScriptAnalyzer 门禁：仅新增违规失败（`ci/psa-baseline`）。
        快照取自基线提交（PR 取目标分支 tip、push 取上一提交）——对变更过的
        .ps1 比较当前与基线版本的按规则计数，新增即失败，存量放行且无需
        入库快照文件；豁免清单在 Scripts/Compare-PsaBaseline.ps1 头部

- [ ] **阶段 2：注册表健壮性**（`feat/registry-hardening`）
  - [ ] 损坏恢复：解析失败先备份 `.corrupt-<时间戳>`，按 manifest 与磁盘状态重建
  - [ ] 并发锁：命名 Mutex 防 setup 与 Repair 同时登记互相覆盖
  - [ ] 备份目录治理：只清理严格 `backup-<yyyyMMdd-HHmmss>` 命名目录，保留最近 3 份

- [ ] **阶段 3：文档防漂移 CI**（`ci/docs-drift-check`）
  - [ ] AST 提取 aliases.ps1 函数与 setup.ps1 winget 清单，CI 校验
        docs/usage.md 与 docs/reference.md 覆盖（代码 ⊆ 文档单向）

## P2：长期优化

- [ ] **明确 PSCompletions、PSFzf 和 PSReadLine 的职责**
  - PSC 导入后 Tab 由其 trigger_key 接管（psreadline 的 MenuComplete 仅在
    PROFILE_NO_COMPLETIONS=1 时生效，见 psreadline.ps1 注释）。
  - 评估默认关闭 PSFzf `TabExpansion`（当前被 PSC 接管后实际不生效），保留
    Ctrl+t/Ctrl+r/Git 快捷键；避免多个组件同时接管 Tab 和补全菜单。

- [ ] **补充链接部署模式文档**
  - 说明 SymbolicLink、Junction、HardLink、Copy、CopyDirectory 的差异。
  - 说明不同模式的同步行为、权限要求和恢复方式。

- [ ] **增加工具版本管理策略**
  - 评估是否维护 PowerShell 模块的版本范围或锁定版本。
  - 评估 winget 工具版本、Yazi flavor 和 LazyVim 的可复现安装方案。

- [ ] **拆分可选个人功能**
  - 评估将 Wallpaper、LazyVim、Yazi flavor 从基础 Profile 安装流程中独立出来。
  - Profile 中保留轻量 wrapper，具体功能按需安装。

## 已完成

- [x] 修复 setup 重复运行时重复备份和重建链接的问题。
- [x] 统一管理核心 Profile 文件和外部配置链接的 manifest。
- [x] 增加 LinkRegistry，记录 Target/Source/LinkType。
- [x] 支持 SymbolicLink、Junction、HardLink、Copy、CopyDirectory 的修复与降级。
- [x] 修复外置仓库 + HardLink/Junction 部署时的仓库发现和 `psync`。
- [x] 修复 fnm 跨 PowerShell 会话复用旧 `FNM_MULTISHELL_PATH` 的问题。
- [x] 修复 bootstrap 安装 Git 后当前进程 PATH 未刷新的问题。
- [x] 增加非交互 Profile 静默模式和 `PROFILE_NO_COMPLETIONS`。
- [x] 增加 PSReadLine 参数能力检测和模块级异常隔离。
- [x] 改进 wallpaper 下载、超分输出和设置壁纸失败处理。
- [x] 修正文档中的 `lazy-lock.json`、必需依赖和外部配置数量。
- [x] 提供 setup 安装模式（`-Minimal`/`-Full`/`-Components`/`-SkipComponents`/`-ExcludeTools` + 交互向导）。
- [x] 向 PSCompletions 上游提交懒加载 Feature Request——issue #172 已实现并随 v7.3.0 发布
      （模块初始化延迟到首次补全触发；更新检查改为命令后内联运行）。本仓库冷启动 ~524ms → ~300ms。
- [x] 降低 PSCompletions 启动成本——上游 v7.3.0 内置懒初始化后已基本解决，
      剩余为模块 JIT 固有开销（~130ms），勿再自行包装 OnIdle（见 AGENTS.md 例外条款）。
- [x] 修复 touch 清空已存在文件内容的问题（改为 GNU 语义：存在则只更新时间戳）。
- [x] fnm 启动开销优化：静态兑底（default 版本目录前置 PATH）+ 懒加载
      （首次 node/npm/npx/corepack 才执行 fnm env），启动期零进程调用，
      另提供 PROFILE_NO_FNM=1 总开关。
