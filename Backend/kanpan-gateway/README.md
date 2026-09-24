# 看盘轻量行情网关

两台已部署的公开行情入口：

- 主节点：`kanpan.107-174-172-10.sslip.io`
- 备用节点：`kanpan.96-44-162-222.sslip.io:8443`（该机443已有业务，保留原服务）

只处理公开行情，不接收交易/API密钥/账户数据，不提供任意 URL 转发。

客户端怎么选线路是 app 那边的事，2026-09-17 已经定死：设置里「行情线路」两档由用户自己选，**没有自动切换**——选「直连」就只走币安自己的域名，选「网关」才走到这两台上来。本文早先写的「比较用户地址、官方和两台网关的首条有效行情、断线后重选」那套自动择路已经不存在了。走网关时两台之间仍然竞速，败选连接立即关闭，首帧不会丢失；某台报 429 / 503 就按它给的 `Retry-After` 歇一会儿——本机忙（`{"error":"busy"}`）是几秒的事，**上游限流（`{"error":"upstream_rate_limited"}`）给的可能是 120 秒，不许再按 10 秒截断**，详见下面的失败线契约。

历史 K 线通过受限的 `/market/v1/*` 接口按 `source=binance|okx` 取数，响应会明确返回品种、周期和来源。网关不会把失败的 Binance 请求伪装成 OKX，也不拼接两个交易所的 K 线。客户端选了网关就整套取 OKX，选了直连就整套取币安，不会在两边之间自动来回。近期 K 线不从归档站伪造，服务端只访问固定的 Binance/OKX 公开市场接口。

## 共享实时订阅

`/market/stream?streams=…`由独立aiohttp服务处理：每节点只有一条固定币安上游WS，所有客户端的同名频道合并订阅，最后一个订阅者离开才退订；无客户端时释放上游。保留双向SUBSCRIBE/UNSUBSCRIBE语义。每个慢客户端只留每频道最新一条待发真实帧，不落盘，不向新客户端重播旧报价。例外是`<symbol>@aggTrade`：每一笔成交都要算进主动买卖量，所以逐帧排队不合并（仍受每客户端待发上限约束，超出就断开让它重连），走的仍是同一条`/market`上游（实测`/public`不推成交）。OKX线路（`/market/okx/stream`）只转ticker与K线，不接受`@aggTrade`。旧版订单流用过的`<symbol>@depth@100ms`（币安`/public`上游、OKX `books`/`trades`映射，原`depth_relay.py`）已被kanpan-api的`/v1/market/ws/*`中继取代，2026-09-24删除，两条线路握手时都按非法频道拒绝。共享上游不等于下行免费：客户端数量增加仍消耗出站带宽和连接资源。

允许ticker、markPrice@1s、aggTrade和图表支持的kline周期（`depth@100ms`等深度流不再放行）；不允许用户指定上游URL、交易或账户API。每连接最多64频道、每来源最多160不同频道、每节点最多512频道。订阅消息有大小和速率限制；单来源握手、并发与总键数有界；慢发送超时断开，避免阻塞其他客户端。Caddy覆盖客户端来源头，公网自行填写同名头不能伪造来源。

当前匿名应用用可信连接IP隔离滥用，不宣称能识别独立自然人。共享NAT也共享来源配额。正常自选与主图每App通常两条连接；上限针对异常占用。应用层限制不替代运营商对大规模网络攻击的防护。

## 宿主资源预算

只读检查主机分别为7核/约8GB和3核/约4GB，部署时空闲内存约5.1GB/3.2GB、负载较低。先采用保守预算：主节点128连接、1.5MB/s应用出站；备用64连接、0.75MB/s。它们是上线保护参数，**不是压测得出的最大承载人数或供应商带宽保证**。

每5秒采样宿主CPU、可用内存、服务RSS、默认出口发送速度。压力升高时逐步减少新连接及发送预算，回落时缓慢恢复，避免抖动。整个服务由systemd限制1GB内存、300%CPU（备用节点用`kanpan-stream-hub.service.d/10-standby-node.conf`降为150%）、256任务；历史服务独立受限。预算在`/etc/kanpan-gateway/limits.env`配置（默认`MAX_CLIENTS=512`、`EGRESS_BYTES_PER_SECOND=6000000`、`MEMORY_BUDGET_BYTES=1073741824`、`HOST_EGRESS_BYTES_PER_SECOND=20000000`），不影响同机其他应用。公开HTTP健康接口只返回必要服务状态。

## 历史 K 线与 OI

