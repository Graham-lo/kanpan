import Foundation

/// 端点配置（§4.1）。域名可改：设置页留了「自定义 API 域名」，国内网络换镜像域时用。
public struct BinanceHosts: Sendable, Equatable {
  /// USDT 本位合约 REST，默认 `fapi.binance.com`。
  public var fapi: String
  /// 组合流 WS，默认 `dstream.binance.me`（生产盘，国内可直连）。
  ///
  /// 不是 `fstream.binance.com`：2026-09-18 实测那台只剩 `bookTicker`/`depth` 还在发，
  /// `aggTrade`/`markPrice`/`ticker`/`kline` 整族一帧不发。也不是官方文档并列的
  /// `stream.binancefuture.com`——那台推的是**合约测试网**的数据。选型的完整实测记录
  /// 见 `APIHost.defaultStream`。
  public var stream: String
  /// 公开归档站，OI 的 metrics zip 在这儿。
  public var vision: String
  public var streamFallbacks: [String]
  public var oiProxy: String?
  public var oiProxyFallbacks: [String]
  public var oiProxies: [String] {
    var seen = Set<String>()
    return ([oiProxy].compactMap { $0 } + oiProxyFallbacks).filter { seen.insert($0).inserted }
  }

  public init(fapi: String = "fapi.binance.com",
              stream: String = "dstream.binance.me",
              vision: String = "data.binance.vision",
              streamFallbacks: [String] = [], oiProxy: String? = nil, oiProxyFallbacks: [String] = []) {
    self.fapi = fapi
    self.stream = stream
    self.vision = vision
    self.streamFallbacks = streamFallbacks; self.oiProxy = oiProxy
    self.oiProxyFallbacks = oiProxyFallbacks
  }

  public static let `default` = BinanceHosts()

  // ------------------------------------------------------------------ REST

  func url(_ path: String, _ query: [String: String] = [:]) -> URL {
    var c = URLComponents()
    c.scheme = "https"
    c.host = fapi
    c.path = path
    if !query.isEmpty {
      // 固定字典序，日志和测试里请求串才是稳定的。
      c.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
    }
    return c.url!
  }

  public func exchangeInfo() -> URL { url("/fapi/v1/exchangeInfo") }

  /// 历史 K 线。向前翻页时传 `endTime = 已有第一根 openTime - 1`。
  public func klines(symbol: String, interval: String, limit: Int,
                     startTime: Int64? = nil, endTime: Int64? = nil) -> URL {
    var q = ["symbol": symbol, "interval": interval, "limit": String(limit)]
    if let startTime { q["startTime"] = String(startTime) }
    if let endTime { q["endTime"] = String(endTime) }
    return url("/fapi/v1/klines", q)
  }

  /// 单品种的资金费率快照（`lastFundingRate` / `nextFundingTime`）。
  ///
  /// 公开、免鉴权、权重 1。图上那一份费率是 `markPrice@1s` 流捎回来的，只有
  /// 正在看的那张图有；长按预览卡要的是「任意一个品种现在的费率」，那就走这儿。
  public func premiumIndex(symbol: String) -> URL {
    url("/fapi/v1/premiumIndex", ["symbol": symbol])
  }

  public func ticker24h(symbol: String) -> URL {
    url("/fapi/v1/ticker/24hr", ["symbol": symbol])
  }

  /// 全市场 24h 统计。一次往返换回所有品种，权重 40；从后台回来时
  /// 整屏都要补价，比按行发几十个单品种请求少等一整轮。
  public func tickers24h() -> URL { url("/fapi/v1/ticker/24hr") }

  /// 持仓量近 30 天。`period` 只能是 5m/15m/30m/1h/2h/4h/6h/12h/1d。
  public func openInterestHist(symbol: String, period: String, limit: Int,
                               startTime: Int64? = nil, endTime: Int64? = nil) -> URL {
    var q = ["symbol": symbol, "period": period, "limit": String(limit)]
    if let startTime { q["startTime"] = String(startTime) }
    if let endTime { q["endTime"] = String(endTime) }
    return url("/futures/data/openInterestHist", q)
  }

  /// 全市场多空账户数比近 30 天。`period` 和持仓量同一套：5m/15m/30m/1h/2h/4h/6h/12h/1d。
  ///
  /// 口径已经拍板成「全市场账户数」这一种，不做大户持仓 / 大户账户的切换
  /// （`kanpan-sector-page-no-basis-picker`），所以这儿只有这一条路径。
  public func globalLongShortAccountRatio(symbol: String, period: String, limit: Int,
                                          startTime: Int64? = nil, endTime: Int64? = nil) -> URL {
    var q = ["symbol": symbol, "period": period, "limit": String(limit)]
    if let startTime { q["startTime"] = String(startTime) }
    if let endTime { q["endTime"] = String(endTime) }
    return url("/futures/data/globalLongShortAccountRatio", q)
  }

