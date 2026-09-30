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
  - **订单流热力图冷读**压测时 2 并发就超过 p95 2 s，按规则停了。**09-30 已修**：写入时落三档预聚合段、读时先读段，复测见第 7 节第 1 项。
- **找相似**：9 次搜索全部完成，同一账号第二个并发请求一律 `429 search_busy`。9 次里有 2 次结果是 0，那是分数门槛挡掉的，不是 bug；网页端的空结果说明归 W 路修（`aada4abb`）。
- **静态资源**：HTTP/2 正常。压测时缓存头、压缩、安全头都不理想；**09-30 09:54 已改好上线**（zstd / gzip、带哈希资源一年 immutable、入口 no-cache、404 no-store、HSTS 等四个安全头），逐条核对见第 7 节第 6 项。
- **压测遗留的服务端 / 网关 / Caddy 项，09-30 全部从根因修掉并上线**：热力冷读、census 整表扫、重启后的权重高峰、重启空窗的 502、网关关闭原因、Caddy 头，另外新增了网页板块走势线要的小时收盘接口。修的过程中又挖出两个存量问题（网关测试夹具在忙机上假红、glibc 分配器让内存用例在 Linux 上一直红），一并修了。明细与数字见第 7 节。
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
| 订单流热力 `heat`（改前） | 本机和回环 | 2（停） | — | 0 | — / 约 3 100–3 200 / — | 冷读慢；09-30 已修，改后复测见第 7 节第 1 项 |
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
  - 网页端的空结果说明归 W 路修（`aada4abb`：左右两栏都说明为什么是空的，门槛按周期取，与服务端一致）。
- **回填让路**：代码里 `market_index` 的循环在 `search::busy()`（90 秒内有过领取）、闸门按着、或账本没空间时整个让开。
  - 但这次压测时公开历史索引已经补齐（`market_features` 的写入从 02:28 起一直是 655 494），回填处于空闲，线上没法观察到「正在回填时被搜索挤开」。
  - 采样里能看到的是：找相似跑的那几分钟，账本满了以后搜索自己排队，没有任何失败。
- **重启后的账本高峰**（压测时的观察）：02:56 重启后大约十分钟里，`usd_m` 账本每分钟被用到 600–1 190（平时 20–140），worker 连着几分钟 `provider_budget_exhausted`。
  - 压测时以为高峰来自复盘判定追数据。09-30 查实：账本只有一列 `used`，预留时加上去、回头再和币安回头里的 `x-mbx-used-weight-1m` 取大——而那个头是**整个出口 IP** 的，含 serve 订单流重启后补快照的每分钟约 600。worker 拿「全 IP 已用」去比自己的 1 200，serve 的流量被扣了两遍，所以重启后 worker 整分钟被拒。
  - **09-30 已修并上线**：分成 `reserved`（worker 自己）与 `used`（全 IP）两列、两道闸，后台任务每分钟封顶 900、搜索 1 200、全 IP 1 800。重启后采样见第 7 节第 3 项。

## 4. 网关 WS（kanpan-stream-hub）

| 场景 | 结果 |
|---|---|
| 20 连接 × 每连接 8 条流，持续 180 s | 每连接约 11 250 帧，首帧 0.18 s，最大帧间隔 0.29 s，0 断线，0 错误 |
| 单连接订阅到 160 条的上限 | 超出的订阅在 15 ms 内被拒，`429`，`Retry-After: 5` |
| 同一 IP 第 13 个连接 | `503`，符合每 IP 12 连接的上限 |
| 超额 SUBSCRIBE 后的关闭原因 | 压测时写的是 `invalid subscription`（1008），和真正的格式错误分不开。**已修（09-30 09:57 上线两台节点）**：超额回 1008 `subscription limit exceeded`，格式错误仍回 1008 `invalid subscription`。公网真实 WS 客户端两台节点各验一次，见第 7 节第 5 项 |

## 5. 静态资源与首屏

### `curl -I` 结果

