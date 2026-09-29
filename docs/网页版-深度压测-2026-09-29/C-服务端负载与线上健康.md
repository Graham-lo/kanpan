# 网页版深度压测 · C 路：服务端负载与线上健康

时间：2026-09-29 23:25 至 2026-09-30 03:05（上海时间）。对象是线上 kanpan-api（serve 8794 / worker）、
行情网关 kanpan-stream-hub（8793）、Caddy 站点 `kanpan.107-174-172-10.sslip.io` 与网页版 `/web/`。
负载工具是 `Backend/kanpan-api/ops/stress.mjs`，随本报告一起提交；账号只用 `webstress_c0929`，
凭据只从环境变量读，没有写进任何文件。

## 结论

- **修了两个会让真人看到 503 的服务端 bug，都已上线**：
  1. **刷新与登录被同步推送饿死**（`ede4c077`，02:17 部署）。同一账号 20 路并发同步时，刷新约 4% 回 503，p99 在 6.5–10 秒。
  2. **worker 清理把一个人的同步锁攥了 146 秒**（`82dcda1b`，02:56 部署）。这段时间里这个人的同步 188 次中有 162 次回 503。
- **修完后复测，同步与刷新都是 0 错误**：
  - 同步 20 并发跑 152 秒，共 10 664 次请求，0 错，p95 539 ms。
  - 刷新 60/60 成功，p95 约 340 ms。
- 在上限以内的接口：
  - meta、板块历史、订单流历史（本机回环）、账号接口、网关 WS（20 连接 × 8 流）都在 20 并发下 0 错误、p95 < 2 s。
  - **订单流热力图冷读**在 2 并发就超过 p95 2 s，按规则停了。这一项没修，原因和方案见「没修的问题」。
- **找相似**：9 次搜索全部完成，同一账号第二个并发请求一律 `429 search_busy`。9 次里有 2 次结果是 0，那是分数门槛挡掉的，不是 bug。
- **静态资源**：HTTP/2 正常。缓存头、br/zstd、安全头都不理想，但这些在 Caddy 配置里，不在本路范围，只记录。
- **首屏**（2560×1440 冷启动，中位数）：直连价格出现 1.89 s、首次跳价 3.07 s；网关价格出现 1.78 s、首次跳价 2.83 s。

## 1. 后端测试

全部经 `scripts/machine-guard.sh run` 跑：

| 时间点 | lib | 集成 |
|---|---|---|
| 改动前 | 511 过 | 35 组全绿 |
| 第一个修复后 | 全绿 | 全绿，新增 `refresh_and_login_are_not_starved_by_a_personal_transaction` |
| 第二个修复后 | 511 过（含迁移无锁检查） | 35 组全绿，新增 `pruning_neither_waits_for_nor_hogs_a_persons_sync_lock` |

## 2. 负载前后基线（VPS 每 30 秒采样一次）

| 项 | 负载前（09-29 23:25–23:35） | 负载后（09-30 03:03） | 说明 |
|---|---|---|---|
| 负载（1 分钟） | 1.2–2.5 | 3.3 | 刚跑完同步复测；worker 重启后复盘判定在追数据 |
| 可用内存 | 约 4.27 GB | 4.39 GB | 8 GB 的机器 |
| 交换区 | 758 MB | 900–940 MB | 上限 4 GB |
| kanpan-api 内存（cgroup） | 298 MB | 226 MB | 负载后的数字是重启后的 |
| 订单流跟踪 | 154 只，RSS 289 MB，59 条上游连接 | 155 只，RSS 217 MB，59 条上游连接 | |
| kanpan-worker 内存 | 39 MB | 23 MB | |
| PG 连接 | 约 20（活跃 1–2，空闲 18–19） | 23（活跃 2–4，空闲 19–21） | serve 连接池 8，worker 8 |
| 数据库总量 | 3 506 MB | 5 186 MB | 预算 20–40 GB |
| · orderflow_heat | 1 576 MB | 2 451 MB | 表从 09-29 16:35 起写，约 235 MB/小时 |
| · market_features | 828 MB | 1 504 MB | 找相似索引在补历史，已补齐，写入停在 655 494 |
| · orderflow_orders | 1 068 MB | 1 129 MB | |
| · sync_operations | — | 38 MB | 压测账号的回执 |
| 采样窗口里的 warn / error | 0 | 0 | 部署后 journal 没有 warning，也没有 55P03 |
| 磁盘 | — | 144 GB 盘剩 105 GB | |