- `/market/v1/klines?source=okx&symbol=BTCUSDT&interval=1m&limit=300`：受限的 OKX/Binance 统一 K 线格式；`source` 必须明确，服务端校验 OHLCV、连续性、时间范围和 USDT 永续品种。
- `/market/v1/ticker?source=okx&symbol=BTCUSDT`：当前源的 24h 行情。
- `/market/v1/tickers?source=okx`：当前源的**全市场** 24h 行情（板块页用），详见下面那一节。
- `/market/v1/instruments?source=okx`：当前源的 USDT 永续品种表；OKX 的 `state` 按状态机原样透传成币安的 `status`（`live`→`TRADING`、`preopen`→`PENDING_TRADING`、`suspend`→`BREAK`），非交易中的合约**仍然列在表里**、其余字段照常合成，客户端才分得清「待上市」「临时停牌」和「没有这个品种」；`test`（OKX 自己的测试合约）不输出，其他没见过的 `state` 也不输出并在日志里记一条（每个值每进程一次），绝不拿 `TRADING` 兜底。临时停牌（`suspend`）的合约照样能取 K 线和 ticker——目录里既然说它在，图就不能回 503；`preopen` 等还没成交过的状态仍然不给数据。

历史分页按时间游标继续请求，不把短响应误判为历史耗尽；缺口、来源不匹配或上游不可用都返回失败。主节点失败后按顺序尝试备用节点，客户端只在两台网关都不可用时报告失败。

OKX 的字段按**单位**对齐，不按名字对齐：ticker 的 `volCcy24h` 是 24 小时的**币数量**，只放进币安语义的 `volume` / WS `v`；OKX V5 的 ticker 根本没有计价成交额（`vol24h` 是张数），所以 `quoteVolume` / WS `q` 一律留空，REST 与 WS 两条路一致。不拿 `volCcy24h × last` 估一个「额」出来冒充——那是用一个瞬时价给一整天的成交定价，手机上显示 `--` 才是真话。K 线三个量各就各位：`vol`（张）不发，`volCcy`（币）进 row[5] / WS `k.v`，`volCcyQuote`（USDT）进 row[7] / WS `k.q`。`instruments` 只在 OKX 自己的字段能证明时才写 `underlyingType: "COIN"`（`instType=SWAP`、`ctType=linear/inverse`、`ctValCcy` 就是基础币、`uly` 与 `instFamily` 都是 `<币>-<结算币>`），证明不了就不写这个字段，让客户端保守处理，绝不把类型不明的合约一律补成币。

### `/market/v1/tickers`：网关模式的全市场行情

    GET /market/v1/tickers?source=okx

只读，只认 `source` 一个参数（`okx` 或 `binance`），**不带 `symbol`**；多给任何一个参数都是 400。OKX 侧一次请求取全场（`/api/v5/market/tickers?instType=SWAP`），不分页——用户规模小，几百个品种一份 JSON 比几百笔单品种请求便宜得多。走和单品种 ticker 相同的小请求池、相同的冷却与限流契约（上面那张表照用）。服务端缓存 **5 秒**：三台手机同时看板块页，这个端点每 5 秒最多打上游一次。

信封与单品种 `/market/v1/ticker` 完全一样——同一个 `source`、同一个 `symbol`、同一个 `ticker` 载荷键；区别只是 `symbol` 是空串、`ticker` 是数组：

    {"source":"okx","symbol":"","ticker":[{...},{...}]}

（为此单品种那条也补上了 `symbol`，两条路的信封字段集一字不差。）

数组里每个元素与单品种 `/market/v1/ticker` 的字段映射**逐字段相同**，就是币安 `ticker/24hr` 的形状：

| 字段 | 类型 | 来源 |
| --- | --- | --- |
| `symbol` | 字符串 | 币安风格代号，`BTC-USDT-SWAP` → `BTCUSDT` |
| `lastPrice` | 字符串 | OKX `last` |
| `openPrice` | 字符串 | OKX `open24h` |
| `highPrice` | 字符串 | OKX `high24h` |
| `lowPrice` | 字符串 | OKX `low24h` |
| `volume` | 字符串 | OKX `volCcy24h`（24 小时**币数量**，就是币安 `volume` 的单位） |
| `quoteVolume` | 字符串 | **永远是空串**：OKX V5 ticker 没有计价成交额（`vol24h` 是张数），不估算 |
| `priceChange` | 字符串 | `last - open24h` |
| `priceChangePercent` | 字符串 | `(last / open24h - 1) × 100`，`open24h` 为 0 时是 `0` |
| `closeTime` | 整数 | OKX `ts`（毫秒） |

没有 `openTime`，也没有 `count`：OKX 给的是一个滚动 24 小时窗口、不给窗口起点，也不给成交笔数。单品种那条同样没有这两个字段——「单品种有的这里都有」，单品种没有的这里也不凭空算一个出来（拿不到可靠数据就留空）。