> 下面是压测当时（改前）的状态。**缓存头、压缩、安全头、404 缓存都已在 09-30 09:54 改好上线**，改后逐条核对见第 7 节第 6 项。
> 站点块在 `/etc/caddy/Caddyfile`（仓库外），它 import 的路由在仓库里 `Backend/kanpan-gateway/Caddy.routes`。

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
  - 修法：Web 端在请求 K 线的同时就建连订阅，推送先缓存，等 K 线到了再对齐。
  - 归 W 路修（`aada4abb` 已在 main 上：WS 首帧直连 1 457 → 754 ms、网关 1 361 → 629 ms，各 10 次中位数）。

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

## 7. 压测遗留项（09-30 全部修掉并上线）

压测当晚只记录、没修的几项，09-30 由 C 路接着从根因修掉。

**部署记录**：

- **Caddy**：09:54，只在 orderflow-vps。
- **网关**：两台，orderflow-vps 09:57、trade-vps-old 09:58。
- **kanpan-api**：11:21，一次完整流程：
  1. 备份；
  2. rsync 源码，核对差异正好是本次的 16 个文件；
  3. `flock` + `nice` 编译，用时 3 分 54 秒；
  4. `install.py` 跑一次，11:20:42 → 11:21:27。它自己跑迁移 0037–0040 并重启，之后没有再手动 `systemctl restart`。

**只读核对**：

- 三个服务都是 active，`/health` 200。
- 11:21 以后 journal 没有 error，warn 只有三类：
  - 80 条是热力预聚合追历史时的慢语句（每条 7–12 s，追平后不再出现，见第 1 项）；
  - 2 条是启动时 census 的首次计数；
  - 37 条是 `market_meta` 对 ETF 的供应量页面「答成了别家公司、不发布」。这是存量保护，02:55 那次重启时也是 37 条。

### 1. 订单流热力图冷读慢 —— 已修

- **根因**：
  - 一次请求最多抽 720 个原始快照，读的是分散在 2.4 GB 热力表里的冷堆页。
  - VPS 盘的随机读慢，2 并发 p95 就到 3.1–3.2 s。
  - 表会长到约 17 GB，越往后越慢。
  - 这不是参数问题，是读的时候在现算本该写入时就算好的东西。
- **修法**：
  - **迁移 0038**：`orderflow_heat_rollup`，按段宽 LIST 分区成 `_30s` / `_150s` / `_900s` 三张子表。
  - **写入侧**：`src/orderflow_history/heat.rs:83` `ROLLUPS`、`:323` `roller`。
    - 常驻任务每 30 秒把已收完的原始快照并成 30 s 段，再由 30 s 段并成 150 s 段、由 150 s 段并成 900 s 段。
    - 每格保存样本数，平均值按样本数加权，和直接从原始快照算的结果一致。
    - 首次上线从最老的数据一段段追。
  - **读取侧**：`heat.rs:633–646`、`:357` `pieces`。
    - 格宽是哪一档段宽的整数倍，就用最粗的那一档段；段还没盖到的头尾（最多几十秒）才读原始快照。
    - 接口契约、参数、响应都不变。
  - 滚动删与原始表同一保留期（`delete_rollups_before`）。
  - 测试：`pieces_use_the_coarsest_rollup_that_divides_the_cell_and_raw_for_the_rest`，以及 `rollups_average_every_snapshot_and_reads_stitch_them_with_raw`（数据库用例，逐格比对段与原始快照的结果）。
