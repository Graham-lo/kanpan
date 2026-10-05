# 服务端回归与有界压测（2026-10-05）

对象：线上 kanpan-sg（`https://kanpan.43-160-232-253.sslip.io`，`/health` 只在本机 `127.0.0.1:8794`）。美国 orderflow-vps 已停用，没碰。
范围：今天的服务端提交 `44991485`（drawToolUsage）、`90861683`（landscapeBarSpacing）、compareSymbols 接 DXY / Coinbase、DXY 提醒与提醒记录、macro 行情（K 线、ticker、WS）。
时间均为 UTC，除特别注明的 CST。

## 基线（14:22 UTC，周一，DXY 开盘中）

| 项 | 值 |
|---|---|
| kanpan-api | PID 1056586，NRestarts=0，RSS 181–197 MB |
| kanpan-worker | NRestarts=0，RSS 约 47 MB |
| 迁移号 / health | 43 / 200 |
| 线上二进制 | sha256 `a9f9a70a…a4e9030`（= `90861683` 那次部署） |

## 1. 代码层

- `cargo test --lib`：修前 587 过；修后 589 过、0 失败、3 忽略（新增两条 WS 关闭回执测试）。
- `cargo clippy`：无新增告警（`coinbase.rs:297`、`:353` 两条是存量）。
- `ops/test.py --test alert_log`（真 Postgres、隔离库）：2 条全过，含「31 天前的删、29 天的留、超过 31 天的迟到上报不入库」。单测 `the_alert_log_keeps_thirty_days` 钉住清理 SQL 常量。
- 三份字段白名单对账（契约 `contract/settings-fields.json` / iOS `Prefs.syncedFieldNames` / Web）：`drawToolUsage`、`landscapeBarSpacing`、`compareSymbols` 三端一致，无需改。

## 2. 功能回归（临时测试账号，用完即删）

### 同步 —— 全 PASS
- 合法推送（200，`droppedFields [[]]`）：`drawToolUsage {trend:12,hline:5,fibonacci:0,rectangle:100000}`、恰好 12 个键；`landscapeBarSpacing` 1.6 / 40 / 9.5；`compareSymbols` `[macro/index/DXY, binance/usd_m/BTCUSDT]`、`[macro/index/DXY, coinbase/spot/BTC-USD, binance/usd_m/ETHUSDT]`。
- 非法推送（一律 400 `invalid_operation`）：drawToolUsage 未知键 / 负数 / 1.5 / 100001 / 13 个键 / 数组；landscapeBarSpacing 1.5 / 41 / "4" / null；compareSymbols EURUSD / `macro/usd_m/DXY` / 重复 / 4 个；同一条 op 合法字段混非法字段；同一批合法 op 混非法 op（整批拒，原子）。
- 非法推送之后拉回的正文与之前逐字节相同；bootstrap 与 changes 一致。

### 提醒（DXY）—— PASS
- 账号 A：14:31:53 现价 102.317 建 QA-DN（102.314）/ QA-UP（102.32），14:35:01.757 与 14:36:06.757 先后触发；worker 日志「DXY triggered … recorded and synced, not pushed (no APNs key)」；`alert_watches` 两条 fired，`alert_log` 2 行，同步对象 `status: fired` + `firedAt` / `firedPrice`、未删除。
- 账号 B：14:39:24 现价 102.322 建一对，QA-DN（102.319）14:40:31 触发、`firedPrice 102.317`；QA-UP 10 分钟内没到价、保持 active（只响一次、不误触发）。
- 提醒记录接口：GET 原文 200；`symbol=BTCUSDT`（裸代号归 binance/usd_m）200 空；非法 symbol 400 `invalid_symbol`；`limit=1` 返回 1 条；DELETE 204、之后 GET 空；无令牌 401。

### 行情（macro K 线 / ticker）—— PASS
- 1m：500 根、末根是当前分钟、步长 60 s、OHLC 不自洽 0；1h / 1d / 5m / 15m / 1w 各 500 根，4h 438 根（历史源本身就这么多）；远端 230–550 ms，冷启动首个 1m 767 ms，VPS 本机约 3 ms。
- `limit=5` / `limit=1000` 按数返回；一小时的 startTime/endTime 窗口返回 59–60 根；`interval=2m` 400 `invalid_interval`；`symbol=EURUSD` 400 `invalid_symbol`。
- ticker：`marketState open`、`priceSource official`。休市行为（每日 21–22 UTC 夏令时、周五 21:00 至周日 22:00 UTC、节假日无报价落 closed）按 `calendar.rs` 核对，回归时段在开盘中，没有实测到休市帧。

### 行情 WS（`/v1/market/stream?source=macro`）—— 发现 1 个 bug，已修已部署
- 60 s：握手 1.3–1.8 s；ticker 6 帧、kline 6 帧、心跳 4 帧；ticker 间隔中位 10.5 s、最大 18.7 s；心跳严格 15.0 s 一帧且带 `marketState open`。
- `LIST_SUBSCRIPTIONS` → `["dxy@ticker","dxy@kline_1m"]`；SUBSCRIBE / UNSUBSCRIBE 正确；未知流 `eurusd@ticker` 回 error code 2；乱码回 "Invalid JSON"；断开重连握手 1271 ms、首帧即到。
- **Bug**：客户端先发 Close，macro 与 coinbase 两条流都直接丢 socket、不回 Close 帧，客户端拿到 1006（非正常关闭）。根因：tungstenite 收到 Close 只把回执排进队列、下一次读或 flush 才真正发出，服务端随即 break 丢了连接。修复 `a40c046e`：macro 收到 Close 后 `flush` 一次（最多等 2 s）再走；coinbase 读循环收到 Close 后再 `next()` 一次（最多 2 s）把回执推出去；两条各加一条起真 axum 服务、真客户端发 Close、断言收到 Close 帧的测试（修前两条都红「没回 Close 就断了」）。Web 端 `feed.ts` 关之前先摘 onclose，用户侧原本看不到症状，但 1006 会污染监控与任何依赖关闭码的客户端。