只输出 `/market/v1/instruments` 已经合成出来的那些品种：板块页可以直接按 `symbol` 和品种表对齐，不会碰到目录里没提过的名字。个别行读不出来（缺字段、价格不是数）就只丢那一行，一个坏合约不会把整块板块页清空；数组按 `symbol` 升序，同一份上游答复的缓存字节是稳定的。`source=binance` 时直接透传币安自己的 `/fapi/v1/ticker/24hr`（不带 symbol 就是全场），形状本来就是这个。

### `/market/v1/*` 的失败线契约

同一个 429 可能是两件完全相反的事，所以**看 body 的 `error` 字段**，不要只看状态码：

| 情况 | 状态 | 头 | body |
| --- | --- | --- | --- |
| 上游限流/封禁（币安 429/418/403、OKX `50011`/`50013`/`50026`） | `429` | `Retry-After: <整数秒>`、`X-Kanpan-Upstream: <source>-limited` | `{"error":"upstream_rate_limited","source":"okx","code":429,"retryAfter":120,"upstreamStatus":"429"}` |
| 上游地域拒绝（451） | `451` | `X-Kanpan-Upstream: <source>-blocked` | `{"error":"upstream_blocked","source":"okx","code":451}` |
| 本机网关准入满 | `429` | `Retry-After: 2` | `{"error":"busy"}` |
| 本机市场队列满 | `503` | `Retry-After: 2` | `{"error":"busy"}` |
| 其他失败 | `503` | `Retry-After: 2` | `{"error":"market unavailable"}` |

`retryAfter` 是整数秒，优先用上游给的 `Retry-After`（秒数或 HTTP-date 都解析），上游没给时 429 用 10 秒、418 用 120 秒（官方公布的 418 时长下限是 2 分钟）、403 用 60 秒；403 是币安 WAF 把这台机器按下了，属于「封禁」而不是「这条路不通」，所以它和 429 走同一份契约（HTTP 429 + `Retry-After`，`upstreamStatus` 是 `"403"`），只有地域拒绝的 451 才回 451；`upstreamStatus` 是上游的 HTTP 状态或 OKX 业务码字符串。同一个来源在冷却期内的请求即使已经排进限速队列，**取到节奏许可后还会再看一次冷却**，不会出站，同样按上面这行回复剩余的秒数。上游限流不退还调用方的本机配额：正确反应是等，客户端照旧狂打就该同时撞上本机限速。

- `/oi/v1/metrics/BTCUSDT/2021-12-01.json`：归档日切片，真实 `[毫秒时间戳,持仓量]`。
- `/oi/v1/metrics/BTCUSDT/range?interval=4h&from=1638316800000&to=1638403199999`：按14种图表周期取桶末值，周/月/年用UTC日历，1m/3m保留源5m粒度。
- `/chart-gateway/health`：历史服务状态。
- `/chart-gateway/stream-health`：实时服务连接/频道/预算状态。健康HTTP本身不证明行情可用。

历史日切片缓存最多200MB、8个全局下载任务、64个待处理键；同日请求合并。范围最多4并发，每请求2个读取任务；每来源2并发和请求速率限制，HTTP工作线程最多16，读超时5秒。缓存按最近使用淘汰，失败/404不永久缓存。手机只收周期聚合结果；主节点失败顺序转备用，不同时在两台重复生成相同历史范围。近期市场 REST 与实时 WS 走同一完整来源，不从 OI 归档补行情。

## 少等一点：四处结构性等待

手机那几百毫秒不是 Python 慢，是在等：等 TTL 过期后重新问一次交易所、等上游 WS 冷启动、等全局锁里那次
JSON 解码、等一段和上一屏 90% 重叠的历史被重新分页下载。四处都按「把等待挪到用户不在等的时候」来改：

- **热窗口后台续鲜**：被访问过的实时窗口由后台线程在 TTL 到期前重取，手机来的时候读的是缓存。新鲜度上界不变
  （仍是 1 秒），只是等待发生在后台。最多 64 个窗口，60 秒没人再问就停。
- **已收盘 K 线落盘**：收盘的 K 线不会再变，按 (来源, 品种, 周期) 存在 `/var/cache/kanpan-gateway/bars`
  （内存 64000 根、32 条序列，磁盘 256MB，30 秒落盘一次）。往回翻页时和上一屏重叠的部分直接从本地切片，
  只向交易所要下面缺的那一段；拼接处用与整窗相同的连续性规则校验，对不上就报错而不是给出一段拼错的历史。
- **上游 WS 保温**：常驻频道（`RESIDENT_STREAMS`，默认 `btcusdt@kline_1m`）让上游 socket 一直活着；
  最后一个客户端离开后频道还保持订阅 `CHANNEL_LINGER` 秒（默认 90，最多 48 个频道），
  所以来回切品种、换周期不必再付一次交易所的订阅启动时间。
- **拆掉全局锁里的 10 ms**：OKX 品种表解析一次后常驻，响应字节的 JSON 解码移出全局锁。