- **复测**（rollup 11:50:09 追平以后，`node ops/stress.mjs heat --stages 2,5,10`，账号 webstress_c0929，全程 0 错）。三条路径分开测，才能把服务端和链路分开：

  | 路径 | 2 并发 p95 | 5 并发 p95 | 10 并发 p95 | 次数 / 时长 |
  |---|---|---|---|---|
  | VPS 回环直连 8794（只有服务端） | 99 ms | 235 ms | 398 ms | 6 707 次 / 151 s |
  | VPS 上经公网域名走 Caddy + TLS | 92 ms | 205 ms | 344 ms | 4 236 次 / 90 s |
  | 本机（上海）→ 线上，第一轮 | 787 ms | 1 700 ms | 6 654 ms（触发停止规则） | — |
  | 本机 → 线上，第二轮 | 309–360 ms | 1 091–1 459 ms | 3 884 ms，停（ttfb p95 930 ms） | — |

  - 改前是 2 并发 p95 3.1–3.2 s，而且是在服务端内部就慢。改后服务端和 Caddy 在 2 / 5 / 10 并发都是 **p95 < 0.4 s**，目标 p95 < 1 s 在服务端这一侧满足。
  - 本机端 5 / 10 并发超过 1 s，瓶颈是本机到 VPS 的跨洋带宽，不是服务端：
    - 单个热力响应 gzip 后 100–180 KB（解压后约 462 KB）。
    - 实测本机到 VPS 的总吞吐：同一个 146 KB 的静态 JS，10 路并行拉 30 次，墙钟 4.65 s，合计 **0.94 MB/s**；单条不压缩下载 340 KB/s。
    - 10 个并发分这约 1 MB/s，每条只有约 0.1 MB/s，一个 150 KB 的响应光传输就要 1.5 s 左右。
    - 同一轮里 ttfb p95 只有 930 ms，总时长却到 3.9 s，也就是首字节快、传输慢，正是带宽被分摊的特征。
    - 这和压测当晚订单流 history 那一项的结论一致（第 3 节）。
    - 真实用户一个人一次只开一张热力图，不会 10 个并发同时拉。单用户单请求 1.0–1.5 s，其中新建 TLS 的 ttfb 约 0.58 s。

### 2. 找相似索引的 census 整表扫 —— 已修

- **根因**：`market_index` 的 census 按 `symbol, div(start_at)` 分组计数，只能对 68 万行、660 MB（带 HNSW 向量列）的 `market_features` 并行顺序扫描。
  - 每次 5–6.5 s，而且每一轮循环都跑一次。
  - 09-30 03:00–11:00 这 8 小时，journal 里这条慢语句有 **1 158 条**，约 25 秒一次。
- **修法**：
  - **覆盖索引**：迁移 0039 `market_features_census`，等值列在前、`symbol, start_at` 在后、`bars_count` 放 INCLUDE，用 `CONCURRENTLY` 建。整条查询走 Index Only Scan，不回表。
  - **进程内缓存**：`src/market_index.rs:81` `RECOUNT`，`:419` 起。
    - 进程里记一份段计数，自己写进去的窗口自己加。
    - 一小时，或删过旧窗口、换过品种表时，才重数一次。
- **`EXPLAIN (ANALYZE, BUFFERS)`**（1h 档，47 只）：

  | | 计划 | 执行时间 | 缓冲 |
  |---|---|---|---|
  | 改前 | Parallel Seq Scan | 6 155.8 ms | hit 46 115 / read 39 146 |
  | 改后 | Index Only Scan using `market_features_census`（Heap Fetches 18 235） | 1 983.3 ms | hit 37 072 / read 0 |

- **线上**：
  - 上线后只在启动时数了一次，两条分别 1.25 s、1.71 s。
  - 此后 journal 里这条慢语句 0 条（改前约 25 秒一条）。
  - 索引 `indisvalid = t`，78 MB。

### 3. 重启后的币安权重高峰 —— 已修

- **根因**：见第 3 节「重启后的账本高峰」。
  - 账本只有一列 `used`，又拿整个出口 IP 的已用（含 serve 订单流补快照的每分钟约 600）去比 worker 自己的 1 200。
  - serve 的流量被扣了两遍，重启后 worker 连着几分钟被拒。
- **修法**：迁移 0040 给 `provider_budgets` 加 `reserved` 列。
  - `vendor/scorebook-market/src/adapters/provider_budget.rs:133` `admits`：一次预留要同时过两道闸。
    - `reserved + w ≤ 份额`：worker 自己的账。
    - `used + w ≤ 1800`：全 IP，`KANPAN_BINANCE_IP_WEIGHT_CEILING`，币安上限 2 400 的四分之三。
  - `src/review_market.rs:93` `BACKGROUND_SHARE = 75`：复盘判定与找相似索引这两条后台任务只拿 1 200 的 75%，即每分钟 900。剩下 300 留给用户在等的找相似搜索。
  - **每分钟的明确上限**：后台 ≤ 900，搜索 ≤ 1 200，全 IP ≤ 1 800。
