import Foundation

/// 桌面小组件读的那份快照（P3.2）。
///
/// app 刷到行情就写一份到 App Group 容器里（`Kanpan/Kanpan/Widget/WidgetFeed.swift`），
/// 小组件扩展（`Kanpan/KanpanWidget/`）只读它，再在自己刷新的那一拍按需补一口新价。
/// 两边都只认这一个类型，字段一改两边一起编译不过，不会各读各的。
///
/// 快照本身（字段、「挑哪四行」「新价怎么折成涨跌幅」、补价的地址模板与解析）是纯逻辑，
/// 放在 Core 才能在 `make core-test` 里测。它落在哪、怎么读写（App Group 容器里的
/// 那个文件）是 app 与扩展共用的平台胶水，在 `Kanpan/KanpanShared/WidgetSnapshotFile.swift`
/// （审查 24：Core 不做文件 IO、不认 App Group）。
public struct WidgetSnapshot: Codable, Sendable, Equatable {
  /// 「全部」这一类没有真身（自选页上没有这颗 chip），小组件编辑里用这个 id 代它。
  public static let allGroupID = "all"
  public static let allGroupName = "全部"
  /// 小号一屏四行。
  public static let rowLimit = 4
  /// 中号折线：最近 24 根 1 小时收盘价，和 24 小时涨跌幅看的是同一段。
  public static let sparkBars = 24
  /// 中号折线最多多少个点。
  public static let sparkLimit = 48

  public struct Quote: Codable, Sendable, Equatable {
    public var symbol: String
    public var price: Double
    /// 百分数（1.23 = +1.23%），已经按用户选的涨跌幅口径折好。
    public var change: Double
    public var decimals: Int?
    /// 迷你折线用的收盘价，旧→新。
    public var closes: [Double]
    /// 交易所时刻（毫秒）。
    public var timeMs: Int64
    /// 涨跌幅口径的那口开盘价。小组件自己补到新价时拿它重算涨跌幅；
    /// 滚动 24 小时口径下这一格没用（交易所直接给百分比）。
    public var open: Double?
    /// 这一只的涨跌幅口径是不是滚动 24 小时。2026-09-28 起口径按品种类型定（加密滚动、
    /// 美股 / 贵金属 / 指数按 UTC 0 点），一张快照里两种都有；nil 是旧快照，照快照整体那一格。
    public var rolling: Bool?

    public init(symbol: String, price: Double, change: Double, decimals: Int?, closes: [Double] = [],
                timeMs: Int64, open: Double? = nil, rolling: Bool? = nil) {
      self.symbol = symbol; self.price = price; self.change = change; self.decimals = decimals
      self.closes = closes; self.timeMs = timeMs; self.open = open; self.rolling = rolling
    }

    public var base: String { Alert.base(of: symbol) }
    /// 价：品种小数位 + 千分位，和自选 / 搜索列表、顶栏一个写法（UI 审查 2026-09-24 P1a 定的）。
    public var priceLabel: String { AlertMessage.groupedPrice(price, decimals: decimals) }
    public var changeLabel: String {
      // 全 app 唯一那把涨跌幅写法（审查 U9）：负号 U+2212、平盘「+0.00%」；缺数和旁边的价一样写「--」。
      changePercentText(change, missing: "--")
    }
  }

