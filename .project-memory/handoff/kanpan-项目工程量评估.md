# 会话「项目工程量评估」交接（2026-10-09 01:20 CST）

主线任务：主力订单流接 Bybit + Hyperliquid（三端 + 服务端，统一展示模型；订单流抽成独立模块、交易所接入放进多交易所模块；限流 / 断网；压测；交叉验证）。全貌与数字见 `.project-memory/PROJECT.md` §69。

## 已推上 main 的

- 功能本体、限流断网、三端用词、验收截图、线上五家实测：见 §69 前半（bca05018 / 2b9e020d / e26e3ae0 / 3217fa2c / 4572f96e 等）。
- 压测翻出并从根因修掉的三批：KanpanData 7 处偶发（888233b0）、服务端慢语句（ea211781，迁移 0053–0057，已上线并复查）、iOS app-logic 主 actor 饿死（734ca4aa，848 / 848 + 冒烟 5 / 5）。
- 服务端 01:00 CST 前复查：无重启、IO 压力在基线、近 25 分钟 1 条 rollup 慢语句（legacy 分区 02:00 CST 前仍在收行，预期内）；`orderflow_heat` legacy 那 19 GB 分区按闸门约 10-09 08:00 CST 整张 DROP，预算回到 20 GiB 以内，不需人工干预。

## 工作树里未提交、未完成的（Opus 子代理 a13767ea5b163e088 的活，已叫停）

十六图专项 `layout16-review.mjs` 9 条红 + 手机 `m-stress.mjs` 4 条红的根因修复。子代理改过的 15 个文件全在 `Web/` 下：
`src/chart/chart.ts`、`src/chart/domPulse.ts`（新）、`src/chart/footprint.ts`、`src/chart/heikinAshi.ts`、`src/chart/rangeBars.ts`、`src/market/klineCache.ts`、`src/market/rest.ts`、`src/orderflow/index.ts`、`src/orderflow/layer.ts`、`src/pages/chart.ts`、`tests/dom-pulse.test.ts`（新）、`tests/feel-universe-cache.test.ts`、`tests/kline-cache.test.ts`、`scripts/layout16-review.mjs`、`scripts/m-stress.mjs`。
（`Web/` 下其余未提交改动——`drawGeom / drawStyle / drawTools / drawSpec / drawTV / orderflow/drawer* / ladder / state / orderflow.css / styles / ui/icons / ui/qicons / scripts/_q*.mjs / _switch-probe.mjs`——属于别的窗口，不是这条线的。）

已修（本地 tsc 0 错、vitest 191 文件 2447 条绿、b10 / b12 / m-stress 四段 0 ✗，c13 还剩 1 ✗）：
- B10 K 线请求：3bcd4645 让每次 1↔16 切换都给 15 格重取尾巴 → 60 秒内取过的直接用，格子销毁时把 K 线记回会话缓存。
- B10 堆 / 节点 / 监听：订单流图层和足迹、HA、范围 K 三张绑定表攥着已销毁的图 → 销毁时解绑。
- B10 本机存档大小：78aec4f8 把全市场表放进 localStorage → 挪到 IndexedDB。
- B12 #2：误判——磁盘缓存命中、格子只补尾巴；脚本改成分开算整段请求与补尾巴请求（实测 16 个补尾巴请求并行发）。
- C13 常态 10 秒 / C15 CPU：推送改 DOM 文字没有节拍上限 → 新增 `domPulse`，图例和详情 250 ms 一拍、自选行 1 秒一拍（3d084e75 旧构建也一样红，不是某个提交引入）。
- C15 interval 计数：多出来的是 e26e3ae0 加的 OKX / Bybit / HL 订单流连接心跳，每条一个；脚本改成应用自己的仍按 ≤ 8 卡、心跳单独对账，没放宽应用那条。

未修（接手人从这里继续）：
1. **C15「16 格最新价跟推送走」**：已复现——页面进了断线态（`body` 上 `stale` 类为真）但连接开着、K 线帧照常来；`pages/chart.ts` 处理 K 线推送那段见 `st.stale` 为真直接 return，16 格整段冻住。推测是全市场表刷新失败把 `S.live` 置 false 后一直卡着，未确认、未修。查清根因修掉，再验这条。
2. C14（布局 ×50、换品种 ×100 的堆增长）修完还没重测。
3. 整套复跑：`layout16-review.mjs b10 b12 c13 c14 c15`、`m-stress.mjs`、`pc-bigtrade.mjs`、`vite build` 后 `draw-cross.mjs perf layouts`，全 0 ✗ 后才提交、`cd Web && sh scripts/deploy.sh` 部署、线上再跑一遍 m-stress。
4. PROJECT.md §69 末尾补一条「网页十六图 / m-stress 根因」（§69 的 iOS 与服务端复查两段已写在工作树里未提交的 PROJECT.md 中；同一文件里 §70 是别的窗口的）。
5. 子代理留在 scratchpad 的 `wt-head`、`wt-bis` 两个 git worktree 由本机 `git worktree prune` 清，不在仓库里。

## 其他

- `git stash list` 里的 10 条都不是这条线的新东西：stash@{0}（10-08 19:24 autostash）代码部分已核对与 HEAD 一致（`git apply --check --reverse` 通过），其余是验收截图；stash@{1} 只有验收截图；stash@{2}–{9} 是 9 月的旧暂存（D 线半成品、lane 备份、multi-exchange 预 rebase 等），内容未核对，不要 pop。
- 没有密钥、证书、`.env` 进来；`.claude/worktrees/*` 是子代理的嵌套工作树（含 `.git`），不该提交。
