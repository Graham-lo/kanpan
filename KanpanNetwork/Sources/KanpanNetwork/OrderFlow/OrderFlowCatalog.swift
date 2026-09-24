import Foundation
import KanpanCore

/// 一只币有哪几本簿、怎么分到几条连接上。
///
/// 1. 查网关的品种表 `GET /v1/market/orderflow/instruments?base=BTC`（kanpan-api 每 10 分钟把币安 /
///    OKX / Coinbase 的七张合约表汇总一次，只查内存）：各家各产品的合约代号、面值口径、交割时间、
///    币安带前缀的缩放（`1000PEPE`）。两条线路都查网关——这是网关专属的只读接口，和行情走哪条路无关。
/// 2. 查不到（网关都不通、回了坏数据、一本都没有）就用保底那几本：币安 U 本位永续 `<BASE>USDT`、
///    币安现货 `<BASE>USDT`、Coinbase `<BASE>-USD`。哪本不存在，它的快照回 4xx，那本就一直不就绪，
///    图上少一本而已。
/// 3. 分连接（`adapters`）：币安 U 本位、币本位各一条组合流（一条最多 4 本），币安现货一条，
///    OKX 一条中继（一条最多 12 本），Coinbase 一本一条。一只 BTC 满打满算 5 条连接，其中走网关中继的
///    2–3 条（中继全进程上限 64 条）。
///
/// 哪几种产品真的要订由调用方按门槛决定（没有门槛的产品不订，例如非加密只有 U 本位永续）。
public struct OrderFlowCatalog: Sendable {
  public static let path = "/v1/market/orderflow/instruments"
  /// 同一只币的品种表在内存里留多久（网关那边 10 分钟刷一次表）。
  static let cacheMs: Int64 = 10 * 60_000

  let route: MarketRoute
  let binanceHosts: BinanceHosts
  let sockets: any WSSocketFactory
  let http: any HTTPTransport
  let cache: OrderFlowCatalogCache

  public init(route: MarketRoute, binanceHosts: BinanceHosts = .default,
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport(),
              cache: OrderFlowCatalogCache = .shared) {
    self.route = route; self.binanceHosts = binanceHosts
    self.sockets = sockets; self.http = http; self.cache = cache
  }

  /// 一只币的全部簿。
  public struct Books: Sendable, Equatable {
    /// 去掉缩放前缀之后的币名（`1000PEPE` → `PEPE`）。
    public var base: String
    /// 图上那只品种一个价格单位是几个币（`1000PEPEUSDT` 为 1000，其余为 1）。
    public var chartScale: Double
    public var books: [DepthBook]
    /// 来自网关的品种表；false 是保底那几本。
    public var fromCatalog: Bool
  }

  // ------------------------------------------------------------------ 查表

