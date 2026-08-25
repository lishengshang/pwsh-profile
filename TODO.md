# TODO / Roadmap

本文件只记录长期维护事项。临时调试过程、一次性安装问题和具体讨论放在对应的 GitHub Issue 或分支中。

## 优先级说明

- **P0**：阻塞安装、启动、同步或数据安全的问题。
- **P1**：明显功能缺陷、兼容性问题或维护风险。
- **P2**：性能、体验、文档和结构优化。

## P0：阻塞性问题

当前无已知 P0 问题。

## P1：重要改进

- [ ] **增加链接管理测试套件**
  - 覆盖 SymbolicLink、Junction、HardLink、Copy、CopyDirectory。
  - 覆盖断链、错误目标、跨卷降级、重复 setup 和 registry 迁移。
  - 验收标准：在临时目录中运行 Pester 后，所有部署模式均能通过。

- [ ] **增加链接注册表损坏恢复机制**
  - 检测 JSON 解析失败时先备份为 `.corrupt-时间戳`。
  - 根据 manifest 和当前目标重新构建可恢复的登记信息。
  - 不应静默覆盖并丢失其他条目。

- [ ] **为链接注册表增加并发锁**
  - 防止两个 setup/Repair 进程同时读写时相互覆盖登记。
  - 优先使用命名 Mutex 或单次读取、批量写入策略。

## P2：长期优化

- [ ] **明确 PSCompletions、PSFzf 和 PSReadLine 的职责**
  - PSC 导入后 Tab 由其 trigger_key 接管（psreadline 的 MenuComplete 仅在
    PROFILE_NO_COMPLETIONS=1 时生效，见 psreadline.ps1 注释）。
  - 评估默认关闭 PSFzf `TabExpansion`（当前被 PSC 接管后实际不生效），保留
    Ctrl+t/Ctrl+r/Git 快捷键；避免多个组件同时接管 Tab 和补全菜单。

- [ ] **增加 Pester、PSScriptAnalyzer 和 CI**
  - Profile 语法与 smoke test（5.1 解析兼容已人工验证，可自动化）。
  - setup 幂等性测试。
  - 外置仓库、Worktree、无符号链接权限场景测试。
  - Wallpaper 使用 mock API 测试错误处理。

- [ ] **补充链接部署模式文档**
  - 说明 SymbolicLink、Junction、HardLink、Copy、CopyDirectory 的差异。
  - 说明不同模式的同步行为、权限要求和恢复方式。

- [ ] **增加工具版本管理策略**
  - 评估是否维护 PowerShell 模块的版本范围或锁定版本。
  - 评估 winget 工具版本、Yazi flavor 和 LazyVim 的可复现安装方案。

- [ ] **拆分可选个人功能**
  - 评估将 Wallpaper、LazyVim、Yazi flavor 从基础 Profile 安装流程中独立出来。
  - Profile 中保留轻量 wrapper，具体功能按需安装。

- [ ] **setup 备份目录治理**
  - `backup-<时间戳>` 目录随重跑 setup 累积（已被 .gitignore 忽略），
    可考虑保留最近 N 份自动清理。

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
