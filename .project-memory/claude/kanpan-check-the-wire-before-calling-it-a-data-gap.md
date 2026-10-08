# kanpan-check-the-wire-before-calling-it-a-data-gap

**项目约定**：看盘里说某功能「缺数据/缺接口」之前，必须先核对已订阅的流、已实现的接口、交易所公开接口，以及交易所官网自用的非文档接口，不能凭印象判死

2026-09-17 到 09-18，同一个毛病用户连着纠正了我两次。

第一次：我做完 AICoin 前端全量盘点，把「当前持仓量」和「资金费率」都标成了 B 类
（资源完整但看盘缺数据，要后期补接口）。用户反问：「持仓量和资金费率应该有接口吧，
当前累计持仓量不是已经有历史数据了吗可以计算的啊」。他是对的，而且比他说的还便宜：
资金费率一直在已经订阅的 `btcusdt@markPrice@1s` 流里流进来，`markPriceUpdate` 帧带着
`r`（费率）、`T`（下次结算）、`i`（指数价）、`P`（预估结算价），只是
`KanpanNetwork/Sources/KanpanNetwork/Binance/DTO.swift` 的解码只取了 `p` 和 `E`；
当前持仓量则是已实现的 `openInterestHist` 最后一行。我把「客户端还没写这段解析」
误当成了「没有数据来源」。

第二次：我又把「市值」判成无来源，理由是 Binance fapi 和 OKX v5 的公开文档里没有流通量。
用户说：「市值没来源可以计算的，总量是多少，按理来说交易所会提供吧，而且他们的 app 上
也有这样的数据」。他还是对的。交易所官网自己在用的非文档接口是公开、免密钥的，
`https://www.binance.com/bapi/apex/v1/public/apex/marketing/symbol/list` 一次请求就回
`circulatingSupply` / `totalSupply` / `maxSupply` / `marketCap` / `rank` / `marketCapDominance`，
`.../bapi/asset/v2/public/asset-service/product/get-products` 回 1372 个币的流通量，
`.../bapi/asset/v1/public/asset-service/product/currency` 回 54 组法币汇率（含 CNY）。
我只查了「交易所的交易 API 文档」，没查「交易所自己的 app 和网页是怎么拿到这个数的」。

所以在看盘里给任何功能下「缺数据 / 做不了 / 要补接口」的结论之前，要走四步：
一看已订阅的 WS 流里还有哪些字段被解码丢掉了；二看 `KanpanNetwork` 里已实现的接口
能不能直接推出这个值；三看交易所公开文档（Binance fapi / OKX v5）；
四看参照 app（AICoin、币安 app、交易所网页）上既然显示了这个数，它是从哪个接口拿的——
抓一下官网自用的 bapi / priapi 这类非文档接口，它们通常免密钥且一次回全市场。
判死之前先实际 curl 一下验证，不要凭印象。用户对交易所接口覆盖面比我熟，
把「能做」判成「不能做」会被当场否掉，而且会让盘点低估可做范围，
这比高估更有害——本该排进日程的功能会被划掉。

2026-09-18 第三次，换了个失败模式：**命名口径对不上，被我当成了「没有这类标的」。**
我在验证板块气泡图的数据源时拉了币安现货 `exchangeInfo`，拿 1368 个交易对的 `baseAsset`
去和合约里那 182 个股票代号做精确匹配，零命中，于是下结论「币安现货没有任何股票标的」。
用户直接否掉：「bian 接了美股正股的，而且链上也有，你先核实一下」。他是对的——
币安的代币化美股 bStocks 在现货里用的是**加 B 后缀**的 base（`AAPLB`/`NVDAB`/`TSLAB`），
`AAPLB ≠ AAPL`，我的精确匹配自然一个都对不上。同一轮还有第二个口径陷阱：股票永续的
`contractType` 是 `TRADIFI_PERPETUAL` 而不是 `PERPETUAL`，凡是按 `PERPETUAL` 过滤的脚本
都会把 183 个股票合约全部悄悄滤掉；以及币安会给撞了币圈代币名的股票改代号
（Seagate `STX`→`STXX`、Quantinuum `QNT`→`QNTX`），要靠 `/fapi/v1/constituents` 反查
指数成分里的真实交易所代码才能还原。

所以上面那四步之外再加一条：**匹配不上的时候，先怀疑自己的命名口径，再怀疑数据不存在。**
交易所为了避免代号冲突会加前后缀、改代号、用自己的 contractType 枚举，
精确字符串比对返回空集只能说明「我这条规则没匹配上」，不能说明「交易所没有这东西」。
空集是要去人工翻一眼原始清单的信号，不是可以直接拿去下结论的证据。