  /// `base` 是图上那只品种的 base 资产（`SymbolInfo.base`，例如 `BTC`、`1000PEPE`）。
  public func books(base viewedBase: String, nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async -> Books {
    let (base, scale) = OrderFlowBase.normalize(viewedBase)
    guard OrderFlowBase.isValid(base) else {
      return Books(base: base, chartScale: scale, books: [], fromCatalog: false)
    }
    if let rows = await cache.rows(base: base, nowMs: nowMs) {
      return Books(base: base, chartScale: scale, books: Self.books(rows, chartScale: scale, nowMs: nowMs), fromCatalog: true)
    }
    for host in route.gateways {
      guard var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { continue }
      c.path = Self.path
      c.queryItems = [URLQueryItem(name: "base", value: base)]
      guard let url = c.url else { continue }
      do {
        let reply = try await http.get(url, timeout: 6)
        guard (200..<300).contains(reply.status), let rows = Self.parse(reply.body), !rows.isEmpty else { continue }
        await cache.store(rows, base: base, nowMs: nowMs)
        let books = Self.books(rows, chartScale: scale, nowMs: nowMs)
        if !books.isEmpty { return Books(base: base, chartScale: scale, books: books, fromCatalog: true) }
      } catch is CancellationError {
        break
      } catch {
        continue
      }
    }
    return Books(base: base, chartScale: scale,
                 books: Self.fallback(viewedBase: viewedBase.uppercased(), base: base, chartScale: scale),
                 fromCatalog: false)
  }

  /// 品种表的一行（字段名是和 kanpan-api `orderflow_instruments.rs` 的约定）。
  public struct Row: Sendable, Equatable {
    public var exchange: String
    public var product: OrderFlowProduct
    public var instrument: String
    public var notional: OrderFlowNotional
    public var expiryMs: Int64?
    public var priceScale: Double
  }

  /// 解析品种表。整体不是那个形状就是 nil；单行坏了（未知交易所、未知产品、面值不对）只丢那一行。
  static func parse(_ data: Data) -> [Row]? {
    guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let venues = obj["venues"] as? [[String: Any]] else { return nil }
    return venues.compactMap { v in
      guard let exchange = v["exchange"] as? String, OrderFlowBase.exchanges[exchange] != nil,
            let product = (v["product"] as? String).flatMap(OrderFlowProduct.init(rawValue:)),
            let instrument = v["instrument"] as? String, OrderFlowBase.isValidInstrument(instrument),
            let n = v["notional"] as? [String: Any] else { return nil }
      let notional: OrderFlowNotional
      switch n["kind"] as? String {
      case "linear":
        guard let m = DepthWire.number(n["multiplier"]) else { return nil }
        notional = .linear(multiplier: m)
      case "inverse":
        guard let c = DepthWire.number(n["contractUsd"]) else { return nil }
        notional = .inverse(contractUsd: c)
      default:
        return nil
      }
      guard notional.isValid else { return nil }
      let scale = DepthWire.number(v["priceScale"]) ?? 1
      guard scale.isFinite, scale > 0 else { return nil }
      return Row(exchange: exchange, product: product, instrument: instrument, notional: notional,
                 expiryMs: DepthWire.integer(v["expiryMs"]), priceScale: scale)
    }
  }

  /// 行 → 簿。已经过了交割时间的剔掉（表还没刷新时）。
  static func books(_ rows: [Row], chartScale: Double, nowMs: Int64) -> [DepthBook] {
    var seen = Set<String>()
    return rows.compactMap { row in
      if let expiry = row.expiryMs, expiry <= nowMs { return nil }
      let book = DepthBook(venue: venue(exchange: row.exchange, product: row.product, instrument: row.instrument,
                                        notional: row.notional),
                           priceFactor: chartScale / row.priceScale, expiryMs: row.expiryMs)
      return seen.insert(book.id).inserted ? book : nil
    }
  }

  static func fallback(viewedBase: String, base: String, chartScale: Double) -> [DepthBook] {
    [DepthBook(venue: venue(exchange: "binance", product: .usdtPerp, instrument: viewedBase + "USDT",
                            notional: .linear(multiplier: 1))),
     DepthBook(venue: venue(exchange: "binance", product: .spot, instrument: base + "USDT",
                            notional: .linear(multiplier: 1)), priceFactor: chartScale),
     DepthBook(venue: venue(exchange: "coinbase", product: .spot, instrument: base + "-USD",
                            notional: .linear(multiplier: 1)), priceFactor: chartScale)]
  }

  static func venue(exchange: String, product: OrderFlowProduct, instrument: String,
                    notional: OrderFlowNotional) -> OrderFlowVenue {
    let model: DepthSequenceModel
    let inBand: Bool
    switch exchange {
    case "okx": model = .previousFinalExact; inBand = true
    case "coinbase": model = .strictIncrementing; inBand = true
    default: model = product == .spot ? .rangeOverlap : .previousFinalOverlap; inBand = false
    }
    return OrderFlowVenue(exchange: exchange, label: OrderFlowBase.exchanges[exchange] ?? exchange, product: product,
                          instrument: instrument, notional: notional, sequenceModel: model, snapshotInBand: inBand)
  }

  // ------------------------------------------------------------------ 分连接

  /// 把要订的簿分到连接上。顺序：币安 U 本位、币安币本位、币安现货、OKX、Coinbase。
  /// 没有网关时 OKX 那几本订不了（只有中继能到 OKX），直接不给。
  public func adapters(_ books: [DepthBook]) -> [any DepthFeedAdapter] {
    var binance: [BinanceDepthAdapter.Market: [DepthBook]] = [:]
    var okx: [DepthBook] = []
    var coinbase: [DepthBook] = []
    for book in books {
      switch book.venue.exchange {
      case "binance": binance[Self.binanceMarket(book.venue), default: []].append(book)
      case "okx": okx.append(book)
      case "coinbase": coinbase.append(book)
      default: continue
      }
    }
    var out: [any DepthFeedAdapter] = []
    for market in BinanceDepthAdapter.Market.allCases {
      for chunk in Self.chunks(binance[market] ?? [], BinanceDepthAdapter.maxBooks) {
        out.append(BinanceDepthAdapter(market: market, books: chunk, hosts: binanceHosts, route: route,
                                       sockets: sockets, http: http))
      }
    }
    if !route.gateways.isEmpty {
      for chunk in Self.chunks(okx, OKXBooksAdapter.maxBooks) {
        out.append(OKXBooksAdapter(books: chunk, gateways: route.gateways, sockets: sockets))
      }
    }
    for book in coinbase { out.append(CoinbaseLevel2Adapter(book: book, sockets: sockets)) }
    return out
  }

  static func binanceMarket(_ venue: OrderFlowVenue) -> BinanceDepthAdapter.Market {
    switch venue.product {
    case .spot: .spot
    case .usdtPerp: .um
    case .coinPerp: .cm
    case .delivery:
      if case .inverse = venue.notional { .cm } else { .um }
    }
  }

  static func chunks(_ books: [DepthBook], _ size: Int) -> [[DepthBook]] {
    stride(from: 0, to: books.count, by: max(1, size)).map { Array(books[$0..<min($0 + max(1, size), books.count)]) }
  }
}

/// 币名的小工具。
public enum OrderFlowBase {
  /// 交易所代号 → 显示名。
  public static let exchanges: [String: String] = ["binance": "币安", "okx": "OKX", "coinbase": "Coinbase"]

