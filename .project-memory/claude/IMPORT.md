# Claude 记忆导入

导入时间：2026-09-14T21:41:00+08:00

来源：
- /Users/mdd/.claude/projects/-Users-mdd-kanpan/memory/*.md
- /Users/mdd/.claude/projects/-Users-mdd-zhk/memory/kanpan*.md

共 16 份原文快照，保留原文件时间。这里只保存历史上下文，不把旧会话中的授权自动视为新操作授权。用户当前指示与项目根 KANPAN-HANDOFF-2026-09-14.md 的现场核验优先。

2026-09-17 复核（Codex 已退出项目，现行约定见 `../PROJECT.md`）：
- kanpan-implementation-by-collaborator.md 已删除：「代码由协作者写、Claude 不要开发」完全失效，现在代码由 Claude 窗口实现。
- kanpan-project-location-and-spec.md：仓库路径仍对；「先读实施任务书」已不成立，任务书的默认风格、指标、底栏布局都被后续决定覆盖，先读 `README.md` 与 `../PROJECT.md`。（2026-09-18 已在该文件头部打上历史标注并取消 `pinned`，里面的 iOS 17+、「只有品种/周期/K 线/指标四件事」都是旧的。）
- kanpan-dev-environment.md：Xcode / 模拟器信息是 09-14 快照，真机验证以 iOS 26 的 iPhone 16 Pro 为主。
- kanpan-default-subplots.md：仍然成立（`IndicatorID.defaultSubs == [.macd, .rsi]`）。
- kanpan-period-list.md、kanpan-chart-zoom-fixed-box.md、kanpan-no-persistent-kline-storage.md、panels-close-after-pick.md、verify-feel-against-real-aicoin.md：仍然成立。
- kanpan-surge-proxy-scope.md、mac-is-the-surge-gateway.md：「不改 Mac 网络」的约束仍在；「iPhone 镜像不可用」已过时。

2026-09-14 导入时的备注：
- mac-is-the-surge-gateway.md 中“iPhone 镜像不可用”已被当前实际画面推翻；网关网络不可随意修改的约束仍应保留。
- kanpan-implementation-by-collaborator.md 描述今天早些时候协作分工，不能用它判定当前工程未开发或取消用户本轮交接要求。
- 旧的 A / ⏮ 形态争议以最新真机记录为准，两者是不同控件。
- 旧记忆中的并行代理偏好不等于本轮要求启动其他代理。
