# kanpan-codex-handoff-for-named-features

**项目约定**：看盘里只有用户明确说「交给 codex」的活才走 Codex CLI（gpt-6-astra / xhigh）；2026-09-23 起不再默认交给 Codex（推翻了 09-22「没做的一律交给 codex」），默认由 Claude 这边自己完成

# 看盘：用户点名交给 Codex 的功能，Claude 只设计与验收

2026-09-22 「发给朋友·画线分享」方案定稿后，用户说：「可以直接开工……这个功能我想交给 codex
来完成，使用 gpt 6 astra 极高挡位……直接 cli 即可。你还是负责设计验收，不对的让 gpt 返工，
同步一下这个项目的相关记忆给它，测试让它去做，你只验收即可。」

这改写了 kanpan-who-writes-the-code（一律派 Opus high 子代理写）在**用户点名**时的做法：

- **用户说「交给 codex」时，代码由 Codex CLI 写，不派 Opus 子代理，我自己也不动手。**
  只对被点名的那个功能有效；没点名的活仍按原规矩走。
- **「极高」对应 Codex 的 `model_reasoning_effort = "xhigh"`**（档位 minimal / low / medium /
  high / xhigh），模型 id 是 `gpt-6-astra`。本机 `~/.codex/config.toml` 已把这两项设成默认，
  `approval_policy = "never"`、`sandbox_mode = "danger-full-access"`，所以非交互跑法就是
  `cd /Users/mdd/zhk/kanpan && codex exec -m gpt-6-astra -c model_reasoning_effort=xhigh - < prompt.md`
  放到后台、输出写进 scratchpad 日志；不要开轮询等它（kanpan-no-idle-waiting-for-phone）。
- **我的角色是设计 + 验收 + 打回**：验收按 kanpan-acceptance-means-reproducing-the-symptom-is-gone
  独立复现；不对就再跑一次 `codex exec`（或 `codex exec resume --last`）把具体的错处和期望
  写清楚让它返工，不自己顺手修。
- **测试是 Codex 的活**：单测、UI 用例、真机装包、服务端部署与只读验证都写进交接 prompt 里
  要求它做完，我只查它的报告并独立复现。
- **交接前要把项目的相关记忆同步给它**：Codex 看不到我的 memory 目录，所以 prompt 里要把
  适用的规则摘成条目（中文标签、图上不浮控件、一个动作一个入口、不堆选项、尺寸克制、
  功能端到端做完含 Rust 后端与部署、同步契约流程、只跑受影响用例并开超时、真机
  `make install-release`、不动别的窗口未提交文件、只提交自己的文件并 push、后端先备份再
  部署再只读验证、用自造的测试账号真的测）。写法按 kanpan-handoff-prompt-style：指路径与
  file:line，不内联大段代码。
- 同时把 `AGENTS.md`「谁在做什么」里「Codex 不再参与」那句改成带例外的说法，不然 Codex
  一进仓库读到那句会误判自己的角色。

## 2026-09-22 起：没做的一律交给 Codex

同一天晚些时候，我把「未完成事项」盘完准备派活时，用户连说三句：「接下来要交给 codex 实现，
使用 GPT 6 astra 极高档位……你只负责设计验收等项目经理以及产品经理的任务和职责，不负责实现」、
「我把其它那个窗口的任务停了，现在全部交接出去」、「**没做的一律交给 codex**」。

所以从这天起 Codex 不再是「点名例外」，而是看盘所有剩余实现的默认承接方：

- **仓库里任何还没做完的事，默认都写进交接书交给 Codex**，不派 Opus 子代理写、我也不动手。
  kanpan-who-writes-the-code 里「一律派 Opus 子代理写」这条对看盘的实现已经不再适用；
  Opus 子代理只用于盘点、溯源、核对这类只读调查。
- 交接书要分期（先修用户当天看见的 bug，再接上一个窗口的半成品，再便宜的修补，
  再从零的功能，最后证据与文档），每项都给出处 file:line、产品决定、验收标准；
  用户已判「不做」的项列成禁做清单（kanpan-decided-not-to-do-stays-dead）。
- 派出去之后不空等：用一个后台 `until` 等进程退出、一个 Monitor 看它落到 main 的提交，
  然后结束回合；它推了什么再按阶段独立复现验收。
- 仓库 `AGENTS.md`「谁在做什么」、`.project-memory/PROJECT.md` §1 和父目录 `CLAUDE.md`
  都要同步改成「未完成事项一律 Codex 实现」，否则 Codex 读到旧句子会误判自己的角色。

## 2026-09-23 起：不再默认交给 Codex

体验审查做完、我把根因调查派出去准备写 Codex 交接书时，用户说：「这个由你来完成，不要交给 codex」
「**以后不要默认交给 codex，除非我明确和你说**」。

所以上面「没做的一律交给 codex」这一节**已经失效**：

- 默认的实现方回到 Claude 这边（主窗口负责把控，按 kanpan-who-writes-the-code 派 Opus 子代理写、
  主窗口验收；也可以自己动手），不写 Codex 交接书、不起 `codex exec`。
- 只有用户在当次对话里明确点名「交给 codex」时，才按本文前两节的流程走 Codex。
- 其他窗口在这之前已经派出去、还在跑的 Codex 阶段不用去拦，这条只管我之后怎么派活。