- **重启后采样**（11:21 部署，每 5 秒读一次账本，15 分钟，每分钟取最大）：

  | 分钟 | `used`（全 IP） | `reserved`（worker） |
  |---|---|---|
  | 11:21（重启那一分钟，新旧两个 serve 都在出站） | 1 226 | 120 |
  | 11:22–11:26（serve 订单流补快照） | 777–967 | 180–200 |
  | 11:27–11:34（小时收盘首次回填还在跑） | 262–330 | 180–200 |
  | 11:35–11:36（回填结束） | 126–189 | 120–180 |

  - `reserved` 最高 200，离后台上限 900 很远；`used` 最高 1 226，低于 1 800。
  - 这段时间没有一条 `provider_budget_exhausted`；02:56 那次重启后是连着几分钟。
- 11:21–11:34 新上线的小时收盘在做首次回填（每秒一只、每只权重 2，约每分钟 120），也记在 `used` 里；回填一结束 `used` 就回到 200 以下。

### 4. `meta` 偶发 502（A 路报告第 163 行）—— 已修

- **根因**：`kanpan-api serve` 重启时先关监听口，再等订单流收尾与在途请求。
  - Stopping → Started 实测约 2.1 s，这段时间 8794 没人监听。
  - Caddy 只有一个上游，当场回 502。
  - `install.py` 部署、supervisor 拉起都会碰上。
- **修法**：
  - `Backend/kanpan-gateway/Caddy.routes:14–15` 等三处：每个上游都带 `lb_try_duration 20s` / `lb_try_interval 250ms`。连不上就挂着每 250 ms 重试；请求还没发出去，所以 POST 也安全。
  - 优雅停机核对过：先关监听口，再在途答完。
  - `ops/install.py:144` 的 `TimeoutStopSec=15` 给收尾卡住的最坏情况封顶，保证空窗落在 20 s 以内。
  - `install.py` 的重启顺序核对过，已经是最短空窗的顺序，所以没改：
    - 先 `migrate`，这时服务还没停。这次 0039 用 `CONCURRENTLY` 建索引花了 22 s（11:21:02 → 11:21:24），旧进程全程照常答。
    - 迁移都是纯增量，旧二进制在新表结构上照跑。
    - 然后 `daemon-reload`，再对两个单元只 `try-restart` 一次。
    - 空窗只剩 Stopping → Started 的 2 s（11:21:24 → 11:21:26），这一段交给 lb_try 挂住。
    - 再往下缩就得让新旧进程交接监听口（socket 激活），而 lb_try 已经让这 2 s 对用户不可见，不值得。
  - trade-vps-old 没有 8794 上游，那台的 Caddy 不加重试，否则那几条本来就连不上的路径会白挂 20 s。
- **验证**：部署前后 25 分钟，在 VPS 上循环打公网 `/v1/market/meta`（每 0.2 s 一次，11:15:47–11:40:47，跨过 11:20:42 起的 install.py 与 11:21:24 的重启）：**6 366 次，全部 200，非 200 为 0**。超过 2 s 的 45 次：44 次 5.08–5.14 s，1 次 7.85 s。
  - 11:21:19 发出的那一次用了 7.85 s，时间上正好跨过 11:21:24 → 11:21:26 的重启空窗，**回的是 200**。
  - 循环里零星的 5.1 s 是 VPS 自己解析 sslip.io 的 DNS 超时（`resolv.conf` 用 8.8.8.8，默认 5 s 超时），部署前就有，与服务端无关。
    - 实测：同一台机器上裸做 150 次 `getaddrinfo`，2 次 5.0 s，中位数 3.7 ms。
    - 同期 40 次 curl 的连接到首字节都在 0.11 s 左右。

### 5. 网关超额 SUBSCRIBE 的关闭原因 —— 已修

- **根因**：`stream_hub.py` 里超额与格式错误都抛 `ValueError`，一起落到 `1008 invalid subscription`。客户端分不清是「写错了」还是「订多了」。
- **修法**：
  - `Backend/kanpan-gateway/stream_hub.py:41` 新增 `class OverLimit(ValueError)`。
  - `streams()` 超过上限（`:53`）和整连接超额（`:275`）都抛它，关闭帧 `1008 subscription limit exceeded`（`:278`）。
  - 格式错误仍是 `1008 invalid subscription`。
  - 新增测试 `test_over_the_cap_and_malformed_close_with_different_reasons`。