  /// 币安给单价极小的币加的前缀（和 kanpan-api `BINANCE_SCALED` 同一张）。长的在前。
  static let scaledPrefixes: [(String, Double)] = [("1000000", 1_000_000), ("1000", 1000), ("1M", 1_000_000)]

  /// `1000PEPE` → (`PEPE`, 1000)；`1MBABYDOGE` → (`BABYDOGE`, 1e6)；其余原样、1。
  public static func normalize(_ base: String) -> (base: String, scale: Double) {
    let upper = base.uppercased()
    for (prefix, scale) in scaledPrefixes where upper.hasPrefix(prefix) {
      let rest = String(upper.dropFirst(prefix.count))
      if isValid(rest), rest.first.map({ !$0.isNumber }) ?? false { return (rest, scale) }
    }
    return (upper, 1)
  }

  /// kanpan-api 只收 `^[A-Z0-9]{1,20}$`。
  public static func isValid(_ base: String) -> Bool {
    !base.isEmpty && base.count <= 20 && base.allSatisfy { ($0.isASCII && $0.isUppercase) || $0.isASCII && $0.isNumber }
  }

  /// 合约代号：字母数字、`-`、`_`，不长于 40。
  static func isValidInstrument(_ s: String) -> Bool {
    !s.isEmpty && s.count <= 40 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
  }
}

/// 品种表的内存缓存（按 base，10 分钟）。
public actor OrderFlowCatalogCache {
  public static let shared = OrderFlowCatalogCache()
  private var entries: [String: (rows: [OrderFlowCatalog.Row], atMs: Int64)] = [:]
  public init() {}

  func rows(base: String, nowMs: Int64) -> [OrderFlowCatalog.Row]? {
    guard let e = entries[base], nowMs - e.atMs < OrderFlowCatalog.cacheMs, nowMs >= e.atMs else { return nil }
    return e.rows
  }

  func store(_ rows: [OrderFlowCatalog.Row], base: String, nowMs: Int64) {
    if entries.count > 64 { entries.removeAll() }
    entries[base] = (rows, nowMs)
  }
}
