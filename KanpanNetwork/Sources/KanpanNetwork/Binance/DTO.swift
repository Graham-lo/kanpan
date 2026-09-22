import Foundation
import KanpanCore

// ---------------------------------------------------------------- K 线

/// `fapi/v1/klines` 的一行：数组，元素类型混着来。
/// `[openTime, o, h, l, c, v, closeTime, quoteVolume, trades, takerBase, takerQuote, ignore]`
struct KlineRow: Decodable {
  var openTime: Int64
  var open: Double
  var high: Double
  var low: Double
  var close: Double
  var volume: Double
  var closeTime: Int64

  init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    openTime = try c.decode(Int64.self)
    open = try KlineRow.num(&c)
    high = try KlineRow.num(&c)
    low = try KlineRow.num(&c)
    close = try KlineRow.num(&c)
    volume = try KlineRow.num(&c)
    closeTime = try c.decode(Int64.self)
    guard bar.isValidMarketBar else { throw FeedError.badResponse("无效的 OHLCV") }
    // 后面几列（成交额、笔数、主动买量）1.0 用不上，不解。
  }

  /// 币安价格量都是字符串，但归档和某些镜像会给数字，两种都收。
  private static func num(_ c: inout UnkeyedDecodingContainer) throws -> Double {
    if let s = try? c.decode(String.self) {
      guard let d = Double(s) else {
        throw FeedError.badResponse("不是数字：\(s)")
      }
      return d
    }
    return try c.decode(Double.self)
  }

  var bar: Bar { Bar(openTime: openTime, open: open, high: high, low: low, close: close, volume: volume) }
}

// ---------------------------------------------------------------- 品种表

struct ExchangeInfoDTO: Decodable {
  struct Symbol: Decodable {
    var symbol: String
    var baseAsset: String
    var quoteAsset: String
    var contractType: String?
    var underlyingType: String?
    var underlyingSubType: [String]?
    /// `TRADING` / `PENDING_TRADING` / `SETTLING` / `CLOSE`…
    /// 不再当过滤条件用，而是原样映射成 `SymbolInfo.status`（审查 B-06）。
    var status: String?
    var pricePrecision: Int
    var quantityPrecision: Int
    var filters: [[String: JSONValue]]

    var tickSize: Double {
      for f in filters where f["filterType"]?.stringValue == "PRICE_FILTER" {
        if let t = f["tickSize"]?.doubleValue { return t }
      }
      return pow(10, -Double(pricePrecision))
    }
  }
  var symbols: [Symbol]
}

/// 只为了从 `filters` 这种异构数组里挑两个字段，不值得写 9 个 struct。
enum JSONValue: Decodable {
  case string(String), number(Double), bool(Bool), null, other

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null }
    else if let s = try? c.decode(String.self) { self = .string(s) }
    else if let d = try? c.decode(Double.self) { self = .number(d) }
    else if let b = try? c.decode(Bool.self) { self = .bool(b) }
    else { self = .other }
  }

  var stringValue: String? { if case .string(let s) = self { return s }; return nil }
  var doubleValue: Double? {
    switch self {
    case .string(let s): return Double(s)
    case .number(let d): return d
    default: return nil
    }
  }
}

// ---------------------------------------------------------------- 24h 行情

struct Ticker24hDTO: Decodable {
  var symbol: String
  var lastPrice: String
  var priceChange: String?
  var priceChangePercent: String
  var openPrice: String?
  var highPrice: String
  var lowPrice: String
  var quoteVolume: String
  var closeTime: Int64?
  var lastId: Int64?

  var ticker: Ticker {
    Ticker(symbol: symbol,
           last: Double(lastPrice) ?? .nan,
           changePercent: Double(priceChangePercent) ?? .nan,
           high: Double(highPrice) ?? .nan,
           low: Double(lowPrice) ?? .nan,
           quoteVolume: Double(quoteVolume) ?? .nan, open24h: openPrice.flatMap(Double.init),
           timeMs: closeTime, lastTradeID: lastId, priceChange: priceChange.flatMap(Double.init))
  }
}

// ---------------------------------------------------------------- 资金费率

/// `/fapi/v1/premiumIndex` 的单品种响应里我们要的那两项。
///
/// `nextFundingTime` 在没有资金费率这回事的品种上是 0，那时候只当「没有下一次」，
/// 费率本身照旧有效。
struct PremiumIndexDTO: Decodable {
  var symbol: String
  var lastFundingRate: String
  var nextFundingTime: Int64?
}

/// 一个品种此刻的资金费率。`nextFundingTimeMs` 只有大于 0 才算数。
public struct FundingSnapshot: Sendable, Equatable {
  public var rate: Double
  public var nextFundingTimeMs: Int64?

  public init(rate: Double, nextFundingTimeMs: Int64?) {
    self.rate = rate
    self.nextFundingTimeMs = nextFundingTimeMs
  }
}

// ---------------------------------------------------------------- 持仓量

