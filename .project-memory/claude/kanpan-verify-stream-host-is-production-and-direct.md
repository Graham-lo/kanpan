# kanpan-verify-stream-host-is-production-and-direct

**项目约定**：看盘选行情推送域名时绝对不能用 *.binancefuture.com（合约测试网）；换域名前必须先证明它推的是生产盘、四族流都真的发，再比直连与代理哪条快

2026-09-18 我把看盘合约行情的默认推送域名设成了 `stream.binancefuture.com`，理由是
币安官方文档把它和 `fstream.binance.com` 并列成两个基址，而且国内直连拨得通。用户看了
一眼就点破：「你看看代码里合约 ws 是不是用的国内可以直连最快的域名，不要搞成测试网了」，
随后又要求「ws 能实时拿到数据的不是测试网数据，国内快还是走了代理更快」都要实测。

他是对的。`*.binancefuture.com` 那一族推的是**合约测试网**的数据：同一时刻它的
24hrTicker 与 `testnet.binancefuture.com` 的 REST 逐字段相同（成交额 1214 亿、成交笔数
31.6 万、firstId/lastId 一致），而生产盘 `fapi.binance.com` 是 139 亿、431 万笔。价格
只差几十美元，所以光看价格永远看不出来；测试网上大多数山寨没有成交，界面就表现为
「K 线和自选都不跳」。另一个窗口（kanpan-d2）排查同一个现象时也踩进来过，并转达了
用户的原话：**「vps 是美国的，要使用快的域名，具体测试让它那边去做，千万不要使用测试网」**。

所以先记死一条硬约束：`stream.binancefuture.com` / `dstream.binancefuture.com` /
`fstream.binancefuture.com` **整族都是合约测试网，一个都不能用**。它们难防的地方在于
挂在币安官方文档上、国内也直连得通、数据结构完全正常，所以「找一个能直连的镜像」时
极容易被选中。拿候选域名和 `testnet.binancefuture.com` 的 REST 对一下，逐字段相同
就说明选错了。

所以在这个项目里换任何行情域名，动手前要按顺序验三件事：

1. **是不是生产盘**。不要比价格，要比 24h 成交额、成交笔数这些量级字段，并且和
   `fapi.binance.com` 的 REST 同刻对照。官方文档把某个域名列出来不等于它是生产盘。
   比成交 id 的时候注意别自己吓自己：**聚合成交 id（aggTrade 的 `a`）和逐笔成交 id
   （24hrTicker 的 `firstId`/`lastId`）是两个不同的序列**，同一时刻 BTCUSDT 分别是
   34 亿量级和 80 亿量级，对不上是正常的，不是测试网的证据。最干净的对照是
   `count` 与 `quoteVolume`：实测同刻 `fapi` 3393098 笔 / 108.91 亿，
   `dstream.binance.me` 的 `btcusdt@ticker` 3393408 笔 / 108.92 亿，这才叫同一个盘。
2. **四族流是不是都真的发**。只连上、只收到 `bookTicker` 不算数——从国内这条出口看，
   `fstream.binance.com` 与 `fstream.binance.me` 就是订阅 `kline`/`ticker`/`aggTrade`/
   `markPrice` 回 `result:null` 然后一帧不发。每一族都要单独订一遍、看着帧流出来才算通过。
   **这个结论只对做实验的那条出口成立**：同一天美国机房的网关上 `fstream.binance.com` 的
   `kline_1m` 是正常出帧的。我当时把它写成了「币安 CM 合并后把合约流整体搬到 dstream 了」，
   被另一个窗口的实测推翻——一个出口上的流可用性不能推广成交易所的全局变更。
3. **直连和走代理哪条快**。用同一组流并发开两条连接（一条被 Surge 临时规则强制 DIRECT、
   一条走节点）跑同一个时间窗，比握手时延、首帧时延、以及「本地收到时刻 − 帧里的 E
   字段」这个推送延迟，同时核对两条收到的帧数是否一致（防止把丢帧当成快）。
   顺序跑出来的帧数差是行情活跃度波动，不能当结论。

这一轮的结论：合约行情流在币安 CM 合并后搬到了 `dstream` 这一族，`dstream.binance.me`
国内解析干净、可直连、四族流齐全，实测直连比走新加坡节点握手快一倍、推送延迟低约 30ms，
于是它成了 `APIHost.defaultStream`。
换完之后真机复验通过：日志里 `WS有效首帧 dstream.binance.me 657ms`，图表事件从 15~24
涨到 34~36 每 5 秒、列表收行情从 33~38 涨到 50~56 每 5 秒、丢 0，用户确认界面已经正常跳动。
