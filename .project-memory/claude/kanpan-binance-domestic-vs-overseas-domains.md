# kanpan-binance-domestic-vs-overseas-domains

**项目约定**：币安的域名分「国内可直连」与「国内被墙」两族，看盘排查行情线路时先按单个主机名分，不要按交易所或按顶级域下结论

2026-09-18 排查看盘真机直连模式时，用户点出了一条前提：
「因为分 bian 国内国外域名，国外的才需要被代理」。我当天在 Mac 上用一条
`PROCESS-NAME,<探针>,DIRECT` 的 Surge 临时规则强制直连，把全部候选主机跑了一遍，
结论确实是分族的，但**分界线是单个主机名，不是顶级域**：`fstream.binance.me` 直连能
握手能推数据，同一个顶级域下的 `fapi.binance.me` 却在 TLS 握手就被 reset。

国内直连能用（DNS 干净 + TLS 通）：
- 合约推送 `dstream.binance.me` —— 生产盘，`kline`/`ticker`/`aggTrade`/`markPrice`
  四族全都在发，现在是 app 的默认推送域名。
- `stream.binancefuture.com`、`dstream.binancefuture.com`、`fstream.binancefuture.com`
  也直连得通，但当天晚些时候实测发现**它们推的是合约测试网的数据**（我最初在这份
  笔记里写「都是生产数据」是错的，见
  `kanpan-verify-stream-host-is-production-and-direct`）。
- `fstream.binance.me` 直连通，但**在国内这条出口上**只剩 `bookTicker`/`depth` 还在发
  （20 秒窗口 bookTicker 六千多帧、kline 零帧，四种路径都试过）。注意这是按出口而异的：
  同一天美国机房实测 `fstream.binance.com` 的 `kline_1m` 正常出帧，所以不能写成
  「币安停发了 fstream 的行情流」，只能说「国内这两条出口上 fstream 不可用」。
- 现货推送 `data-stream.binance.vision`；现货 REST `data-api.binance.vision`、
  `api.binance.me`（`/api/v3/*` 返回 200 真数据）。
- 历史归档 `data.binance.vision`；测试网 `testnet.binancefuture.com`。

国内直连不通（DNS 被投毒成 Facebook/Twitter 的地址，且就算用 DoH 拿到真 IP
再 `--resolve` 过去，TLS 也会在 SNI 处被 reset）：
`fapi.binance.com` 及 `fapi1~3`、`dapi.binance.com`、`api.binance.com`、
`api-gcp/api1`、`www.binance.com`、`fstream.binance.com`、`dstream/stream.binance.com`、
`fapi/dapi/api1/ws-*.binance.me`、`*.binance.info`、`futures.binance.*`、
`ws-fapi.binance.com`、`ws-api.binance.com`。`binancezh.com/.top/.pro` 已整体 NXDOMAIN。

对看盘最关键的一条：**合约 REST 在国内没有任何可直连的入口**。
`binancefuture.com` 域下只有推送，没有 REST（fapi/api/www 全无 A 记录）；
`api.binance.me` 只开现货，请求 `/fapi/v1/*` 直接 403；`ws-fapi.*`（WebSocket API）
也全被墙。所以国内没有代理的手机，直连模式能收到实时行情，却拿不回历史 K 线、
开盘价基线和 exchangeInfo——只有现货数据有直连替代，合约没有。

排查这类问题时的正确顺序：先按主机名逐个验 DNS 和 TLS，不要把「某个 binance
主机在国内不通」推广成「币安被墙」或「这个顶级域不能用」。
