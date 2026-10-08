# kanpan-takeover-ends-codex-threads

**项目约定**：看盘里 Claude 接手 Codex 没做完的活时，先把那几条 codex exec 线程彻底结束，免得额度恢复后它们续跑、和接手方撞车还白烧额度

2026-09-23 Codex 额度用完（恢复时间 2026-09-29），四条看盘实现线程停在半路，用户让我接手，
并补了一句：「接手后直接结束 codex 的几个线程，避免额度恢复浪费 token」，又提醒「之前派任务是 cli 派的」。

所以以后凡是 Claude 从 Codex 手里接活，第一步就是确认 Codex 那边不会再动：

- 这些线程是用 CLI `codex exec` 派的，不是 ChatGPT 桌面版里的会话。每条线程在 `/tmp/codex-<名字>/`
  下有 `pid`、`prompt.md`、`run.log`；线程记录在 `~/.codex/sessions/…/rollout-*.jsonl`。
- 要查的是：`pid` 文件里的进程是否还活着（`pgrep -fl 'codex.*exec'`）、有没有包装脚本或重试循环、
  cron / launchd / `at` 任务，以及 `~/.codex/goals_1.sqlite`（thread goal 会自动续跑）和
  `~/.codex/queue_1.sqlite`（排队消息）。活着的一律杀掉，自动续跑的挂钩一律清掉。
- 原因：额度恢复后续跑的线程会拿过期的交接书接着改同一批 worktree、再推 main，既浪费用户的额度，
  又会和已经接手的一方互相覆盖。
