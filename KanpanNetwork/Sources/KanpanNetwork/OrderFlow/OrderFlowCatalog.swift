import Foundation
import KanpanCore

/// 一只币有哪几本簿、怎么分到几条连接上。本文件只查交易所注册表（`VenueRegistry.orderFlow`），
/// 不认识任何一家；各家的序号模型、快照来源、连接怎么分、保底订哪几本都写在各家目录的条目里。
///
/// 1. 查 kanpan-api 的品种表 `GET /v1/market/orderflow/instruments?base=BTC`（服务端每 10 分钟把各家合约表
///    汇总一次，只查内存）：各家各产品的合约代号、面值口径、交割时间、价格缩放（`priceScale`）。
///    两条线路都查 `MarketRoute.apiHosts`（只有主机）——和行情走哪条路无关。
///    表在本机留一份（`OrderFlowCatalogCache`，Caches 目录，按币）：10 分钟内直接用；24 小时内先用着、后台再问一次；
///    再旧才等服务端。原来只留内存、冷启动开图每只币都先等这一问（一个往返 0.6 秒以上，2026-10-07）。
/// 2. 查不到（网关都不通、回了坏数据、一本都没有）就按注册表顺序取各家的保底簿（`OrderFlowExchange.fallback`）。
///    哪本不存在，它就一直不就绪，图上少一本而已。
/// 3. 分连接（`adapters`）：按注册表顺序把簿交给各家的 `makeAdapters`。
///
/// 哪几种产品真的要订由调用方按门槛决定（没有门槛的产品不订，例如非加密只有 U 本位永续）。
public struct OrderFlowCatalog: Sendable {
  public static let path = "/v1/market/orderflow/instruments"
  /// 同一只币的品种表算新鲜多久（网关那边 10 分钟刷一次表）；旧到多久之内还先用着、后台刷新。
  static let cacheMs: Int64 = 10 * 60_000
  static let staleMs: Int64 = 24 * 3_600_000

  let route: MarketRoute
  let sockets: any WSSocketFactory
  let http: any HTTPTransport
  let cache: OrderFlowCatalogCache

  public init(route: MarketRoute,
              sockets: any WSSocketFactory = URLSessionSocketFactory(),
              http: any HTTPTransport = URLSessionTransport(),
              cache: OrderFlowCatalogCache = .shared) {
    self.route = route
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

    public init(base: String, chartScale: Double, books: [DepthBook], fromCatalog: Bool) {
      self.base = base; self.chartScale = chartScale; self.books = books; self.fromCatalog = fromCatalog
    }
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
    if let rows = await cache.staleRows(base: base, nowMs: nowMs) {
      // 旧一点的先用着（交割合约多半还是那几张；到期的 books() 会剔掉），后台问一次给下一回
      let me = self
      Task.detached(priority: .utility) { _ = await me.fetch(base: base, nowMs: nowMs) }
      return Books(base: base, chartScale: scale, books: Self.books(rows, chartScale: scale, nowMs: nowMs), fromCatalog: true)
    }
    if let rows = await fetch(base: base, nowMs: nowMs) {
      let books = Self.books(rows, chartScale: scale, nowMs: nowMs)
      if !books.isEmpty { return Books(base: base, chartScale: scale, books: books, fromCatalog: true) }
    }
    return Books(base: base, chartScale: scale,
                 books: Self.fallback(viewedBase: viewedBase.uppercased(), base: base, chartScale: scale),
                 fromCatalog: false)
  }

  /// 向服务端问这只币的表；拿到就存进缓存。都不通、回了坏数据是 nil。
  func fetch(base: String, nowMs: Int64) async -> [Row]? {
    for host in route.apiHosts {
      guard var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { continue }
      c.path = Self.path
      c.queryItems = [URLQueryItem(name: "base", value: base)]
      guard let url = c.url else { continue }
      do {
        let reply = try await http.get(url, timeout: 6)
        guard (200..<300).contains(reply.status), let rows = Self.parse(reply.body), !rows.isEmpty else { continue }
        await cache.store(rows, base: base, nowMs: nowMs)
        return rows
      } catch is CancellationError {
        break
      } catch {
        continue
      }
    }
    return nil
  }

  // ------------------------------------------------------------------ 服务端历史

  public static let historyPath = "/v1/market/orderflow/history"

