# 多交易所 阶段 1 + 对比 K 线阶段 1/2：合入 main

日期：2026-09-23。执行：Claude 子代理 xchain（Opus 5.5，high）。工作树 `/Users/mdd/zhk/kanpan-wt-xchain`，临时分支 `xchain-tmp`，模拟器只用 iPhone 17 Pro Max。

## 合入内容

旧分支 `compare-kline-s2`（`6a67192`）rebase 到 `origin/main`（先 `30bf1b4`，推送前再 rebase 到 `191734d` P3.4 Handoff），9 个提交加本次两个修正提交：

- 多交易所阶段 1：`InstrumentID` 统一品种身份，个人数据与缓存无损迁移（报告见 [阶段1](阶段1.md)，原提交 `513e53d` 的验收材料随本次一并入库）。
- `kanpan-feed --cache-root`：冷缓存测量用独立目录。
- 对比 K 线阶段 1、2 与验收材料（报告见 `docs/acceptance/对比K线-2026-09-22/`）。
- 图表读屏只念品种代号。
- 与主线 P3.1（提醒）、P3.2（小组件）对齐：完整品种 key 存储，界面只显示代号。

## 合入时新发现并修掉的四处

| 位置 | 问题 | 修法 |
| --- | --- | --- |
| `AlertActivityController.syncID` | P3.3 锁屏实时活动写死 `"binance/usd_m/" + alert.symbol`，而 `alert.symbol` 已是完整 key，同步 id 变成两层前缀，服务端认不出线 | 改成 `InstrumentID.canonical(alert.symbol) + "/" + id`，与 `PersonalSyncCodec` 同一拼法 |
| `WatchMove.Tracker` | 闸的键 `key + "/" + 方向`，`keep` 按第一个 `/` 拆，拆出来是交易所名，自选一改所有闸被清，同一窗口能再响一次 | 闸键改用 `|` 接方向、按最后一个 `|` 拆；新增 `keepPreservesGatesForFullKeys` |
| `ChartHandoff`（P3.4，合入前一刻上的 main） | 活动标题直接用 `market.symbol`，身份统一后会显示 `binance/usd_m/BTCUSDT`；用例按裸代号写 | 标题只念代号；userInfo 保留完整 key，接力端走 `hkline://symbol/<venue>/<market>/<symbol>`，裸代号仍归币安合约；用例改完整 key、加 Coinbase 一条 |
| `ReviewRange.init(from:)` | 存档里 `symbol` 若是完整 key，`key` 会拼出两层前缀（`init` 已处理，解码没处理） | 解码时含 `/` 则按 `InstrumentID` 拆成三段；新增 `testDecodingAFullKeySymbolSplitsIntoVenueMarketSymbol` |

## 显示文案审计

独立核对了界面文案、读屏、分享输出、提醒标题、小组件、对比图例：**没有一处把带交易所前缀的内部 key 露给用户**。低风险一处留作记录：品种搜索行 `.draggable(symbol)` 拖到外部 App 时带的是完整 key（不是显示文案，未改）。

## 验证（iPhone 17 Pro Max，全部经 `scripts/machine-guard.sh run`）

| 目标 | 退出码 | 结果 |
| --- | --- | --- |
| `make core-test` | 0 | 403 条（第一次跑时我在编译中途改了 `WatchMove.swift`，报 “modified during the build” 退出 2，已作废重跑） |
| `make network-test` | 0 | 115 条 |
| `make data-test` | 0 | 206 条 Swift Testing + 3 条 XCTest |
| `make app-logic-test` | 0 | 8 个逻辑包全过；Handoff 改完后 `make deeplink-test` 另跑一次：14 条 |
| `make account-test` | 0 | 65 条 |
| `make sync-contract` | 0 | 两端字段对账一致（`compareSymbols` 在两份白名单里） |
| `make build`（iPhone 17 Pro Max） | 0 | rebase 到 `191734d` 后重编一次仍为 0 |
| `make chart-test`（iPhone 17 Pro Max） | 0 | 145 条 Swift Testing + 4 条 XCTest |
| `make review-test`（iPhone 17 Pro Max） | 0 | 含新增解码用例 |
| `cargo test --lib` | 0 | 182 passed |
| UI：`CompareUITests`（iPhone 17 Pro Max，rebase 到 `44364a4` 后） | 0 | 4 条全过：面板集合持久与清除、三档周期 / 十字线 / 平移 / 横屏 / 复盘、扫图保留集合、新安装档案登录恢复（截图与读数见 `docs/acceptance/对比K线-2026-09-22/阶段3/`） |

UI 用例这一轮的两处返修：

- `testIntervalsCrosshairPanLandscapeAndReview`：图表面板里「十字线」那一行在屏幕下沿之外，用例原来用 `scrollViews.firstMatch.swipeUp()` 一次划五下，一划就越过那一行滚到了底（失败截图停在「至今涨幅」），`isHittable` 一直是假。改成只拖面板自己的 `panel.content`，按目标在上半还是下半决定往哪拖，落进可视区就停。纯用例问题，app 没有改。
- `testScanningKeepsCollectionAndIgnoresTheMainInstrument`：上一轮（机器上同时有 3 个重活、负载 19）横滑到 ETH 后图区 30 秒仍是「行情加载中」，用例超时；同一份代码 rebase 到最新 main 后重跑，横滑后 ETH 首屏正常、21 秒整条用例通过，早先两轮（合入前 s2 / s3）也都通过。判断是那一刻 ETH 的 K 线请求慢，不是扫图与对比的逻辑问题，app 没有改。

## 后端

阶段 1 与对比 K 线阶段 2 的服务端改动（`sync.rs` / `sync_validation.rs` 白名单加 `compareSymbols`）已从 `origin/main` `ae7673a` 部署到线上：

- 加部署锁 `/tmp/kanpan-deploy.lock` → 备份 `/opt/kanpan-api/backup-xchain-s1-20260923-162121` → rsync → `cargo build --release`（2 分 24 秒，日志 `/opt/kanpan-api/build-xchain-s1.log`）→ `python3 ops/install.py`（退出 0）→ `systemctl restart kanpan-api kanpan-worker`（两个都 active，启动于 16:27:59 CST）→ 释放锁。
- 只读验证：内网 `/health` 200；公网 `/v1/market/meta`、`/v1/capabilities` 200；运行中进程 `/proc/<pid>/exe` 与磁盘上的新二进制 sha256 一致（`7e4d3a19…`），且含 `compareSymbols`；worker 日志报 `Alert evaluator started`。
- 部署前 `testSyncRestoresCollectionIntoFreshInstallationProfile` 失败（新档案登录后对比集合没恢复）：根因是线上服务端还没有 `compareSymbols` 白名单，整条同步操作被拒。部署后该用例通过。