- **上线**：
  - orderflow-vps 09:57，备份 `/opt/kanpan-backups/gateway-c0930-20260930-095735`；
  - trade-vps-old 09:58，备份 `/opt/kanpan-backups/gateway-c0930-20260930-095825`；
  - 新文件 sha256 前缀 `7e606263`（旧 `34c98771`）。
- **验证**：用公网真实 WS 客户端，两台节点各打一次：
  - 一次 SUBSCRIBE 70 条流 → `1008 subscription limit exceeded`；
  - 格式错误 → `1008 invalid subscription`。

### 6. Caddy 缓存头、压缩、安全头 —— 已修

- **改了什么**：`/etc/caddy/Caddyfile` 的 kanpan 站点块（仓库外），以及它 import 的 `Backend/kanpan-gateway/Caddy.routes`。
  - `encode zstd gzip`。
  - `/web/assets/*`、`/web/m/assets/*` 回 `public, max-age=31536000, immutable`。
  - 入口页（`/web/`、`/web/index.html`、`/web/m/`、`/web/m/index.html`）、manifest、`sw.js` 回 `no-cache`。
  - 404 回 `no-store`。
  - 全站加 `Strict-Transport-Security: max-age=31536000; includeSubDomains`、`X-Content-Type-Options: nosniff`、`Referrer-Policy: strict-origin-when-cross-origin`、`X-Frame-Options: DENY`，不加 CSP。
  - API 用 `header ?Cache-Control "no-store"`（`Caddy.routes:24` 等）：`?` 只在上游没写时补，所以接口自己定的缓存保持不变。
  - `@account` 补上 `shares`、`friends` 两条路径。
- **上线**：
  - 09:54；备份 `/etc/caddy/Caddyfile.bak-20260930-095422`、`/opt/kanpan-gateway/Caddy.routes.bak-20260930-095422`。
  - 先 `caddy validate` 过了。
  - 这台 Caddy 配的是 `admin off`，`reload` 必然失败，只能 `restart`，全站断约 2 s。
  - Trader Foresight 那一段一字未动：改前改后 diff 相同，站点照旧回它自带 basicauth 的 401。
- **`curl -I` 逐条核对**：

  | 路径 | cache-control | 其他 |
  |---|---|---|
  | `/web/`、`/web/index.html`、`/web/m/`、`/web/m/index.html`、manifest、`sw.js` | `no-cache` | |
  | `/web/assets/*.js` | `public, max-age=31536000, immutable` | `content-encoding: zstd` |
  | 图标 | `public, max-age=300` | |
  | 404（含 `/web/assets/nope.js`） | `no-store` | |
  | `/v1/market/meta`、`/v1/shares` | `no-store` | |
  | heat / 板块历史 / flow / 小时收盘 | 保持接口自己的 `max-age=5` / `3600` / `20` / `300` | |

  - 以上响应都带 HSTS、nosniff、Referrer-Policy、`X-Frame-Options: DENY`。
  - `/web/m/assets` 线上目前还不存在，matcher 已经覆盖。

### 7. 小时收盘接口（网页板块走势线要的）—— 新增并上线

- **为什么要**：网页板块页原来为走势线直连币安，每只打一段 1 小时 K 线，冷启动几百次请求、占浏览器所在 IP 的权重。
- **改了什么**：
  - `src/hourly_close.rs`（新建），迁移 0037 `hourly_close(symbol, hour_ms, close)`，`src/lib.rs:115` 挂路由，`src/main.rs:95` 常驻。
  - 全部 U 本位永续每个整点过 1 分钟扫一遍，一秒一只、一次一只，出站前看 `binance_gate`。
  - 启动时回填 170 小时，保留 8 天、滚动删。
  - 契约见 `docs/网页版-小时收盘接口-2026-09-30.md`：
    - `GET /v1/market/hourly-closes?symbols=`，最多 200 只、大写；
    - 回 `200 {"asOf","hours":170,"series":{…}}`，只给已收盘的小时，没数据的键不出现；
    - `Cache-Control: public, max-age=300`；
    - 参数不合法回 400 `{"error":"invalid_symbols"}`，不套信封。