struct OIHistDTO: Decodable {
  var symbol: String
  var sumOpenInterest: String
  var sumOpenInterestValue: String
  var timestamp: Int64

  var point: OIPoint { OIPoint(time: timestamp, value: Double(sumOpenInterest) ?? .nan) }
}

// ---------------------------------------------------------------- WS 报文

/// 组合流外层：`{"stream":"btcusdt@kline_1m","data":{…}}`。
/// 也收裸报文（单流地址、回放文件），那时 `stream` 为空。
public struct StreamEnvelope: Decodable {
  public var stream: String?
  public var data: StreamPayload?
  /// 裸报文时外层就是 payload 本身。
  public var inline: StreamPayload?

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: K.self)
    stream = try c.decodeIfPresent(String.self, forKey: .stream)
    data = try c.decodeIfPresent(StreamPayload.self, forKey: .data)
    if data == nil {
      inline = try? StreamPayload(from: decoder)
    }
  }
  enum K: String, CodingKey { case stream, data }

  public var payload: StreamPayload? { data ?? inline }
}

public enum StreamPayload: Sendable {
  case kline(KlineEvent)
  case ticker(Ticker)
  case tickerBatch([Ticker])
  /// 标记价。第三个位置从「事件时间」换成了整帧 `MarkPriceTick`（资金费率、下次结算、
  /// 指数价、预估结算价都在里面），事件时间挪到 `tick.timeMs`。
  case markPrice(symbol: String, price: Double, tick: MarkPriceTick)
  /// 逐笔成交。K 线的实时跳动现在靠它（见 `BinanceHosts.tradeStream`）。
  case trade(TradeEvent)
  /// 最优挂单：只给价格线一个心跳，不进成交量。
  case bookTicker(symbol: String, bid: Double, ask: Double, timeMs: Int64)
  case other(String)
}

extension StreamPayload: Decodable {
  public init(from decoder: Decoder) throws {
    if var rows = try? decoder.unkeyedContainer() {
      var tickers: [Ticker] = []
      while !rows.isAtEnd {
        if case .ticker(let ticker) = try rows.decode(StreamPayload.self) { tickers.append(ticker) }
      }
      self = tickers.isEmpty ? .other("empty ticker batch") : .tickerBatch(tickers)
      return
    }
    let c = try decoder.container(keyedBy: K.self)
    let e = (try? c.decode(String.self, forKey: .e)) ?? ""
    switch e {
    case "kline":
      self = .kline(try KlineEvent(from: decoder))
    case "24hrTicker":
      let sym = try c.decode(String.self, forKey: .s)
      func d(_ k: K) -> Double { (try? c.decode(String.self, forKey: k)).flatMap(Double.init) ?? .nan }
      self = .ticker(Ticker(symbol: sym, last: d(.c), changePercent: d(.P),
                            high: d(.h), low: d(.l), quoteVolume: d(.q), open24h: d(.o), timeMs: try c.decodeIfPresent(Int64.self, forKey: .C),
                            lastTradeID: try c.decodeIfPresent(Int64.self, forKey: .L), priceChange: d(.p)))
    case "markPriceUpdate":
      let sym = try c.decode(String.self, forKey: .s)
      // 数值字段币安一律发字符串，但回放文件 / 镜像偶尔发数字，两种都收。
      func num(_ k: K) -> Double? {
        if let text = try? c.decode(String.self, forKey: k) { return Double(text) }
        return try? c.decode(Double.self, forKey: k)
      }
      let p = num(.p) ?? .nan
      // `r` 空串表示这个品种没有资金费率（例如某些交割合约），当缺失处理。
      let tick = MarkPriceTick(timeMs: (try? c.decode(Int64.self, forKey: .E)) ?? 0,
                               fundingRate: num(.r).flatMap { $0.isFinite ? $0 : nil },
                               nextFundingTimeMs: (try? c.decode(Int64.self, forKey: .T)).flatMap { $0 > 0 ? $0 : nil },
                               indexPrice: num(.i).flatMap { $0.isFinite ? $0 : nil },
                               estimatedSettlePrice: num(.P).flatMap { $0.isFinite ? $0 : nil })
      self = .markPrice(symbol: sym, price: p, tick: tick)
    case "trade":
      self = .trade(try TradeEvent(from: decoder))
    case "bookTicker":
      let sym = try c.decode(String.self, forKey: .s)
      func px(_ k: K) -> Double { (try? c.decode(String.self, forKey: k)).flatMap(Double.init) ?? .nan }
      // 撮合时间 `T` 优先；某些镜像只给事件时间 `E`。
      let t = (try? c.decode(Int64.self, forKey: .T)) ?? (try? c.decode(Int64.self, forKey: .E)) ?? 0
      self = .bookTicker(symbol: sym, bid: px(.b), ask: px(.a), timeMs: t)
    default:
      self = .other(e)
    }
  }
  enum K: String, CodingKey { case e, s, c, o, P, h, l, q, p, k, b, a, r, i, T, E, C, L }
}