**保留期（3 天）**：
- 已结束的订单里最老的是 3 天 7 分钟前，每小时清一次，符合 3 天保留。
- `first_seen` 最老是 5 天前，那是一直挂着没结束的单，按规则保留。
- 已不在跟踪的品种，在订单表和热力表里都是 0 行。

**热力表容量推算**：约 235 MB/小时 × 72 小时 ≈ 17 GB 封顶。加上 market_features 约 1.5 GB、订单约 1.1 GB，稳态大约 20 GB，在 20–40 GB 的预算以内。

## 3. 各接口负载结果

规则：阶梯加并发（2 → 5 → 10 → 20），最后一档持续 2–3 分钟。任一 10 秒窗口里错误率超过 1% 或 p95 超过 2 s 就立刻停下。

| 接口 | 从哪打 | 并发 / 时长 | 请求数 | 错误 | p50 / p95 / p99（ms） | 备注 |
|---|---|---|---|---|---|---|
| `GET /v1/market/meta` | 本机 → 线上 | 20 / 140 s | 7 976 | 0 | — / 352 / 390 | |
| 板块历史 | 本机 → 线上 | 20 / 150 s | 4 990 | 0 | — / 999 / — | 瓶颈在跨洋链路 |
| 板块历史 | VPS 回环 | 20 | — | 0 | — / 10 / — | 服务端本身很快 |
| 订单流历史 `history` | VPS 回环 | 20 / 150 s | 2 511 | 0 | — / 1 432 / — | 首字节 p95 82 ms，主要花在传输大响应 |
| 订单流历史 `history` | 本机 → 线上 | 2 | — | 0 | — / 2 801 / — | 链路带宽限制，按规则停在 2 并发 |
| 订单流热力 `heat` | 本机和回环 | 2（停） | — | 0 | — / 约 3 100–3 200 / — | 冷读慢，见「没修的问题」 |
| 同步：推送 / 增量 / 全量拉取（修复前） | 本机 → 线上 | 20 / 150 s | 6 239 | 0 | — / 582 / — | |
| 刷新令牌（修复前，和同步同时跑） | 本机 → 线上 | 每 5 s 轮换 | — | 约 4% 503 | — / — / 6 500–9 800 | bug 1 |
| 同步（bug 1 刚部署，worker 启动清理期间） | 本机 → 线上 | 20 | 188 | 162 × 503（全是 55P03） | — | bug 2，按规则停下 |
| **同步（两个修复都上线后）** | 本机 → 线上 | 20 / 152 s | **10 664** | **0** | 226 / 539 / 1 009 | |
| **刷新（两个修复都上线后）** | 本机 → 线上 | 两个会话各 30 次 | 60 | 0 | 两个会话 p95 分别 288 / 340 | |
| 账号：登录 / 刷新 / `me` | 本机 → 线上 | 120 s | — | 0 | p95 1 006 / 317 / 289 | 登录慢是故意的（密码哈希） |
| 找相似 | 本机 → 线上 | 串行 9 次 | 9 | 0 | 见下 | |

### 找相似与回填让路

组合：15m / 1h / 4h × 32 / 48 / 64 根，BTC 和 ETH。

- **完成时间**：9/9 都是 `completed`。
  - 提交约 200–250 ms，取结果约 190 ms。
  - 从提交到完成 13.6–19.8 s。有一次 44.6 s，是在排权重账本：那一分钟 `usd_m` 已经用到 1 200/分钟的上限。
- **并发限制**：同一账号同时发第二个搜索，一律回 `429 search_busy`，符合一个账号只允许一个在跑的设计。
- **0 结果的两次**：1h/48 BTC 和 1h/64 ETH 各比了 300 个候选、一个也没留下。
  - 原因是 `search::min_score` 的门槛（1h 要求 ≥ 0.58），不是 bug。
  - 这一点可以在网页端文案上说明（例如「没有足够相似的」），属于 Web 端的事，这里只记录。
- **回填让路**：代码里 `market_index` 的循环在 `search::busy()`（90 秒内有过领取）、闸门按着、或账本没空间时整个让开。
  - 但这次压测时公开历史索引已经补齐（`market_features` 的写入从 02:28 起一直是 655 494），回填处于空闲，线上没法观察到「正在回填时被搜索挤开」。
  - 采样里能看到的是：找相似跑的那几分钟，账本满了以后搜索自己排队，没有任何失败。
