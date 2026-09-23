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
  /// 第 9 格：主动买成交量（base）。CVD 的原料，见 `Bar.takerBuy`。
  var takerBuy: Double

  init(from decoder: Decoder) throws {
    var c = try decoder.unkeyedContainer()
    openTime = try c.decode(Int64.self)
    open = try KlineRow.num(&c)
    high = try KlineRow.num(&c)
    low = try KlineRow.num(&c)
    close = try KlineRow.num(&c)
    volume = try KlineRow.num(&c)
    closeTime = try c.decode(Int64.self)
    // 成交额、笔数跳过，接着的第 9 格是主动买成交量。镜像站偶尔把这一行截短，
    // 解不出来就当缺失（NaN），不能当 0——0 会被读成「整根都是主动卖」。
    if (try? KlineRow.skip(&c, 2)) != nil, let tb = try? KlineRow.num(&c) { takerBuy = tb }
    else { takerBuy = .nan }
    guard bar.isValidMarketBar else { throw FeedError.badResponse("无效的 OHLCV") }
  }

  /// 往后跳 `k` 格，跳不动（行被截短）就抛。
  private static func skip(_ c: inout UnkeyedDecodingContainer, _ k: Int) throws {
    for _ in 0..<k {
      if (try? c.decode(String.self)) != nil { continue }
      if (try? c.decode(Double.self)) != nil { continue }
      _ = try c.decode(Int64.self)
    }
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

  var bar: Bar {
    Bar(openTime: openTime, open: open, high: high, low: low, close: close, volume: volume,
        takerBuy: takerBuy)
  }
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
    /// 上线时间（毫秒）。只给「新」记号用（P2.15）；缺了就当不知道。
    var onboardDate: Int64?

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

// -------------------------------------------- 多空比 / 主动买卖比 / 基差

/// `/futures/data/*` 这一族的数值**全是字符串**，而且可能是空串——实测 `basis` 的
/// `annualizedBasisRate` 一直发 `""`。空串和解不动的串一律当「这一项没有」，不当错误：
/// 为了一个附带字段把整条记录判废，图上就会平白缺一截。
private func futuresDataNumber(_ text: String?) -> Double? {
  guard let text, !text.isEmpty, let v = Double(text), v.isFinite else { return nil }
  return v
}

/// 全市场多空账户数比的一个点。
///
/// 口径是**账户数**之比（多头账户数 ÷ 空头账户数），不是持仓量之比，也不是大户口径。
public struct LongShortRatioPoint: Sendable, Equatable {
  public var timeMs: Int64
  public var ratio: Double
  /// 多头 / 空头账户各占全市场的比例（0…1，两项相加为 1）。缺了不影响 `ratio`。
  public var longAccount: Double?
  public var shortAccount: Double?

  public init(timeMs: Int64, ratio: Double, longAccount: Double? = nil, shortAccount: Double? = nil) {
    self.timeMs = timeMs; self.ratio = ratio
    self.longAccount = longAccount; self.shortAccount = shortAccount
  }
}

/// 主动买卖量比的一个点：主动买入量 ÷ 主动卖出量。
///
/// 这一族的响应里**没有 symbol**，调用方只能靠自己发的请求知道这是谁的数。
public struct TakerRatioPoint: Sendable, Equatable {
  public var timeMs: Int64
  public var buySellRatio: Double
  public var buyVolume: Double?
  public var sellVolume: Double?

  public init(timeMs: Int64, buySellRatio: Double, buyVolume: Double? = nil, sellVolume: Double? = nil) {
    self.timeMs = timeMs; self.buySellRatio = buySellRatio
    self.buyVolume = buyVolume; self.sellVolume = sellVolume
  }
}

/// 基差的一个点：永续合约价相对指数价的偏离。
public struct BasisPoint: Sendable, Equatable {
  public var timeMs: Int64
  /// 合约价 − 指数价，报价货币计。
  public var basis: Double
  /// 基差率（小数，不是百分数）。
  public var basisRate: Double
  public var indexPrice: Double?
  /// 合约价。币安这儿的字段名是 `futuresPrice`，不是 `contractPrice`。
  public var futuresPrice: Double?
  /// 年化基差率。实测币安在永续上一直发空串，所以它基本永远是 nil——
  /// 有它当锦上添花，没它不能判废整条记录。
  public var annualizedBasisRate: Double?

  public init(timeMs: Int64, basis: Double, basisRate: Double, indexPrice: Double? = nil,
              futuresPrice: Double? = nil, annualizedBasisRate: Double? = nil) {
    self.timeMs = timeMs; self.basis = basis; self.basisRate = basisRate
    self.indexPrice = indexPrice; self.futuresPrice = futuresPrice
    self.annualizedBasisRate = annualizedBasisRate
  }
}

struct LongShortRatioDTO: Decodable {
  var symbol: String?
  var longShortRatio: String?
  var longAccount: String?
  var shortAccount: String?
  var timestamp: Int64?

  /// 主字段（比值、时刻）缺一不可，附带字段缺了照收。
  var point: LongShortRatioPoint? {
    guard let timestamp, timestamp > 0, let ratio = futuresDataNumber(longShortRatio), ratio >= 0 else { return nil }
    return LongShortRatioPoint(timeMs: timestamp, ratio: ratio,
                               longAccount: futuresDataNumber(longAccount),
                               shortAccount: futuresDataNumber(shortAccount))
  }
}

struct TakerRatioDTO: Decodable {
  var buySellRatio: String?
  var buyVol: String?
  var sellVol: String?
  var timestamp: Int64?

  var point: TakerRatioPoint? {
    guard let timestamp, timestamp > 0, let ratio = futuresDataNumber(buySellRatio), ratio >= 0 else { return nil }
    return TakerRatioPoint(timeMs: timestamp, buySellRatio: ratio,
                           buyVolume: futuresDataNumber(buyVol),
                           sellVolume: futuresDataNumber(sellVol))
  }
}

struct BasisDTO: Decodable {
  var pair: String?
  var contractType: String?
  var basis: String?
  var basisRate: String?
  var indexPrice: String?
  var futuresPrice: String?
  var annualizedBasisRate: String?
  var timestamp: Int64?

  var point: BasisPoint? {
    guard let timestamp, timestamp > 0,
          let basis = futuresDataNumber(basis), let rate = futuresDataNumber(basisRate) else { return nil }
    return BasisPoint(timeMs: timestamp, basis: basis, basisRate: rate,
                      indexPrice: futuresDataNumber(indexPrice),
                      futuresPrice: futuresDataNumber(futuresPrice),
                      annualizedBasisRate: futuresDataNumber(annualizedBasisRate))
  }
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
  /// 保留帧解析，无消费方；强平功能不做，见 docs/不做清单.md。
  case forceOrder(LiquidationEvent)
  /// 逐笔聚合成交（`@aggTrade`）：给主动买卖比补当前这根的实时尾巴。
  case aggTrade(AggTradeEvent)
  /// 五档全量快照（`@depth5@100ms`）。
  case depth(DepthSnapshot)
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
      // 网关转的替身帧（OKX）不带 `p`，同一帧里的最新价减 24h 开盘价就是它——币安自己
      // 的 `p` 也是这么定义的。`q`（成交额）替身帧里是空串，这里留成缺失，由 REST 那帧补。
      let last = d(.c), open = d(.o)
      var change = d(.p)
      if !change.isFinite, last.isFinite, open.isFinite, open > 0 { change = last - open }
      self = .ticker(Ticker(symbol: sym, last: last, changePercent: d(.P),
                            high: d(.h), low: d(.l), quoteVolume: d(.q), open24h: open, timeMs: try c.decodeIfPresent(Int64.self, forKey: .C),
                            lastTradeID: try c.decodeIfPresent(Int64.self, forKey: .L), priceChange: change))
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
    case "forceOrder":
      self = .forceOrder(try LiquidationEvent(from: decoder))
    case "aggTrade":
      self = .aggTrade(try AggTradeEvent(from: decoder))
    case "depthUpdate":
      // `@depth5@100ms` 的事件名也是 `depthUpdate`（见 `DepthSnapshot`）。
      self = .depth(try DepthSnapshot(from: decoder))
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
    // `V` 是这根到目前为止的主动买成交量。币安的 kline 推流一直带着它，
    // 但网关、镜像、回放都可能不给：拿不到就留 NaN，绝不填 0。
    bar = Bar(openTime: openTime, open: try d(.o), high: try d(.h),
              low: try d(.l), close: try d(.c), volume: try d(.v),
              takerBuy: (try? d(.V)) ?? .nan)
  }

  enum Outer: String, CodingKey { case e, E, s, k }
  enum Inner: String, CodingKey { case t, T, s, i, o, h, l, c, v, x, L, V }
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

// ---------------------------------------------------------------- 强平 / 逐笔 / 盘口

/// 一笔强平里**被平掉的是哪一边**。
///
/// 币安发的 `S` 是**系统这张平仓单的方向**，不是被平仓位的方向，两者正好相反：
/// `S == "SELL"` 是系统卖出去平掉一个**多头**（多头爆仓），`S == "BUY"` 是买回来
/// 平掉一个**空头**。这条流最常被搞错的就是这一点，所以这儿存的是「谁被平了」，
/// 不是原样的 `S`——调用方拿到 `.long` 就是多头爆仓，不用再反一次。
public enum LiquidationSide: Sendable, Equatable {
  case long, short
}

/// 保留的强平事件模型（`forceOrder`），功能不做，见 docs/不做清单.md。
///
/// 只留这张图上要用的四项：品种、被平的方向、成交均价 `ap`、累计成交量 `z`、
/// 撮合时间 `T`。委托价 `p` 和委托量 `q` 不留——爆仓柱看的是**真的成交了多少**，
/// 强平单是 IOC，委托量里有没吃掉的部分。
///
/// 时间用 `T` 不用 `E`，理由和 `TradeEvent` 一样：`E` 是推送时刻，跨周期边界时
/// 会把这一笔折错到下一根上。
public struct LiquidationEvent: Sendable, Equatable, Decodable {
  public var symbol: String
  public var side: LiquidationSide
  /// 成交均价 `ap`。
  public var price: Double
  /// 累计成交量 `z`，按合约标的计。乘以 `price` 才是名义额。
  public var qty: Double
  public var timeMs: Int64

  /// 名义额（报价货币）。双色柱要画的就是它。
  public var notional: Double { price * qty }

  public init(symbol: String, side: LiquidationSide, price: Double, qty: Double, timeMs: Int64) {
    self.symbol = symbol; self.side = side; self.price = price; self.qty = qty; self.timeMs = timeMs
  }

  public init(from decoder: Decoder) throws {
    let outer = try decoder.container(keyedBy: Outer.self)
    let o = try outer.nestedContainer(keyedBy: Inner.self, forKey: .o)
    symbol = try o.decode(String.self, forKey: .s)
    let raw = (try? o.decode(String.self, forKey: .S))?.uppercased() ?? ""
    switch raw {
    case "SELL": side = .long
    case "BUY": side = .short
    default: throw FeedError.badResponse("强平方向不认识：\(raw)")
    }
    func num(_ key: Inner) throws -> Double {
      if let s = try? o.decode(String.self, forKey: key) {
        guard let v = Double(s) else { throw FeedError.badResponse("不是数字：\(s)") }
        return v
      }
      return try o.decode(Double.self, forKey: key)
    }
    price = try num(.ap)
    qty = try num(.z)
    timeMs = (try? o.decode(Int64.self, forKey: .T))
      ?? (try? outer.decode(Int64.self, forKey: .E)) ?? 0
  }

  enum Outer: String, CodingKey { case e, E, o }
  enum Inner: String, CodingKey { case s, S, o, f, q, p, ap, X, l, z, T }
}

/// 聚合成交事件（`aggTrade`）：同一时刻、同一价位、同一方向的若干笔并成一条。
public struct AggTradeEvent: Sendable, Equatable, Decodable {
  public var symbol: String
  public var price: Double
  public var qty: Double
  public var timeMs: Int64
  public var aggID: Int64?
  /// 币安的 `m`：**买方是不是挂单方**。
  ///
  /// 语义是反直觉的：`m == true` 说明买单挂在盘口等着、是**卖方主动**吃过来的，
  /// 这笔算**主动卖出**；`m == false` 才是主动买入。算主动买卖比时按 `takerIsBuyer`
  /// 分桶，别直接拿 `m` 当「买」。
  public var isBuyerMaker: Bool

  /// 这一笔是不是主动买入（吃单方是买方）。
  public var takerIsBuyer: Bool { !isBuyerMaker }

  public init(symbol: String, price: Double, qty: Double, timeMs: Int64,
              aggID: Int64? = nil, isBuyerMaker: Bool) {
    self.symbol = symbol; self.price = price; self.qty = qty
    self.timeMs = timeMs; self.aggID = aggID; self.isBuyerMaker = isBuyerMaker
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
    price = try num(.p)
    qty = try num(.q)
    aggID = try c.decodeIfPresent(Int64.self, forKey: .a)
    isBuyerMaker = (try? c.decode(Bool.self, forKey: .m)) ?? false
    timeMs = (try? c.decode(Int64.self, forKey: .T)) ?? (try? c.decode(Int64.self, forKey: .E)) ?? 0
  }

  enum K: String, CodingKey { case e, E, s, a, p, q, f, l, T, m }
}

/// 盘口的一档：价 + 量。
public struct DepthLevel: Sendable, Equatable {
  public var price: Double
  public var qty: Double
  public init(price: Double, qty: Double) { self.price = price; self.qty = qty }
}

/// 五档全量快照（`@depth5@100ms`）。
///
/// 事件名是 `depthUpdate`，**但它不是增量流**：partial book depth 每一帧就是完整的
/// 前五档，`U`/`u`/`pu` 那套序号在这儿用不上，也不需要先拉一份 REST 快照来对齐。
/// 照增量流的写法去合并本地订单簿，只会把同一份快照叠加成越来越厚的假盘口。
///
/// 实测一帧（2026-09-22，`dstream.binance.me`）：
/// `{"e":"depthUpdate","E":..,"T":..,"s":"BTCUSDT","ps":"BTCUSDT","U":..,"u":..,"pu":..,
///   "b":[["85606.30","16.972"],…5 条],"a":[["85606.40","0.094"],…5 条],"st":1}`
public struct DepthSnapshot: Sendable, Equatable, Decodable {
  public var symbol: String
  /// 买盘，价格由高到低（币安自己就是这个顺序，原样保留）。
  public var bids: [DepthLevel]
  /// 卖盘，价格由低到高。
  public var asks: [DepthLevel]
  public var timeMs: Int64

  public init(symbol: String, bids: [DepthLevel], asks: [DepthLevel], timeMs: Int64) {
    self.symbol = symbol; self.bids = bids; self.asks = asks; self.timeMs = timeMs
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: K.self)
    symbol = (try? c.decode(String.self, forKey: .s)) ?? ""
    bids = try Self.levels(c.decodeIfPresent([[JSONValue]].self, forKey: .b))
    asks = try Self.levels(c.decodeIfPresent([[JSONValue]].self, forKey: .a))
    // 撮合时间 `T` 优先，`E` 是推送时刻。
    timeMs = (try? c.decode(Int64.self, forKey: .T)) ?? (try? c.decode(Int64.self, forKey: .E)) ?? 0
  }

  /// 每一档是 `["价","量"]`。价量照旧收字符串和数字两种写法（回放文件和镜像会发数字）。
  private static func levels(_ rows: [[JSONValue]]?) throws -> [DepthLevel] {
    try (rows ?? []).map { row in
      guard row.count >= 2, let price = row[0].doubleValue, let qty = row[1].doubleValue else {
        throw FeedError.badResponse("盘口档位不是数字")
      }
      return DepthLevel(price: price, qty: qty)
    }
  }

  enum K: String, CodingKey { case e, E, T, s, b, a }
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