  /// 主动买卖量比近 30 天。
  ///
  /// 路径里的 `takerlongshortRatio` 就是**全小写的 taker/long/short**，只有最后的
  /// `Ratio` 大写——币安这一族里唯一一个不按驼峰写的端点，写成 `takerLongShortRatio`
  /// 会 404。别「顺手改正」它。
  public func takerLongShortRatio(symbol: String, period: String, limit: Int,
                                  startTime: Int64? = nil, endTime: Int64? = nil) -> URL {
    var q = ["symbol": symbol, "period": period, "limit": String(limit)]
    if let startTime { q["startTime"] = String(startTime) }
    if let endTime { q["endTime"] = String(endTime) }
    return url("/futures/data/takerlongshortRatio", q)
  }

  /// 基差近 30 天。
  ///
  /// 参数是 `pair` + `contractType`，**不是 `symbol`**：基差是「某个标的的某类合约
  /// 相对指数的偏离」，同一个 pair 下永续和各期交割合约各有一条曲线。我们只看永续，
  /// 所以 `contractType` 默认 `PERPETUAL`。传 `symbol=BTCUSDT` 会被判成缺参。
  public func basis(pair: String, contractType: String = "PERPETUAL", period: String, limit: Int,
                    startTime: Int64? = nil, endTime: Int64? = nil) -> URL {
    var q = ["pair": pair, "contractType": contractType, "period": period, "limit": String(limit)]
    if let startTime { q["startTime"] = String(startTime) }
    if let endTime { q["endTime"] = String(endTime) }
    return url("/futures/data/basis", q)
  }

  // ------------------------------------------------------------------ 归档

  /// 每日 metrics zip：一天一个，≈ 12 KB，解开是 288 行 5 分钟粒度的 CSV。
  /// metrics **只有 daily 一档**，请求 monthly 是 404。
  public func metricsZip(symbol: String, day: String) -> URL {
    URL(string: "https://\(vision)/data/futures/um/daily/metrics/\(symbol)/\(symbol)-metrics-\(day).zip")!
  }

  // ------------------------------------------------------------------ WS

  /// 组合流。一条连接，后续靠 SUBSCRIBE / UNSUBSCRIBE 换流，不重连（§4.4）。
  ///
  /// 路径是币安自己的 `/stream`（§4.1）。网关那条路上的 `/market/stream` 是 VPS
  /// 自己的路由（`Backend/kanpan-gateway/stream_hub.py`），由 `SourceSocketFactory`
  /// 在换主机的时候一并改掉——不能拿它当这里的默认值，否则直连会拨到币安根本
  /// 没有的路径上，握手当场被拒，WS 永远连不上。
  public func combinedStream(_ streams: [String]) -> URL {
    var c = URLComponents()
    c.scheme = "wss"
    c.host = stream
    c.path = "/stream"
    if !streams.isEmpty { c.queryItems = [URLQueryItem(name: "streams", value: streams.joined(separator: "/"))] }
    return c.url!
  }

  /// 某品种某周期的 K 线流名。1y 没有原生流，订 1M（§4.2）。
  public static func klineStream(symbol: String, interval: String) -> String {
    "\(symbol.lowercased())@kline_\(interval)"
  }
  public static func tickerStream(symbol: String) -> String { "\(symbol.lowercased())@ticker" }
  public static func markPriceStream(symbol: String) -> String { "\(symbol.lowercased())@markPrice@1s" }

  /// Legacy trade decoder support for recordings. Production subscribes to the documented
  /// /market kline/ticker/markPrice streams; /public bookTicker is a separate endpoint.
  public static func tradeStream(symbol: String) -> String { "\(symbol.lowercased())@trade" }

  /// 最优买卖挂单。成交稀疏的品种（半夜的小币）可能几十秒没有一笔成交，
  /// 靠它给最新价一个心跳——只改价，不记量，也不凭它开新的一根。
  public static func bookTickerStream(symbol: String) -> String { "\(symbol.lowercased())@bookTicker" }

  /// 保留未消费的流名；强平功能不做，见 docs/不做清单.md，不添加订阅或展示。
  public static func forceOrderStream(symbol: String) -> String { "\(symbol.lowercased())@forceOrder" }

  /// 逐笔聚合成交。它的用处不是做一张逐笔明细表，而是给主动买卖比补上
  /// 「当前这根还没成型的桶」——`/futures/data/takerlongshortRatio` 是 5 分钟粒度
  /// 且滞后一档，只有这条流是实时的。
  public static func aggTradeStream(symbol: String) -> String { "\(symbol.lowercased())@aggTrade" }

  /// 买卖各五档的**全量快照**（partial book depth），100ms 一帧。
  ///
  /// 不是增量流：每一帧就是完整的五档，不用维护本地订单簿、也不用先拉一份 REST 快照
  /// 对 `U`/`u` 序号。事件名照样是 `depthUpdate`，别被它骗去写增量合并的逻辑。
  public static func depth5Stream(symbol: String) -> String { "\(symbol.lowercased())@depth5@100ms" }
}