- **重启后的账本高峰**：02:56 重启后大约十分钟里，`usd_m` 账本每分钟被用到 600–1 190（平时 20–140）。
  - 能记这本账的只有 worker 里的复盘判定、找相似、索引三路。索引自己每分钟最多 120。
  - 同一时段 `review_jobs` / `review_records` 在持续更新，所以高峰来自复盘判定重启后追数据。
  - 它受 1 200 的上限约束，不会超出币安的额度。但这段时间里的找相似会多排一会儿队。只记录，没改。

## 4. 网关 WS（kanpan-stream-hub）

| 场景 | 结果 |
|---|---|
| 20 连接 × 每连接 8 条流，持续 180 s | 每连接约 11 250 帧，首帧 0.18 s，最大帧间隔 0.29 s，0 断线，0 错误 |
| 单连接订阅到 160 条的上限 | 超出的订阅在 15 ms 内被拒，`429`，`Retry-After: 5` |
| 同一 IP 第 13 个连接 | `503`，符合每 IP 12 连接的上限 |
| 超额 SUBSCRIBE 后的关闭原因 | 写的是 `invalid subscription`（1008），和真正的格式错误分不开。客户端无法区分「超额」与「写错」。**网关问题，只记录**（`Backend/kanpan-gateway` 不在本路范围） |

## 5. 静态资源与首屏

### `curl -I` 结果（只记录：Caddy 配置在 `/etc/caddy/Caddyfile`，不在仓库，也不在本路范围）

- **协议**：HTTP/2 正常，`alt-svc` 声明了 h3。
- **压缩**：只有 gzip。请求 `br`、`zstd` 也只回 gzip，因为 Caddyfile 里只写了 `encode gzip`。
  - 主 JS 原始 500 815 B，gzip 后 182 567 B。
- **缓存头**：`index.html`、带哈希的资源、404 一律是 `cache-control: public, max-age=300`。
  - 带哈希的资源没有 `immutable`，也没有长缓存。
  - `index.html` 不是 `no-cache`：发版后最多 5 分钟内，用户可能拿到旧入口。
  - 404 也被公共缓存。
  - 建议：`/web/assets/*` 用 `public, max-age=31536000, immutable`；`/web/index.html` 用 `no-cache`；404 用 `no-store`。
- **安全头**：HSTS、`X-Content-Type-Options: nosniff`、`X-Frame-Options` 或 CSP `frame-ancestors`、`Referrer-Policy` 全都没有。API 的 JSON 响应也没有 `nosniff`，也没有 `cache-control`。
- **深链**：`/web/某个路由` 回 404。现在网页用的是 hash 路由，所以不影响；以后改成 history 路由时，要在 Caddy 里加 `try_files`。
- **CORS**：API 没有 CORS 层。同源请求正常；外来 Origin 拿不到 `Access-Control-Allow-Origin`，预检回 405。对一个同源应用来说，这是可以接受的拒绝方式。

### 冷启动首屏

测法：本机 Chrome 无头，视口 2560×1440，每轮新开上下文（无缓存、无本地状态），直连、网关各 5 次。数字是中位数 / 最大值，单位 ms，从开始导航算起。

| 线路 | DOM 就绪 | 价格出现 | K 线请求结束 | WS 建连 | WS 首帧 | 首次跳价 |
|---|---|---|---|---|---|---|
| 直连（`fstream.binance.com`） | 1 354 / 1 396 | 1 886 / 1 938 | 2 069 / 2 110 | 2 406 / 2 427 | 2 702 / 2 787 | 3 065 / 3 286 |
| 网关（`/market/stream`） | 1 231 / 1 431 | 1 783 / 2 034 | 2 006 / 2 121 | 2 300 / 2 489 | 2 710 / 2 902 | 2 826 / 2 986 |

- 两条线路的 REST 都是 `fapi.binance.com`，线路只影响 WS。
- **WS 要等 K 线请求结束后才开**，两步是串行的。首次跳价里大约有 0.3–0.4 s 是在等这一步。
  - 建议 Web 端在请求 K 线的同时就建连订阅，推送先缓存，等 K 线到了再对齐。
  - Web 端问题，只记录（本路不改 `Web/`）。

## 6. 发现并修掉的 bug

### Bug 1：刷新与登录被同一个人的同步推送饿死

- **现象**：同一账号 20 路并发同步时，刷新约 4% 回 503，p99 6.5–9.8 s。日志是 `auth.rs` 的 `SELECT … FOR UPDATE OF t,s,u` 等满 5 秒 lock_timeout，报 55P03。
- **根因**：
  - 每个 `personal` 事务开头都对用户行加 `FOR SHARE`。推送一个接一个来时，这一行上始终有共享锁。
  - 刷新和登录对用户行要的是 `FOR UPDATE`（排他锁），所以一直排不上。