## 3. 有界压测（账号 B；三接口各 20 并发 × 60 s 串行；另挂 10 条 macro WS）

| 接口 | 请求数 | rps | p50 ms | p95 ms | p99 ms | max ms | 状态码 |
|---|---|---|---|---|---|---|---|
| GET /v1/alerts/log | 4016 | 57.4 | 235 | 541 | 734 | 952 | 全 200 |
| GET macro klines 1m×500 | 3989 | 57.0 | 231 | 512 | 713 | 1051 | 全 200 |
| POST /v1/sync/operations（1 条 settings patch） | 3937 | 56.1 | 240 | 516 | 705 | 883 | 全 200 |

- 老接口探针 `/v1/sync/changes`：压前 n=39 p50 240 / p95 890；压中 n=265 p50 251 / p95 625 / max 891；压后 n=38 p50 248 / p95 876；全 200。压中 p95 不比基线慢（远端 p95 主要是跨境网络抖动）。
- 10 条 WS 各收 72 帧、无掉线；中止条件（NRestarts 变化、5xx > 1%、p95 > 基线 3 倍）一次没触发。
- 每 10 s 监控（14:50:07–14:54:41）：apiN=0、workerN=0，api RSS 197 MB 不涨，worker 48 MB，load 0.2–1.4，Postgres kanpan_app 连接 16→20（同时活跃 ≤ 1），health 一直 200；压后 NRestarts 0、MemoryCurrent 190 MB；日志 0 panic、0 ERROR。

## 4. 部署（`a40c046e`）

- 2026-10-05 23:09:08（CST）从 origin/main `a40c046e` 的 `git archive` 干净目录 `cargo zigbuild --release --target x86_64-unknown-linux-gnu.2.35`。
- 备份 `/opt/kanpan-api/backup-20261005-230552/`（旧二进制 `a9f9a70a…a4e9030` + `source.tgz`）。
- 源码 `rsync -rlt --checksum`（不带 `--delete`），只有 `src/venues/coinbase.rs`、`src/venues/macro_index/stream.rs` 有差异；178 个文件 sha256 逐个对上；新二进制 sha256 `37bd1af2…d57179` 本地 = 线上。
- `ops/install.py` 自己 try-restart：两单元 active、NRestarts=0、`/health` 200、迁移 43；重启后日志 0 panic / 0 ERROR。
- 复测：macro 与 coinbase 两条流客户端主动关闭 → `code 1000, wasClean true`（修前 1006）；macro K 线 7 档周期、参数校验、ticker 全部照旧。
- 回滚：`sudo install -m 0755 /opt/kanpan-api/backup-20261005-230552/kanpan-api /opt/kanpan-api/target/release/kanpan-api && sudo systemctl restart kanpan-api kanpan-worker`。

## 5. 范围外发现（没改）

- 订单流历史模块的慢查询：今天 255 条 sqlx「slow statement」WARN，全部来自 `src/orderflow_history`，回归 / 压测窗口内 0 条。`WITH RECURSIVE b(base)` 松散索引扫描（`flow.rs:158`、`heat.rs:391`）177 次，`heat.rs` 的 `WITH src AS (SELECT` 51 次，`SELECT * FROM (SELECT base,venue_id,…` 27 次；耗时中位 4.2 s、最长 18.4 s。值得单开一轮看索引 / 查询计划。

## 6. 测试账号

- 账号 B `qa_rg2_muvcvn5z`（`ca252d18-…`）：`DELETE /v1/auth/account` 200，再登录 401 `authentication_failed`，库里查不到；含口令的文件已删。
- **账号 A `qa_rg_muvcldua`（`64742702-545c-49a8-bcc6-0e30074aedc2`）仍在线上，是孤儿**：它的口令文件放在 `/tmp/kanpan-regress/`，被另一个窗口的 `scripts/machine-guard.sh clean`（清 `/tmp/kanpan-*`）删掉了。用文档里的运维命令 `kanpan-api reset-password` 重置口令、或直接改库，都被自动模式分类器判为远端写入拦下，我没有绕。账号里只有 `settings/chart` 一份、两条已触发的 DXY 提醒与两行提醒记录。清理办法（VPS 上）：
  `sudo systemd-run --quiet --pipe --wait --collect -p DynamicUser=yes -p EnvironmentFile=/etc/kanpan-api/service.env /opt/kanpan-api/target/release/kanpan-api reset-password qa_rg_muvcldua`
  拿到一次性口令后用它登录、`DELETE /v1/auth/account`（body `{"password": "<一次性口令>"}`），再登录应 401。
- 教训：自己的临时目录不要起 `/tmp/kanpan-*` / `/tmp/p[0-9]-*` 这类名字，会被 machine-guard clean 当可再生资源清掉。
