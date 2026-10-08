# kanpan-gateway-picks-its-own-domain

**项目约定**：看盘的 VPS 网关在美国：上游行情域名必须在 VPS 上单独实测选（不能照抄手机端为国内直连挑的那个），而且网关只代理币安 WS，币安 REST 回 451 是既定现状不是故障

2026-09-18 我在 app 侧把合约推送域名定成 `dstream.binance.me`（理由是国内 DNS 解析干净、
可直连、比走代理快），随后发现后端 `Backend/kanpan-gateway/stream_hub.py` 的上游还指着
已经不发 K 线的 `fstream.binance.com`。我把这件事同步给另一个窗口时，用户补了一句：
「vps 是美国的，要使用快的域名，具体测试让它那边去做，千万不要使用测试网」。

所以看盘有**两个各自独立的域名选择**，不能互相照抄：

- **手机端（`APIHost.defaultStream`）** 的前提是用户在国内。选域名的标准是国内解析干净、
  能直连、直连比走代理快。`.me` 这一族镜像就是为这个前提选的。
- **VPS 网关** 跑在美国，「国内可直连」这个前提完全不成立，`.me` 镜像对美国出口不一定快，
  多半是 `dstream.binance.com` 更合适。哪个快必须**在 VPS 上实测**，由负责网关那一侧的
  窗口自己跑，不要拿我在 Mac 或手机上测出来的数字去定网关的值。

两边唯一共享的是硬约束：**绝对不能用 `*.binancefuture.com`（合约测试网）**，
以及选定之前必须先证明是生产盘、四族流（kline/ticker/aggTrade/markPrice）真的都在发，
具体验法见 `kanpan-verify-stream-host-is-production-and-direct`。

## 网关只代理 WS，币安 REST 在 VPS 上 451 是既定事实

币安按地域拦美国出口：两台网关（107-174-172-10 与 96-44-162-222）请求
`fapi.binance.com` 一律返回 HTTP 451，网关包装成
`{"error":"upstream_blocked","source":"binance","code":451}`，
`/market/v1/klines|ticker|instruments?source=binance` 三个端点全是 451，
而同一台机器上 `source=okx` 返回 200、WS 流也通。

我两次把这个当成"待修的故障"报给用户（一次列了三条修法请他拍板，一次写进只读复验报告），
两次都被回绝：**「vps 只有 bian ws 是通的，rest 是不通的这个没问题」**、
**「bian rest 本身就是地域限制不用管啊」**。

所以这是网关这条线路的**既定定位，不是 bug**：网关只负责代理币安的 WS 行情，
币安的 REST（K 线、exchangeInfo、24h ticker）不走网关；网关里那套 `cooldown` /
`upstream_blocked` 逻辑就是为它准备的兜底。以后再看到这三个端点 451，不要再开排查、
不要换域名重试、不要提"换 REST 入口／让网关走代理出去"这类方案，也不要因此怀疑
自己刚改的东西。需要 REST 行情时，网关那条线走的是 OKX 源；币安行情靠手机端直连和
流推送拿。只有用户自己提出要让网关也取到币安 REST 时，才谈代理、换机房这些办法。
网关上真正需要维护的是 WS 上游那一段（`stream_hub.py`）。

这条也意味着在 VPS 上**没法**用「跟 `fapi.binance.com` 的 24hrTicker 同刻比量级」
来证明某个推送域名不是测试网——那一步会被 451 挡掉。在受限机器上改用
「成交 id 的绝对量级」当指纹：生产盘 BTCUSDT 的 aggTrade id 是 80 亿级、24h 成交笔数
400 万级，测试网是 5 亿级 / 30 万级，差一个数量级，不需要同刻基准；
或者从不受限的机器（比如走新加坡节点的 Mac）取一份基准值带过去比。

推而广之：这个项目里凡是「选一个最快的域名/节点」的结论，都要连着它的网络位置一起记，
换个出口就得重测。同一个结论在手机、Mac、美国 VPS 上可以是三个不同的答案。