- **验证**：
  - `BTCUSDT`、`ETHUSDT` 各 170 根。
  - 粉丝代币板块的 `CHZUSDT`、`ASRUSDT`、`ALPINEUSDT` 各 170 根。
  - 最新一根是上一个整点，回填约 12 分钟完成（库里 778 只合约，含 USDC 计价）。
  - 整点扫描实测（12:00 上海 = 04:00 UTC 那一轮）：
    - 04:01 开跑，按字母顺序一秒一只；04:04 时 BTC、CHZ 已补上 03:00 UTC 那一根，778 只里 222 只已补齐。
    - 这一轮约 13 分钟扫完。在这之前，还没轮到的合约最新一根停在 02:00，`series` 少一根（169 根），不会给出未收盘的数据。
  - 这个模块每轮的汇总是 INFO 日志，线上 `RUST_LOG=warn,…` 只放行 alerts、apns、orderflow_history 的 INFO，所以 journal 里看不到汇总；取失败、被 `binance_gate` 拦的 WARN 照常出现。上面的核对都是直接查库。
  - 不存在的 `NOSUCHUSDT` 不出现在 `series` 里。
  - 小写、空、带连字符、缺参数、201 只，都回 400 `{"error":"invalid_symbols"}`。
- **网页端复验**（W 路的 `node Web/scripts/firstscreen.mjs https://kanpan.107-174-172-10.sslip.io/web/ sectors 20`）：
  - 28 个板块 28 个有走势线，点名的比特币生态、基础设施、粉丝代币、DeFi 其他都有线；
  - 走势线只打了 2 次 `hourly-closes`；
  - 直连币安的 K 线剩 6 次：5 次是中文名合约（哈基米、币安人生、我踏马来了、牛来、龙虾，按契约不在服务端代号范围内，网页走直连），1 次是图表本身。

### 8. `GET /v1/market/orderflow/flow` —— 已上线，在累积

- 这条接口由 `f6bb4aa1`（迁移 0036）在 C 路之前上线。第 8 节原来写的「仍是 404」已过时。
- 11:26 取 `?base=BTC`：200，`Cache-Control: public, max-age=20`，182 行分钟数据，覆盖最近约 3 小时。
- 11:37 再取：195 行，最新一分钟从 11:23 推到 11:36，正好多了 13 行；库里 BTC 从 08:22（上海时间）起到 11:36，一分钟一行，数据在持续累积。

### 9. Web 端两项 —— 归 W 路修

- WS 等 K 线请求结束后才建连：`aada4abb` 改成同时发，WS 首帧直连 1 457 → 754 ms、网关 1 361 → 629 ms。
- 找相似 0 结果的说明：同一提交。

### 10. 修的过程中挖出来的两个存量问题 —— 已修

1. **网关测试在忙机上假红**：`test_stream_hub.py` 的 100 客户端用例在 VPS 上回 503，改动前的原版也一样。
   - 根因：测试里的 Hub 用的是真的 `HostSampler`，它每 5 秒读 `/proc`。VPS 在编译、负载约 10 时，它把 `Capacity(128)` 缩到 25 个客户端。macOS 上没有 `/proc`，所以一直是绿的。
   - 修法：夹具换成 `QuietHost`（不报压力），主机压力那条路径另有 `BudgetTests` 覆盖。
   - 验证：修后负载 9.9 时 99 条全过。
