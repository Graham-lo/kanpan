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
}