后台续鲜不许把手机的位置抢走：限速闸上只要有请求在排队，后台就让出时隙，而且只在闸门空出一整个间隔时才动手。
同一个窗口的请求仍然合并，但手机不会继承后台那一次的失败——后台放弃时，手机自己再要一次。

备用节点上的冷启动 A/B（每轮都清空落盘 K 线库并重启服务，基线与改后交替各两轮，中位数）：

| 项目 | 基线 | 改后 |
| --- | --- | --- |
| 间隔 2.5 秒重取实时窗口 | 146～154 ms | 2.8～3.4 ms |
| 回补与上一屏重叠 90% 的窗口 | 2202～2209 ms | 146～157 ms |
| 回到 3 秒前看过的 WS 频道 | 731～1613 ms | 187～2341 ms（噪声大，见下） |
| 首屏未命中 / 1500 根回补 / ticker | 140 / 2171 / 147 ms | 135 / 2169 / 126 ms |

代价是网关 CPU 从每轮约 600 ms 涨到约 2200 ms——后台续鲜在替用户守着窗口，这是它的账单。按当前 3 位用户、
上限 10 人的规模（CPUQuota=300%）可以接受。WS 首帧那一项测不出稳定结论：`@kline_1m` 只在有成交时才推，
中小品种两帧之间常隔几秒，这个噪声比订阅启动时间大得多；同一批品种成对比较（先冷后回访）时，
保温把回访中位数从 1068 ms 压到 502 ms，方向一致但不宜当作精确数字。

## 运行、验证与回滚

Python3.11+，独立venv，`pip install -r requirements.txt`；aiohttp固定3.14.3。本地运行 `python -m unittest discover -s Backend/kanpan-gateway`，**必须用装了 aiohttp 的那个解释器（venv 里的 python）**：实时那一半（`test_okx_hub` / `test_stream_hub`）在导入时就需要 aiohttp，系统 `python3` 上它们会以带修复办法的 skip 信息整模块跳过（输出里是 `OK (skipped=2)`，不是「WS 那半边跑过了」，想看原因加 `-v`）。98项测试含100个本地客户端复用一条假上游、来源限额、异常控制帧隔离、慢客户端释放、OI周期与缓存，以及历史分页并行不丢连续性、响应字节缓存而serverTime保持新鲜、上游451作为独立信号不扣调用方配额，还有落盘 K 线只在能给出与网络逐行一致的窗口时才回答、后台续鲜让出限速时隙、频道保温到期后真的退订。另有上游限流那一组：上游 429 带 `Retry-After` 与无头 418 各自的截止时间原样到达客户端、OKX HTTP 200 的限流业务码不当空行情、已排进限速队列的第二条请求在冷却期内不再出站、本机 busy 的 429 与上游限流的 429 可区分，以及 OKX ticker / K 线的量纲与 `underlyingType` 只在有依据时才写、上游 403 当封禁走 429 契约而不是压成 503、OKX `state` 映射后透传（`preopen`/`suspend` 各一条断言，`test` 合约被过滤）。全市场 ticker 那一组另钉住：数组元素与单品种映射逐字段相等、品种表里没有的合约被过滤掉、5 秒内第二次请求不出站、`quoteVolume` 恒为空串（不是 `"0"`）。100客户端测试只证明共享/隔离功能，不是生产容量承诺。

源码部署在`/opt/kanpan-gateway`，`kanpan-gateway.service`监听127.0.0.1:8792，`kanpan-stream-hub.service`监听127.0.0.1:8793；DynamicUser、NoNewPrivileges、ProtectSystem=strict、ProtectHome、PrivateTmp。历史缓存位于`/var/cache/kanpan-gateway`，可清理重建。

仅在项目独立Caddy站点导入`Caddy.routes`（REST/OI与账号两段开启`encode zstd gzip`，WebSocket段不压缩），其它主机规则保留。两台现有Caddy均admin off，配置备份并validate成功后各短重启一次激活；未升级Caddy或更改管理接口。后续Python更新只重启项目服务。恢复`/etc/caddy/Caddyfile.backup-before-shared-<部署时间>`并validate/激活可回滚路由；主节点旧源码另备份在`/var/backups/kanpan-gateway`。未修改Mac网络代理规则。

两台VPS的实时共享与 OI 验证记录见`docs/acceptance/AICoin-base/foundation/dual-gateway-live.json`；市场源的 OKX 历史、实时和分页应通过 `LiveRoutingTests` 在当前公网环境单独复验，不能用本地单元测试代替 VPS 或真机覆盖。

Git只包含公开服务地址、实现及验证记录，不包含SSH配置、登录端口、私钥、密码或令牌。VPS是受信行情中转；WSS/HTTPS正常校验证书，不等于交易所对报价做端到端签名。