- **修法**：刷新改成 `FOR UPDATE OF t,s FOR SHARE OF u`，登录读密码哈希也改成 `FOR SHARE`。
  - 这样挡得住「提交前被停用、删号、改密码」（这些操作是 UPDATE / DELETE / FOR UPDATE，仍会等它）。
  - 同时和 `personal` 事务相容。
- **测试**：新增 `refresh_and_login_are_not_starved_by_a_personal_transaction`。改前是红的，改后是绿的。
- **提交**：`ede4c077`，已推 main。
- **部署**：2026-09-30 02:17:36。kanpan-api 02:18:00 起来。
- **备份**：`/opt/kanpan-backups/stress-20260930-0212/`（`kanpan-api.bin`、`service.env`、`kanpan-api-src.tgz`）。
- **回滚**：
  ```
  cp /opt/kanpan-backups/stress-20260930-0212/kanpan-api.bin /opt/kanpan-api/target/release/kanpan-api
  tar -xzf /opt/kanpan-backups/stress-20260930-0212/kanpan-api-src.tgz -C /opt
  systemctl restart kanpan-api kanpan-worker
  ```

### Bug 2：worker 清理拿着一个人的同步锁跑了两分半

- **现象**：bug 1 部署后马上复测同步（20 并发），02:18–02:20 之间 188 次请求有 162 次回 503。
  - 全部是 `sync.rs` 的 `sync::lock`（`pg_advisory_xact_lock('sync:{owner}')`）等满 5 秒报 55P03。
  - 同一时段 worker 日志里有一条慢语句：`DELETE FROM sync_operations` 用了 145.99 s，结束于 02:20:33，一行都没删。
  - 01:52 那一轮整点清理也有一条，用了 99.6 s。
- **根因**：
  - worker 每小时（以及每次启动）对每个人跑一次 `sync::prune`：先**阻塞地**拿这个人的同步锁，再按 `user_id + created_at` 删 30 天前的回执和变更。
  - 回执表只有 `(user_id, id)` 主键，而 id 是随机 UUID，规划器只能 Seq Scan 整张表。也就是说，每个人每小时都要把所有人的回执堆页读一遍。线上实测 7 876 行占 1 754 页，一次冷读 1 672 页。
  - worker 的连接池没有语句死线，也没有锁死线；而 API 等这把锁只等 5 秒。
  - worker 刚启动的那一轮，正赶上检查点（那次检查点写了 194 s）、全局清理、热力表 ANALYZE 把 IO 占满，这一扫就拖到了 146 秒。整段时间这个人的所有同步都排在锁后面，超时回 503。
- **修法**：
  1. `sync::prune` 先**不拿锁**，用 `past_window` 看一眼有没有到期的回执或变更（最新的那一行变更不算）。
     - 老行只会越来越老，不会有新写进来的老行，所以「没有」这个结论不会被并发推送推翻。
     - 绝大多数人、绝大多数小时根本不碰这把锁。
  2. 有到期的，才用 `pg_try_advisory_xact_lock` 试**一次**。这个人正在同步就让开，下一小时再来。
  3. 拿到锁以后 `SET LOCAL statement_timeout='2s'`，两条删除加起来也短于 API 那边的 5 秒；超时就整批回滚、记一笔。
  4. 同步这一路每批从 5 000 行降到 1 000 行（`maintenance::in_batches_of`），慢盘上也删得完。
  5. 迁移 0034 / 0035：`sync_operations`、`sync_changes` 各加一条 `(user_id, created_at)` 索引，用 `CONCURRENTLY`、`no-transaction`，一个文件一条语句。
     - 线上实测 `past_window` 走 Index Only Scan，只动 4 个缓冲页、0.5 ms。原来那一扫要读 1 672 页。
- **测试**：新增 `pruning_neither_waits_for_nor_hogs_a_persons_sync_lock`，覆盖三点：
  - 没有到期的时候不拿锁。
  - 别的事务攥着这个人的同步锁时，整轮清理 5 s 内跑完、不算失败，他的回执留到下一轮。
  - 拿到锁的事务里语句死线是 2s。
