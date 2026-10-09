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

- [x] **阶段 1：测试与 lint 加固**
  - [x] 提取 setup 链接部署循环为可测试函数（`refactor/extract-link-deploy`，
        新增 `Scripts/Deploy-ConfigLinks.ps1`；`Get-ManagedLinkState` 迁入
        LinkRegistry.ps1；旧 txt 迁移块当时提取为独立函数，后因迁移已完成而删除）
  - [x] Pester 测试套件：registry 读写 / deploy 幂等与降级 / repair 五类链接
        （`test/link-pester-suite`，CI 仅 pwsh 矩阵作业运行；附带修复断链
        junction 判定跨版本不一致——PS7 下被误备份而非清理）
  - [x] PSScriptAnalyzer 门禁：仅新增违规失败（`ci/psa-baseline`）。
        快照取自基线提交（PR 取目标分支 tip、push 取上一提交）——对变更过的
        .ps1 比较当前与基线版本的按规则计数，新增即失败，存量放行且无需
        入库快照文件；豁免清单在 Scripts/Compare-PsaBaseline.ps1 头部

- [x] **阶段 2：注册表健壮性**（`feat/registry-hardening`）
  - [x] 损坏恢复：解析失败先备份 `.corrupt-<时间戳>`，按 manifest 与磁盘状态重建
        （Restore-LinkRegistry，只认领有磁盘证据的链接，Copy 登记随损坏丢失、
        由下次 setup 重新接管升级为链接）
  - [x] 并发锁：命名 Mutex 防 setup 与 Repair 同时登记互相覆盖
        （__Invoke-WithLinkRegistryLock 串行化 Set-LinkRegistryEntry 读改写与
        迁移/重建落盘；创建失败或超时降级为不加锁继续）
  - [x] 备份目录治理：只清理严格 `backup-<yyyyMMdd-HHmmss>` 命名目录，保留最近 3 份
        （Remove-StaleLinkBackup，部署结束后执行；大小写或格式不一致的一律不碰）

- [ ] **阶段 3：文档防漂移 CI**（`ci/docs-drift-check`）
  - [x] 注释与文档的交叉引用真实性校验（`Scripts/Check-CommitMsg.ps1 -CheckRefs`，
        CI 与本地提交前验证都跑）——文件不存在、或 `X.md「章节」` 里 X.md 无该标题
        即失败。此前有 3 处注释指向 README Hub 化时已删除的「设计说明」「依赖工具」表
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

不在此重复登记。历史与理由看 `git log`，仍然有效的约束已经写进 `AGENTS.md`
（如「勿再自行包装 OnIdle」在规则 1）和 `docs/reference.md`（如 `PROFILE_NO_FNM` 开关）。