/// `kline` 事件。`x == true` 表示这根收了（§4.4）。
public struct KlineEvent: Sendable, Equatable, Decodable {
  public var symbol: String
  public var interval: String
  public var openTime: Int64
  public var closed: Bool
  public var eventTime: Int64
  public var lastTradeID: Int64?
  public var bar: Bar

  public init(symbol: String, interval: String, openTime: Int64, closed: Bool, bar: Bar, eventTime: Int64 = 0, lastTradeID: Int64? = nil) {
    self.symbol = symbol; self.interval = interval
    self.openTime = openTime; self.closed = closed; self.bar = bar; self.eventTime = eventTime; self.lastTradeID = lastTradeID
  }

  public init(from decoder: Decoder) throws {
    let outer = try decoder.container(keyedBy: Outer.self)
    eventTime = (try? outer.decode(Int64.self, forKey: .E)) ?? 0
    let k = try outer.nestedContainer(keyedBy: Inner.self, forKey: .k)
    if let s = try? k.decode(String.self, forKey: .s) { symbol = s }
    else { symbol = try outer.decode(String.self, forKey: .s) }
    lastTradeID = try k.decodeIfPresent(Int64.self, forKey: .L)
    interval = try k.decode(String.self, forKey: .i)
    openTime = try k.decode(Int64.self, forKey: .t)
    closed = (try? k.decode(Bool.self, forKey: .x)) ?? false
    func d(_ key: Inner) throws -> Double {
      if let s = try? k.decode(String.self, forKey: key) {
        guard let v = Double(s) else { throw FeedError.badResponse("不是数字：\(s)") }
        return v
      }
      return try k.decode(Double.self, forKey: key)
    }
    bar = Bar(openTime: openTime, open: try d(.o), high: try d(.h),
              low: try d(.l), close: try d(.c), volume: try d(.v))
  }

  enum Outer: String, CodingKey { case e, E, s, k }
  enum Inner: String, CodingKey { case t, T, s, i, o, h, l, c, v, x, L }
}

/// `trade` 事件：一笔成交。
///
/// 币安合约的字段是 `p`（价）、`q`（量）、`T`（撮合时间毫秒）。时间用 `T` 不用 `E`：
/// `E` 是服务器发出这条推送的时刻，跨周期边界时那点延迟会把最后一笔成交折错到下一根上。
public struct TradeEvent: Sendable, Equatable, Decodable {
  public var symbol: String
  public var price: Double
  public var qty: Double
  public var timeMs: Int64
  public var tradeID: Int64?

  public init(symbol: String, price: Double, qty: Double, timeMs: Int64, tradeID: Int64? = nil) {
    self.symbol = symbol; self.price = price; self.qty = qty; self.timeMs = timeMs; self.tradeID = tradeID
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: K.self)
    symbol = try c.decode(String.self, forKey: .s)
    func num(_ key: K) throws -> Double {
      if let s = try? c.decode(String.self, forKey: key) {
        guard let v = Double(s) else { throw FeedError.badResponse("不是数字：\(s)") }
        return v
      }
      return try c.decode(Double.self, forKey: key)
    }
    tradeID = try c.decodeIfPresent(Int64.self, forKey: .t)
    price = try num(.p)
    qty = try num(.q)
    timeMs = (try? c.decode(Int64.self, forKey: .T)) ?? (try? c.decode(Int64.self, forKey: .E)) ?? 0
  }

  enum K: String, CodingKey { case e, s, p, q, T, E, t, m }
}

// ---------------------------------------------------------------- 运行时限额

/// `exchangeInfo` 里那份 `rateLimits`：上游自己公布的当前限额（A.2）。
///
/// 硬编码 2400 是抄文档抄来的，币安调整过就只能靠我们发现 429 才知道。
/// 每次取品种表都会回这份，顺手把 `RateLimiter` 的预算对上去
/// （`RateLimiter.apply(rules:)`）。
public struct BinanceRateLimitRule: Decodable, Sendable, Equatable {
  /// `REQUEST_WEIGHT` / `ORDERS` / `RAW_REQUESTS`。
  public var rateLimitType: String
  /// `MINUTE` / `SECOND` / `DAY`。
  public var interval: String
  public var intervalNum: Int
  public var limit: Int

  public init(rateLimitType: String, interval: String, intervalNum: Int, limit: Int) {
    self.rateLimitType = rateLimitType
    self.interval = interval
    self.intervalNum = intervalNum
    self.limit = limit
  }

  /// 这一条是不是「每 1 分钟的请求权重」那条。
  public var isRequestWeightPerMinute: Bool {
    rateLimitType.uppercased() == "REQUEST_WEIGHT"
      && interval.uppercased() == "MINUTE" && intervalNum == 1
  }
}

struct RateLimitsDTO: Decodable {
  var rateLimits: [BinanceRateLimitRule]?
}