- **提交**：`82dcda1b`，已推 main。
- **部署**：2026-09-30 02:56:00（worker 02:55:58）。部署走的是 `install.py`：先 migrate（34、35 两条，`indisvalid` 都是 t），再由它自己重启一次，之后没有额外重启。
- **只读核对**：
  - kanpan-api、kanpan-worker、kanpan-stream-hub 三个服务都是 active。
  - `/health` 回 200。
  - 部署以后 journal 没有 warning，55P03 为 0 次。
  - 复测结果见第 3 节（同步 10 664 次请求 0 错，刷新 60/60）。
- **备份**：`/opt/kanpan-backups/stress-20260930-0251/`（`kanpan-api.bin`、`service.env`、`kanpan-api-src.tgz`、`schema.sql`）。
- **回滚**：
  ```
  cp /opt/kanpan-backups/stress-20260930-0251/kanpan-api.bin /opt/kanpan-api/target/release/kanpan-api
  tar -xzf /opt/kanpan-backups/stress-20260930-0251/kanpan-api-src.tgz -C /opt
  systemctl restart kanpan-api kanpan-worker
  ```
  - 两条新索引是纯增量，旧二进制用不上也没有害处，不必删。
  - 回滚后**不要**再用旧源码跑 `install.py` 或 `migrate`：`_sqlx_migrations` 里已经记了 34、35，旧源码里没有这两个文件，sqlx 会拒绝。
  - 确实要删索引，用 `DROP INDEX CONCURRENTLY IF EXISTS sync_operations_owner_created, …`，再删掉 `_sqlx_migrations` 里 34、35 两行。

## 7. 没修的问题

1. **订单流热力图冷读慢**（按规则在 2 并发停下，本机和回环的 p95 都在约 3.1–3.2 s）。
   - 原因：
     - 一次请求最多读 720 个快照。
     - 读的是分散在 2.4 GB 表里的冷堆页（随机 IO），VPS 盘的随机读很慢。
     - 聚合排序会溢出到磁盘。
     - 表会长到约 17 GB，冷读只会更多。
   - 没修的原因：这需要改存储形态，比如按段预聚合（rollup）、按块存，或者降低快照上限、调大 `work_mem` 避免排序溢出。这属于订单流功能的设计取舍，改动面大，也牵涉 B 路刚上线的读法，不适合在压测里顺手改。
   - 建议作为下一项单独做：先按 `bucketMs ≥ 150 s` 预聚合，写入时就落成段，读的时候不再扫原始快照。
2. **找相似索引的 census 查询**：`SELECT symbol,div(start_at,$1)… count(*) FROM market_features` 每次 5–6.5 s（等 DataFileRead），在 worker 里周期性地跑，给本来就紧张的 IO 再加一份压力。
   - 它不直接影响用户请求，但会拖慢同一时刻的冷读。
   - 建议把段计数缓存在内存里，写入时增量更新；或者给它一个能走 Index Only Scan 的覆盖索引。本轮只记录。
3. **网关超额 SUBSCRIBE 的关闭原因写成了 `invalid subscription`**，和格式错误分不开。网关问题，不在本路范围。
4. **Caddy**：缓存头、br/zstd、安全头、404 缓存。建议见第 5 节。配置在仓库外，不在本路范围。
5. **Web 端**：
   - WS 要等 K 线请求结束后才建连（首次跳价里约 0.3–0.4 s 花在这里）。
   - 找相似 0 结果时的文案。
   - 这两项归 A/B 路或后续 Web 工作，本路不改 `Web/`。

## 8. 假设与说明

- 「线上有人在用」：所有负载都用 20 并发、2–3 分钟封顶，一到停止条件就停。没有清库，也没有破坏性 SQL。只动了压测账号自己的数据：压测画线用 `stress-c-` 前缀，结束时已通过 `node ops/stress.mjs cleanup` 删掉，并退出登录。
- 本机到 VPS 是跨洋链路。板块历史、订单流历史这类大响应在本机侧的 p95 主要是带宽，所以同时给出 VPS 回环的数字，作为服务端本身的能力。
- 部署了两次，各自是一轮完整流程：备份、`git archive origin/main`、`flock` + `nice` 编译、`install.py` 自己重启一次。两次之后都没有再手动 `systemctl restart`。
- `GET /v1/market/orderflow/flow` 仍然是 404。分支 `worktree-agent-ad34e577157c31d5f` 没有推，没有部署，也没有测。
- worker 的日志级别是 `warn`（外加几个模块开 info），索引的 info 日志看不到，所以回填进度用 `pg_stat_user_tables.n_tup_ins` 代替观察。
- 没有命令被权限分类器拒绝。
