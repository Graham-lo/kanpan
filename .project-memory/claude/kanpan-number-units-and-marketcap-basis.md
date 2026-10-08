# kanpan-number-units-and-marketcap-basis

**项目约定**：看盘的数额一律用 K / M / B / T 金融单位（不用万/亿），市值一律用总市值（总供应量 × 现价）而不是流通市值

2026-09-18 用户为看盘（Kanpan）定了两条数值展示约定，都跟之前代码里的做法相反。

**数额单位用 K / M / B / T，不用万 / 亿。** 用户原话是「数额单位用金融单位，比如 b k t」。
在此之前 `KanpanCore/Sources/KanpanCore/Format/Format.swift` 里的 `VolUnit` 只有
`plain / wan / yi` 三档，`fmtVol` 输出「1.23 亿」「45.6 万」。以后成交额、持仓量、市值这类
大额数字都要走千进制的英文金融单位。注意「按品种钉住单位」那条既有规矩仍然成立——
换行情线路时同一品种的口径可能差一截，数字跨过进位坎会让单位跳变，看上去像换了品种，
所以单位要由外面记住（`MarketModel.volumeUnit`），不是每帧按当前数值现算。

**市值用总市值，不是流通市值。** 用户原话是「市值直接用总市值就行」。
这跟加密行业惯例相反：CoinMarketCap、CoinGecko、币安、AICoin 写「市值」时指的都是
流通量 × 价格，总量 × 价格那个他们叫 FDV / 完全稀释估值；AICoin 逆向里那个折叠块的标签
字符串就叫 `ui_ticker_price_extra_label_circulation_market_value`（流通市值）。
两个口径对老币几乎没差（BTC、ETH、BNB 都是 1.00 倍），对新币能差一倍以上
（SUI 2.44 倍、JUP 2.07 倍、OP 1.75 倍）。我把这个差异和惯例摆出来之后用户仍然选了总市值，
所以这是他知情后的决定，不要再拿「跟 CMC 对不上」去回退它。数据上两个口径来自同一个响应，
`totalSupply` 和 `circulatingSupply` 都在，取哪个都是一行的事。