  /// 取服务端记下的大单生命周期（`fromMs…toMs`，服务端只存 3 天）。`base` 是去掉缩放前缀的币名
  /// （`OrderFlowBase.normalize` 之后的）。两条线路都查 `MarketRoute.apiHosts`，哪台回了就用哪台；
  /// 都不通、回了坏数据就是 nil——调用方当它没有，照常只用本地跟到的，不报错、不提示。
  /// 24 小时一页 BTC 约 1.7 MB（gzip 后），URLSession 自己解压；超时给 15 秒。
  ///
  /// `minLifeMs` 给了时带上同名参数：服务端不回活不到这么久就结束的单（挂着的照回）。数据层只在往左补
  /// （24 小时之前）的页上给 5 分钟；nil 不带这个参数。还没认这个参数的旧服务端回 400，这时去掉它再问一次。
  public func history(base: String, fromMs: Int64, toMs: Int64, minLifeMs: Int64? = nil) async -> OrderFlowHistoryPage? {
    guard OrderFlowBase.isValid(base), fromMs >= 0, fromMs <= toMs, (minLifeMs ?? 0) >= 0 else { return nil }
    for host in route.apiHosts {
      guard var c = URLComponents(string: "https://\(host)"), c.host != nil, c.user == nil else { continue }
      c.path = Self.historyPath
      var query = [URLQueryItem(name: "base", value: base),
                   URLQueryItem(name: "from", value: String(fromMs)),
                   URLQueryItem(name: "to", value: String(toMs))]
      var attempts = [query]
      if let minLifeMs {
        query.append(URLQueryItem(name: "minLifeMs", value: String(minLifeMs)))
        attempts = [query, attempts[0]]
      }
      for (k, items) in attempts.enumerated() {
        c.queryItems = items
        guard let url = c.url else { break }
        do {
          let reply = try await http.get(url, timeout: 15)
          // 带了 minLifeMs 回 400：多半是这台还没认这个参数，去掉它再问一次（别的错不重问）。
          if reply.status == 400, k == 0, attempts.count > 1 { continue }
          guard (200..<300).contains(reply.status),
                let page = OrderFlowHistoryPage.parse(reply.body, fromMs: fromMs, toMs: toMs),
                page.base == base else { break }
          return page
        } catch is CancellationError {
          return nil
        } catch {
          break
        }
      }
    }
    return nil
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

  /// 解析品种表。整体不是那个形状就是 nil；单行坏了（注册表里没有的交易所、未知产品、面值不对）只丢那一行。
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

  /// 行 → 落盘用的字典（和服务端 `venues` 里一行同一个形状，读回来走同一个 `parse`）。
  static func encode(_ rows: [Row]) -> [[String: Any]] {
    rows.map { r in
      var v: [String: Any] = ["exchange": r.exchange, "product": r.product.rawValue, "instrument": r.instrument,
                              "priceScale": r.priceScale]
      switch r.notional {
      case .linear(let m): v["notional"] = ["kind": "linear", "multiplier": m]
      case .inverse(let c): v["notional"] = ["kind": "inverse", "contractUsd": c]
      }
      if let e = r.expiryMs { v["expiryMs"] = e }
      return v
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

  /// 保底簿：按注册表顺序取各家的 `fallback`。
  static func fallback(viewedBase: String, base: String, chartScale: Double) -> [DepthBook] {
    VenueRegistry.orderFlow.flatMap { exchange in
      exchange.fallback(viewedBase, base, chartScale).map { f in
        DepthBook(venue: venue(exchange: exchange.key, product: f.product, instrument: f.instrument, notional: f.notional),
                  priceFactor: f.priceFactor)
      }
    }
  }

  /// 一本簿的身份：序号模型、快照来源、显示名都查注册表。表里没有的交易所（服务端先上了、客户端还没认）
  /// 按「每帧整本」记着，`adapters` 不给它连接。
  static func venue(exchange: String, product: OrderFlowProduct, instrument: String,
                    notional: OrderFlowNotional) -> OrderFlowVenue {
    let entry = OrderFlowExchange.named(exchange)
    return OrderFlowVenue(exchange: exchange, label: entry?.displayName ?? exchange, product: product,
                          instrument: instrument, notional: notional,
                          sequenceModel: entry?.sequenceModel(product, notional) ?? .snapshotOnly,
                          snapshotInBand: entry?.snapshotInBand(product) ?? true)
  }

  // ------------------------------------------------------------------ 分连接

  /// 把要订的簿分到连接上：按注册表顺序，每家只拿到自己的簿。注册表里没有的交易所不订。
  public func adapters(_ books: [DepthBook]) -> [any DepthFeedAdapter] {
    let context = OrderFlowConnectContext(route: route, sockets: sockets, http: http)
    return VenueRegistry.orderFlow.flatMap { exchange -> [any DepthFeedAdapter] in
      let mine = books.filter { $0.venue.exchange == exchange.key }
      return mine.isEmpty ? [] : exchange.makeAdapters(mine, context)
    }
  }
}

/// 币名的小工具。
public enum OrderFlowBase {
  /// 交易所代号 → 显示名（由注册表生成）。
  public static let exchanges: [String: String] = Dictionary(
    VenueRegistry.orderFlow.map { ($0.key, $0.displayName) }, uniquingKeysWith: { first, _ in first })

  /// 币安给单价极小的币加的前缀（和 kanpan-api `BINANCE_SCALED` 同一张）。长的在前。
  /// public 是因为 App 测试里的契约生成器（`SettingsFieldContract`）要把它导出到
  /// `Backend/kanpan-api/contract/settings-fields.json`，Rust 那边拿同一份对账（审查第 39 项）。
  public static let scaledPrefixes: [(String, Double)] = [("1000000", 1_000_000), ("1000", 1000), ("1M", 1_000_000)]

  /// base 最长几个字符。和 kanpan-api `ORDER_FLOW_BASE_MAX_LEN` 同一个数，经契约对账。
  public static let maxLength = 20

  /// 千枚计价的另一种写法：小写 `k` 打头、后面是大写币名（`kPEPE`、`kSHIB`）。只认这个小写的 `k`——
  /// 大写的 `KAS`、`KAITO` 是币名本身，不是缩放。
  public static let thousandsPrefix: Character = "k"

  /// `1000PEPE` → (`PEPE`, 1000)；`1MBABYDOGE` → (`BABYDOGE`, 1e6)；`kPEPE` → (`PEPE`, 1000)；其余原样、1。
  public static func normalize(_ base: String) -> (base: String, scale: Double) {
    if base.first == thousandsPrefix {
      let rest = String(base.dropFirst())
      if isValid(rest), rest.first.map({ !$0.isNumber }) ?? false { return (rest, 1000) }
    }
    let upper = base.uppercased()
    for (prefix, scale) in scaledPrefixes where upper.hasPrefix(prefix) {
      let rest = String(upper.dropFirst(prefix.count))
      if isValid(rest), rest.first.map({ !$0.isNumber }) ?? false { return (rest, scale) }
    }
    return (upper, 1)
  }

  /// kanpan-api 只收 `^[A-Z0-9]{1,20}$`。
  public static func isValid(_ base: String) -> Bool {
    !base.isEmpty && base.count <= maxLength && base.allSatisfy { ($0.isASCII && $0.isUppercase) || $0.isASCII && $0.isNumber }
  }

  /// 合约代号：字母数字、`-`、`_`，不长于 40。
  static func isValidInstrument(_ s: String) -> Bool {
    !s.isEmpty && s.count <= 40 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
  }
}

/// 品种表的缓存（按 base）：内存一份，`file` 给了就同时落盘（一个 JSON，`{ base: { atMs, venues } }`，几十只币几十 KB），
/// 冷启动第一次查时读回来。10 分钟内算新鲜；24 小时内算旧、先用着再刷；更旧不用。
public actor OrderFlowCatalogCache {
  public static let shared = OrderFlowCatalogCache(file: defaultFile)
  /// Caches/kanpan/orderflow-catalog.json（系统缺空间会清，清了就是再问一次服务端）。
  static var defaultFile: URL? {
    guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
    return base.appendingPathComponent("kanpan", isDirectory: true).appendingPathComponent("orderflow-catalog.json")
  }
  private var entries: [String: (rows: [OrderFlowCatalog.Row], atMs: Int64)] = [:]
  private let file: URL?
  private var loaded = false

  public init(file: URL? = nil) { self.file = file }

  func rows(base: String, nowMs: Int64) -> [OrderFlowCatalog.Row]? {
    load()
    guard let e = entries[base], nowMs - e.atMs < OrderFlowCatalog.cacheMs, nowMs >= e.atMs else { return nil }
    return e.rows
  }

  /// 不新鲜但还没过 24 小时的那份（先用着、后台刷）。
  func staleRows(base: String, nowMs: Int64) -> [OrderFlowCatalog.Row]? {
    load()
    guard let e = entries[base], nowMs - e.atMs < OrderFlowCatalog.staleMs, nowMs >= e.atMs else { return nil }
    return e.rows
  }

  func store(_ rows: [OrderFlowCatalog.Row], base: String, nowMs: Int64) {
    load()
    if entries.count > 64 { entries.removeAll() }
    entries[base] = (rows, nowMs)
    save()
  }

  private func load() {
    guard !loaded else { return }
    loaded = true
    guard let file, let data = try? Data(contentsOf: file),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    for (base, v) in obj {
      guard let d = v as? [String: Any], let at = DepthWire.integer(d["atMs"]),
            let body = try? JSONSerialization.data(withJSONObject: ["venues": d["venues"] ?? []]),
            let rows = OrderFlowCatalog.parse(body), !rows.isEmpty else { continue }
      entries[base] = (rows, at)
    }
  }

  private func save() {
    guard let file else { return }
    var obj: [String: Any] = [:]
    for (base, e) in entries { obj[base] = ["atMs": e.atMs, "venues": OrderFlowCatalog.encode(e.rows)] }
    guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
    try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: file, options: .atomic)
  }
}