2. **`tests/stress_review_export.rs` 的内存用例在 Linux 上一直红**：改动前也红，导出 +181 MiB、下载 +205 MiB 超线。
   - 根因：glibc 的两个默认。
     - 每线程一个 arena，各自攥着释放的内存。
     - mmap 阈值是动态的，释放大块之后抬到 32 MB，此后十几 MB 的缓冲都从堆里拿、还回去也不交给系统。
     - 线上单元有 `MemoryMax=1G`，而订单流跟踪也在同一个进程里，这一点在线上是真风险，不只是测试问题。
   - 修法：
     - `ops/install.py:140` 两个单元都带 `Environment=MALLOC_ARENA_MAX=2 MALLOC_MMAP_THRESHOLD_=1048576`；
     - 内存用例的子进程用同一组值；
     - `src/lib.rs` 新增 `both_services_pin_the_glibc_allocator` 锁住两处一致。
   - 实测（MiB）：

     | 场景 | 默认 | 改后 |
     |---|---|---|
     | 8 次 12 MB 导出同时到 | +181 | +42～+46，做完只留 +23 |
     | 40 次补图下载同时到 | +166～+205 | +54～+61 |
     | 导出耗时 | 约 4.0 s | 3.3–4.5 s |

   - 上线后两个进程的 environ 里都有这两个变量。部署后 2 分钟窗口：kanpan-api CPU 51%（改前 58%），匿名内存 146 MiB。

**测试**：VPS 上 `cargo test --release --workspace --no-fail-fast`，33 组全绿，唯一红的是 `stress_review_export`（存量，见第 10 项第 2 条）。修后 lib 531 过，`stress_review_export` 5 条全过，vendor 的 scorebook_core 19、scorebook_market 3 都过；网关 `test_stream_hub.py` 全过。

**一次意外，如实记录**：

- 09:47 在 VPS 上跑 `cargo test --release` 时用的是共享的 `CARGO_TARGET_DIR=/opt/kanpan-api/target`，cargo 顺手把 `target/release/kanpan-api` 重新链接成了新源码编出来的版本。
  - 正在跑的进程不受影响，它用的是已经载入的旧映像。
  - 但盘上那份已经不是线上那份了。
- 发现后立即用 `/proc/<pid>/exe` 恢复成线上原样（sha256 `a0f5b413…`），期间没有重启。
- 之后的备份脚本一律从 `/proc/<pid>/exe` 取二进制。

**kanpan-api 备份与回滚**：

- 备份：`/opt/kanpan-backups/c0930-20260930-111552/`，内含 `kanpan-api.bin`（`a0f5b413…`，改前在跑的那份）、`service.env`、`kanpan-api-src.tgz`、`schema.sql`。
- 回滚：
  ```
  cp /opt/kanpan-backups/c0930-20260930-111552/kanpan-api.bin /opt/kanpan-api/target/release/kanpan-api
  tar -xzf /opt/kanpan-backups/c0930-20260930-111552/kanpan-api-src.tgz -C /opt
  systemctl restart kanpan-api kanpan-worker
  ```
- 迁移 0037–0040 都是纯增量（新表、新索引、新列带默认值），旧二进制用不上也没有害处。回滚后同样**不要**用旧源码跑 `install.py` / `migrate`。

## 8. 假设与说明

- 「线上有人在用」：所有负载都用 20 并发、2–3 分钟封顶，一到停止条件就停。没有清库，也没有破坏性 SQL。只动了压测账号自己的数据：压测画线用 `stress-c-` 前缀，结束时已通过 `node ops/stress.mjs cleanup` 删掉，并退出登录。
- 本机到 VPS 是跨洋链路。板块历史、订单流历史这类大响应在本机侧的 p95 主要是带宽，所以同时给出 VPS 回环的数字，作为服务端本身的能力。
- 压测当晚部署了两次（02:17、02:56），09-30 修遗留项时 kanpan-api 又部署了一次（11:21）。
  - 每次都是一轮完整流程：备份、同步源码、`flock` + `nice` 编译、`install.py` 自己重启一次，之后都没有再手动 `systemctl restart`。
  - 09-30 那次的源码是把 C 路 worktree 的改动 rsync 上去的（先核对差异正好是本次的文件），不是 `git archive origin/main`，因为这些改动要等主窗口 cherry-pick 后才进 main。
- `GET /v1/market/orderflow/flow`：压测当晚是 404；此后 `f6bb4aa1` 已上线，09-30 核对返回 200、数据在累积，见第 7 节第 8 项。
- worker 的日志级别是 `warn`（外加几个模块开 info），索引的 info 日志看不到，所以回填进度用 `pg_stat_user_tables.n_tup_ins` 代替观察。
- 没有命令被权限分类器拒绝（压测当晚和 09-30 修遗留项时都没有）。