  public struct Group: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var symbols: [String]
    public init(id: String, name: String, symbols: [String]) { self.id = id; self.name = name; self.symbols = symbols }
  }

  /// 一套皮肤落到小组件上要用的几支颜色（`#RRGGBB`）。涨跌色已经按用户选的涨跌配色（出厂绿涨红跌）对调好。
  public struct Colors: Codable, Sendable, Equatable {
    public var ground, ink, ink2, ink3, line, accent, up, down: String
    public init(ground: String, ink: String, ink2: String, ink3: String, line: String, accent: String,
                up: String, down: String) {
      self.ground = ground; self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
      self.line = line; self.accent = accent; self.up = up; self.down = down
    }
  }

  public enum Appearance: String, Codable, Sendable { case auto, light, dark }

  public var updatedAt: Int64
  /// 「全部」的顺序：置顶的在前，其余照自选表。
  public var favorites: [String]
  public var groups: [Group]
  public var quotes: [String: Quote]
  public var light: Colors
  public var dark: Colors
  public var appearance: Appearance
  /// 小组件自己补价怎么取：主机、路径、有没有网关信封——全由 app 按当前线路
  /// （`RouteResolver`）写进来，小组件不自己判断直连还是网关。nil 就不自己补价，只用快照。
  /// 旧快照里是 `fapiHost` / `hostMarket` 两栏（永远指向直连域名，网关线路下也照打直连），
  /// 解码时忽略它们、这一栏是 nil，下一次 app 写快照就补上。
  public var refresh: Refresh?
  /// 别的市场各自的补价方式（Coinbase 现货等），同样由 app 按线路写。`refresh` 只管默认那一家，
  /// 自选里另一家的品种从前在 app 不回前台时永远停在快照那口价上（深度审查 E-10）。旧快照没有这一格。
  public var venueRefresh: [Refresh]?
  /// 自选里**还没有报价**的那几只各自的涨跌幅口径（是不是滚动 24 小时）。有报价的那只口径在
  /// `Quote.rolling` 里；没报价的从前小组件根本不去补（`apply` 只改已有的那格），新加的自选要等
  /// app 回前台才有价。现在小组件补到价就新开一格，口径看这里（E-10）。
  public var unquotedRolling: [String: Bool]?
  /// 涨跌幅口径是不是滚动 24 小时——旧快照整张一个口径时的那一格；新快照每只自己带
  /// （`Quote.rolling`），这一格只给没带的那只兜底。
  public var rolling: Bool

  public init(updatedAt: Int64, favorites: [String], groups: [Group], quotes: [String: Quote],
              light: Colors, dark: Colors, appearance: Appearance, refresh: Refresh? = nil,
              venueRefresh: [Refresh]? = nil, unquotedRolling: [String: Bool]? = nil, rolling: Bool) {
    self.updatedAt = updatedAt; self.favorites = favorites; self.groups = groups; self.quotes = quotes
    self.light = light; self.dark = dark; self.appearance = appearance; self.refresh = refresh
    self.venueRefresh = venueRefresh; self.unquotedRolling = unquotedRolling
    self.rolling = rolling
  }

  /// 这只品种该照哪份补价方式去取：按它所在的市场（`InstrumentID.marketKey`）挑，
  /// 默认那一家在 `refresh`，别家在 `venueRefresh`。没有、或者一台主机都没给，就 nil（只用快照）。
  public func refreshPlan(for symbol: String) -> Refresh? {
    let market = InstrumentID(symbol).marketKey
    return ([refresh].compactMap { $0 } + (venueRefresh ?? [])).first { $0.market == market && !$0.hosts.isEmpty }
  }

  /// 这只的涨跌幅口径：报价里带的 → 没报价时 app 记下的 → 整张快照那一格。
  public func isRolling(_ symbol: String) -> Bool {
    quotes[symbol]?.rolling ?? unquotedRolling?[symbol] ?? rolling
  }

  /// 小组件自己补价的取数方式。
  ///
  /// 直连：`hosts` 是币安 REST 那一台，路径是 `/fapi/v1/...`，回的就是载荷本身。
  /// 网关：`hosts` 是主、备两台网关，路径是 `/market/v1/...&source=...`，载荷包在信封的
  /// `tickerField` / `closesField` 字段里。两条线路的载荷形状一样（币安 `ticker/24hr` 对象、
  /// `klines` 数组），所以同一家的解析只有一份。
  ///
  /// 载荷形状按交易所分（`format`）：币安形状之外还有 Coinbase 的（`products/{id}` 对象、
  /// `candles` 对象数组），网关对 Coinbase 是原样透传，两条线路仍是同一个形状。
  public struct Refresh: Codable, Sendable, Equatable {
    public enum Format: String, Codable, Sendable {
      /// `ticker/24hr` 对象（`lastPrice` / `priceChangePercent` / `closeTime`）+ `klines` 数组（第 5 列收盘）。
      case binance
      /// `products/{id}` 对象（`price` / `price_percentage_change_24h`）+ `{"candles":[{start, close…}]}`，新的在前。
      case coinbase
    }

    /// 能自己补价的市场（`InstrumentID.marketKey`）。别的市场的品种找别的那份。
    public var market: String
    /// 候选主机（可带端口），按顺序试，第一台回得上就用。
    public var hosts: [String]
    /// 单品种 24h 行情的「路径?查询」模板，`{symbol}` 是交易所裸代号。
    public var ticker: String
    /// 1 小时收盘价的「路径?查询」模板，`{symbol}`、`{limit}` 两个占位；按起止时刻取的
    /// 交易所（Coinbase）再用 `{start}` / `{end}`（秒，整点，两端都含 `limit` 根）。
    public var closes: String
    /// 网关信封里装载荷的字段；直连是 nil（回的就是载荷）。
    public var tickerField: String?
    public var closesField: String?
    /// 载荷形状。nil 是旧快照（那时只有币安一家），按币安解。
    public var format: Format?

    public init(market: String, hosts: [String], ticker: String, closes: String,
                tickerField: String? = nil, closesField: String? = nil, format: Format? = nil) {
      self.market = market; self.hosts = hosts; self.ticker = ticker; self.closes = closes
      self.tickerField = tickerField; self.closesField = closesField; self.format = format
    }

    public func tickerURL(host: String, symbol: String, now: Date = Date()) -> URL? {
      Self.url(host: host, template: ticker, symbol: symbol, limit: WidgetSnapshot.sparkBars, now: now)
    }

    public func closesURL(host: String, symbol: String, now: Date = Date()) -> URL? {
      Self.url(host: host, template: closes, symbol: symbol, limit: WidgetSnapshot.sparkBars, now: now)
    }

    static func url(host: String, template: String, symbol: String, limit: Int, now: Date) -> URL? {
      guard symbol.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
      // 最近 `limit` 根 1 小时：止于这一小时的开盘，起于往前数 `limit - 1` 根。
      let hour: Int64 = 3_600
      let end = Int64(now.timeIntervalSince1970) / hour * hour
      let start = end - Int64(max(1, limit) - 1) * hour
      let filled = template.replacingOccurrences(of: "{symbol}", with: symbol)
        .replacingOccurrences(of: "{limit}", with: String(limit))
        .replacingOccurrences(of: "{start}", with: String(start))
        .replacingOccurrences(of: "{end}", with: String(end))
      return URL(string: "https://" + host + filled)
    }

    /// 一口 24h 行情：`(最新价, 滚动涨跌幅, 时间)`。取不出价就 nil。
    public func parseTicker(_ data: Data) -> (price: Double, change: Double?, timeMs: Int64?)? {
      guard let root = try? JSONSerialization.jsonObject(with: data),
            let object = Self.unwrap(root, field: tickerField) as? [String: Any] else { return nil }
      switch format ?? .binance {
      case .binance:
        guard let price = Self.number(object["lastPrice"]) else { return nil }
        let time = Self.number(object["closeTime"]).map { Int64($0) }
        return (price, Self.number(object["priceChangePercent"]), time)
      case .coinbase:
        // Coinbase 的品种对象不带时刻，由调用方记收到的那一刻。
        guard let price = Self.number(object["price"]) else { return nil }
        return (price, Self.number(object["price_percentage_change_24h"]), nil)
      }
    }

    /// 一段 1 小时收盘价，旧→新。不足两根就 nil。
    public func parseCloses(_ data: Data) -> [Double]? {
      guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
      let closes: [Double]
      switch format ?? .binance {
      case .binance:
        guard let rows = Self.unwrap(root, field: closesField) as? [[Any]] else { return nil }
        closes = rows.compactMap { row in row.count > 4 ? Self.number(row[4]) : nil }
      case .coinbase:
        guard let body = Self.unwrap(root, field: closesField) as? [String: Any],
              let rows = body["candles"] as? [[String: Any]] else { return nil }
        // 新的在前，按开盘时刻排回旧→新。
        closes = rows.compactMap { row -> (Double, Double)? in
          guard let start = Self.number(row["start"]), let close = Self.number(row["close"]) else { return nil }
          return (start, close)
        }.sorted { $0.0 < $1.0 }.map(\.1)
      }
      return closes.count >= 2 ? closes : nil
    }

    private static func unwrap(_ root: Any, field: String?) -> Any? {
      guard let field else { return root }
      return (root as? [String: Any])?[field]
    }

    private static func number(_ value: Any?) -> Double? {
      if let text = value as? String { return Double(text) }
      if let number = value as? NSNumber { return number.doubleValue }
      return nil
    }
  }

  // MARK: 挑行

  /// 某一类里的品种，顺序同「全部」。`nil`、`all` 或者找不到的类（被删了）都当「全部」。
  public func symbols(group id: String?) -> [String] {
    guard let id, id != Self.allGroupID, let group = groups.first(where: { $0.id == id }) else { return favorites }
    let members = Set(group.symbols)
    return favorites.filter { members.contains($0) }
  }

  /// 小号那四行。报价簿里还没有价的品种照样占一行（价写「--」），不跳过——
  /// 跳过的话用户看到的四只会和自选页前四只对不上。
  public func rows(group id: String?, limit: Int = rowLimit) -> [Quote] {
    symbols(group: id).prefix(limit).map { quotes[$0] ?? Quote(symbol: $0, price: .nan, change: .nan, decimals: nil, timeMs: 0) }
  }

  /// 中号那一只：选过的就用它；没选、或者它已经不在自选里，用「全部」第一只。
  public func focus(symbol: String?) -> Quote? {
    let pick = symbol.flatMap { s in favorites.contains(s) || quotes[s] != nil ? s : nil } ?? favorites.first
    guard let pick else { return nil }
    return quotes[pick] ?? Quote(symbol: pick, price: .nan, change: .nan, decimals: nil, timeMs: 0)
  }

  public func colors(systemDark: Bool) -> Colors {
    switch appearance {
    case .light: light
    case .dark: dark
    case .auto: systemDark ? dark : light
    }
  }

  // MARK: 小组件自己补的价

  /// 小组件刷新时自己从交易所取到的一口价。只收比快照新的那口；涨跌幅：滚动口径用
  /// 交易所给的百分比，按日口径拿快照里那口开盘价重算——只在新价与快照那口价同一个
  /// UTC 日（日线切换点是上海 8 点）时才算；跨了日（或快照那口时刻不明）开盘价与旧百分比
  /// 都是昨天的，涨跌幅写「--」并清掉开盘价，等 app 回前台重写快照。
  ///
  /// 快照里还没有这只的报价（新加的自选，app 还没来得及刷到）就新开一格：滚动口径照收
  /// 交易所的百分比；按日口径手上没有那口开盘价，涨跌幅写「--」而不是拿滚动的数冒充（E-10）。
  public mutating func apply(symbol: String, price: Double, rollingChange: Double?, timeMs: Int64,
                             closes: [Double]? = nil) {
    guard price.isFinite, price > 0 else { return }
    guard var quote = quotes[symbol] else {
      let rolling = isRolling(symbol)
      let change = rolling ? rollingChange.flatMap { $0.isFinite ? $0 : nil } ?? .nan : .nan
      let spark = closes.map { $0.count >= 2 ? Array($0.suffix(Self.sparkLimit)) : [] } ?? []
      quotes[symbol] = Quote(symbol: symbol, price: price, change: change, decimals: nil,
                             closes: spark, timeMs: timeMs, open: nil, rolling: rolling)
      return
    }
    guard timeMs >= quote.timeMs else { return }
    let sameDay = quote.timeMs > 0 && Self.utcDay(quote.timeMs) == Self.utcDay(timeMs)
    quote.price = price
    quote.timeMs = timeMs
    if quote.rolling ?? rolling {
      if let rollingChange, rollingChange.isFinite { quote.change = rollingChange }
    } else if !sameDay {
      // 跨过 UTC 0 点（上海 8 点，日线切换点）：快照里那口开盘价是昨天的，拿它算出来的是
      // 「昨天以来」的涨跌；旧百分比也是昨天的数。两样都不能当今天的显示——写「--」，
      // 并且把开盘价一起清掉，不然下一拍时刻已是今天、日界比对通过，又拿昨天的价重算。
      quote.open = nil
      quote.change = .nan
    } else if let open = quote.open, open > 0 {
      quote.change = (price / open - 1) * 100
    }
    if let closes, closes.count >= 2 { quote.closes = Array(closes.suffix(Self.sparkLimit)) }
    quotes[symbol] = quote
  }

  /// 毫秒时刻所在的 UTC 日序号（日线切换点：UTC 0 点 = 上海 8 点）。
  static func utcDay(_ ms: Int64) -> Int64 {
    ms >= 0 ? ms / 86_400_000 : (ms + 1) / 86_400_000 - 1
  }

  // MARK: 折线

  /// 折线在单位方框里的点（x 0…1 从左到右，y 0…1 从上到下）。少于两个点返回空。
  public static func sparkline(_ closes: [Double]) -> [(x: Double, y: Double)] {
    let values = closes.filter(\.isFinite)
    guard values.count >= 2, let lo = values.min(), let hi = values.max() else { return [] }
    let span = hi - lo
    let last = Double(values.count - 1)
    return values.enumerated().map { i, v in
      (x: Double(i) / last, y: span > 0 ? 1 - (v - lo) / span : 0.5)
    }
  }
}
