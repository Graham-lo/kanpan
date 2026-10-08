# 主工作树 `kanpan` 交接（2026-10-09 01:35 CST）

## 汇总

- **分支**：`handoff/kanpan-2026-10-08`（从 `main` 的 `c43ae419` 开出，`main` 与 `origin/main` 当时同一提交，未动 main）。
- **交接时的 HEAD**：本交接提交（`git log -1` 可见），其父提交 `c43ae419 网页切品种时订单流不再和新品种抢出口`。
- **相对 `origin/main`**：领先 1 个提交——就是把工作树里全部未提交改动（WIP）、本机 Claude 记忆导入（`.project-memory/claude/` 181 条）、本目录一起打进来的这一笔。
- **各会话的任务**（同一工作树里同时开着多个本机 Claude 窗口，交接时仍在跑的标 ⏳）：
  - 「项目工程量评估」：主力订单流接 Bybit + Hyperliquid 三端 + 服务端，功能本体已全部推上 main；剩网页十六图 / m-stress 根因修复的尾巴，详见 `kanpan-项目工程量评估.md`。
  - ⏳「Web端自选切换品种卡顿」：c43ae419 已推上 main；交接时仍在改 `Web/src/chart/` 画线相关文件（`drawPreset.ts` 是交接前两分钟新出现的）。
  - ⏳「订单流数额显示优化」、⏳「kanpan-46」：交接时在跑，具体改到哪一步不在本会话掌握中；工作树里 `Web/src/orderflow/{drawer,drawerView,ladder,state}.ts`、`orderflow.css`、`Web/src/styles/{app,icons}.css`、`Web/src/ui/{icons,qicons}.ts`、`Web/scripts/_q*.mjs` 这批未提交改动应属于它们（或已结束的「PC端大单列表优化」「大额成交展示和大单列表优化」「PC自选页面布局优化」）。
  - 已结束但留有未提交改动：画线字段契约线（`Backend/kanpan-api/contract/drawing-fields.json`、`src/{share,sync,sync_validation}.rs`、`Kanpan/Kanpan/Account/PersonalSyncCodec.swift`、`KanpanCore/.../Drawing.swift`、`KanpanTests/AccountCodec/{DrawingFieldContract,PersonalSyncCodecOwnedKeys}Tests.swift`）与电脑网页画线 TV 化（`Web/src/chart/{drawGeom,drawStyle,drawTools,drawSpec,drawTV}.ts`）。两批都没有交接说明，状态按 WIP 处理。
- **整体能不能编译**：
  - 网页 `Web/`：`tsc --noEmit` 0 错（含全部 WIP，10-09 01:25 CST）；子代理最后一次 vitest 191 文件 2447 条绿（在它的 15 个文件上，其它 WIP 未必跑过）。
  - 服务端 `Backend/kanpan-api`：`cargo check` 通过（含 WIP）。`cargo test --lib` 未跑。
  - iOS：含 `PersonalSyncCodec.swift` / `Drawing.swift` / 两份 AccountCodec 测试的 WIP **未编译验证**；最后一次全绿的 `make app-logic-test` 是 734ca4aa（848 / 848 + 冒烟 5 / 5），之后这几个文件的改动没进过那趟。
  - 验收截图：`docs/acceptance/` 下 419 个修改 + 292 个新增的 png / json / txt 是各窗口跑测回写的素材，照规矩入库（`logs/`、`.xcresult` 已被 `.gitignore` 挡着，没有进来）。

## 没推上来的东西及原因

- `.claude/worktrees/*`：子代理的嵌套 git 工作树（各自带 `.git`），不是源码；`.claude/scheduled_tasks.lock`：本机会话锁。都没加。`.claude/settings.local.json` 被 `.gitignore` 挡着（本机权限设置）。`.claude/launch.json`（浏览器预览的 dev server 配置）推了。
- `git stash` 里 10 条都没 pop：stash@{0}（10-08 19:24 autostash）里的代码部分已核对与 HEAD 一致（`git diff stash@{0}^1 stash@{0} -- KanpanNetwork KanpanCore Web/scripts | git apply --check --reverse` 通过），其余是验收截图；stash@{1}（10-08 01:08 autostash）只有验收截图；stash@{5}（09-23 autostash）与 stash@{2}–{4}、{6}–{9}（lane-i 验收图、D 线半成品〔已弃用〕、09-24 过期工作树备份、laneb-wip、compare-kline stage3、multi-exchange 预 rebase 备份、账号页 + 横屏遮罩暂存〔用户叫停〕）都是 9 月的旧暂存，内容未逐条核对，接手人不要 pop。
- 构建产物（DerivedData、`.build`、`target`）、`.xcresult`、`docs/acceptance/**/logs/`、密钥 / 证书 / `.env`：本来就被忽略，没有任何一样进来；也没用 `git add -f`。

## 本机记忆导入时发现的冲突（以仓库为准，条目照旧导入但不得据此改规则）

- `kanpan-top-bar-three-discs-more-menu`（10-08：顶栏右上只剩三颗「铃 · ⋯ · 搜索」）vs `AGENTS.md`「顶栏右侧五颗圆片（2026-10-05）」。记忆是更晚的用户决定、而且代码已按三颗做了，但 `AGENTS.md` 那句没跟着改——接手人改 `AGENTS.md` 时顺手对齐，不要把顶栏改回五颗。
- `kanpan-min-ios-26-and-ipad-scope`（10-03：兼容机型加 iPhone 15 Pro Max，手机网页还要适配华为 nova 16）vs `AGENTS.md`「兼容范围只有 iPhone 16 Pro、17 Pro Max 两台」。同上，`AGENTS.md` 没跟上。
- `kanpan-no-liquidation-feature` 与 `docs/不做清单.md` 第一行一致（10-08 只放开网页抽屉里一块爆仓摘要），不冲突；但注意 §69 之后手机端「大单与爆仓」页也已上线（`kanpan-mobile-bigtrade-liq-page-prototype-pending`），不做清单那行「手机端要不要做等用户看过原型再定」已过时，待用户确认后改清单。
- 其余条目逐条粗查未见与 `AGENTS.md` / 不做清单相反的规则；记忆里的「Codex 线程」相关条目（`kanpan-codex-handoff-for-named-features` 等）与 `AGENTS.md`「只有用户明说才交 Codex」一致。

## 接手顺序建议

1. 先读 `AGENTS.md`、`docs/不做清单.md`、`.project-memory/PROJECT.md` §69–§70，再读本目录两个文件。
2. 把 iOS WIP 过一遍 `make app-logic-test`（或至少 `make sync-contract` + `cargo test --lib` 对账画线字段契约），确认 PersonalSyncCodec / Drawing 那批能编译、测试绿。
3. 按 `kanpan-项目工程量评估.md` 的「未修」清单把网页十六图尾巴收掉，整套跑绿后 `cd Web && sh scripts/deploy.sh`。
4. 其它窗口的 WIP（订单流抽屉 / 画线 TV 化 / 图标 css）没有说明，先 `git diff c43ae419 -- <路径>` 看改了什么，能跑绿就留，跑不绿就单独开提交处理。
