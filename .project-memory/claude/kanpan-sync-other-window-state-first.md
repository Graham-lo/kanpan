# kanpan-sync-other-window-state-first

**项目约定**：看盘项目里给方案或动手前，先同步另一个窗口的进度：看 git 状态与最近提交、.project-memory/PROJECT.md、docs 里的进度文档

在看盘（kanpan）仓库里，用户经常同时开着另一个 Claude 窗口在改代码（2026-09-17 那天是「另一个窗口正在改交互逻辑」）。
我如果不先看那边的状态就提方案或动手，容易和在做的事冲突、重复，或者把别人的未提交改动一起提交掉。
用户以前会明确要求「先同步一下记忆」再谈新功能；现在这件事默认要做。

**先 `git fetch origin main`，再拿 origin/main 当基线。** 2026-09-24 的深度审查我直接以本地 main 为基线，
没有 fetch；其实别的窗口是在各自的 worktree（`/private/tmp/kcb/wt2`、`~/kanpan-matrix` 等）里工作并直接
push 的，本地 main 落后 origin/main 59 个提交，审查出来的一批问题上游早就修了，派出去的 A / B 两条线
和上游重叠了 35 个文件，D 线接到的活全是上游已做完的，只能停掉重新移植。所以「看 git 状态」的第一步
是 `git fetch origin main && git log --oneline main..origin/main`，本地 main 只反映本窗口的视角，
不反映项目的最新状态；审查、方案、派活都要以 origin/main 为准，落后就先 rebase 再开工。

同步时看三处：

- `git status --porcelain` 和 `git log --oneline -10`：工作树里哪些文件被另一个窗口改了、最近推了什么。凡是别人改动中的文件，我的方案不要碰，提交时只 `git add` 自己的文件。
- 仓库自带的跨窗口记忆：`.project-memory/PROJECT.md`（现行约定与状态）、`AGENTS.md`、`README.md`——这三份是现行口径。`docs/账号复盘-实施进度.md` 只剩最后一节「尚未完成的复盘范围」还作数，它讲行情线路的那两节是 2026-09-15 自动切换时代的旧账，已被「两档用户自选、没有自动切换」取代。
- 用户提到另一个窗口在做什么时，把它当作硬边界，先问清楚或直接避开，不要往同一批文件上堆改动。

历史说明：2026-09-15 之前这个项目曾由 Codex 写代码，当时要去读 `~/.codex/memories` 和 `~/.codex/sessions` 的会话记录。Codex 已经退出本项目，那些路径不用再看；仓库里 `.project-memory/HISTORY-2026-09-15-codex.md` 和 `KANPAN-HANDOFF-2026-09-14.md` 是历史快照。

同步结果要在回复里简述给用户，并说明它对新方案的约束。
