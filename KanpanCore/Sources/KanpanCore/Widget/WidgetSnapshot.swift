import Foundation

/// 桌面小组件读的那份快照（P3.2）。
///
/// app 刷到行情就写一份到 App Group 容器里（`Kanpan/Kanpan/Widget/WidgetFeed.swift`），
/// 小组件扩展（`Kanpan/KanpanWidget/`）只读它，再在自己刷新的那一拍按需补一口新价。
/// 两边都只认这一个类型，字段一改两边一起编译不过，不会各读各的。
///
/// 放在 Core：扩展进程只能链 Core（它不带 UIKit 以外的任何 app 模块），而这份东西
/// 的「挑哪四行」「新价怎么折成涨跌幅」都是纯逻辑，放这儿才能在 `make core-test` 里测。
public struct WidgetSnapshot: Codable, Sendable, Equatable {
  public static let appGroup = "group.com.mdd.kanpan"
  public static let fileName = "widget-snapshot.json"
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

    public init(symbol: String, price: Double, change: Double, decimals: Int?, closes: [Double] = [],
                timeMs: Int64, open: Double? = nil) {
      self.symbol = symbol; self.price = price; self.change = change; self.decimals = decimals
      self.closes = closes; self.timeMs = timeMs; self.open = open
    }

    public var base: String { Alert.base(of: symbol) }
    public var priceLabel: String { ReviewLabels.price(price, decimals: decimals) }
    public var changeLabel: String {
      guard change.isFinite else { return "--" }
      return (change > 0 ? "+" : "") + String(format: "%.2f%%", change)
    }
  }

  public struct Group: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var symbols: [String]
    public init(id: String, name: String, symbols: [String]) { self.id = id; self.name = name; self.symbols = symbols }
  }

  /// 一套皮肤落到小组件上要用的几支颜色（`#RRGGBB`）。涨跌色已经按「红涨绿跌」对调好。
  public struct Colors: Codable, Sendable, Equatable {
    public var ground, ink, ink2, ink3, line, accent, up, down: String
    public init(ground: String, ink: String, ink2: String, ink3: String, line: String, accent: String,
                up: String, down: String) {
      self.ground = ground; self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
      self.line = line; self.accent = accent; self.up = up; self.down = down
    }

    public init(seed: PaletteSeed, redUp: Bool) {
      let chart = Palette.chart(seed, redUp: redUp)
      self.init(ground: seed.app.value, ink: seed.ink.value, ink2: seed.ink2.value, ink3: seed.ink3.value,
                line: seed.line.value, accent: seed.accent.value, up: chart.up.value, down: chart.down.value)
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
  /// 涨跌幅口径是不是滚动 24 小时。
  public var rolling: Bool

  public init(updatedAt: Int64, favorites: [String], groups: [Group], quotes: [String: Quote],
              light: Colors, dark: Colors, appearance: Appearance, refresh: Refresh? = nil, rolling: Bool) {
    self.updatedAt = updatedAt; self.favorites = favorites; self.groups = groups; self.quotes = quotes
    self.light = light; self.dark = dark; self.appearance = appearance; self.refresh = refresh
    self.rolling = rolling
  }

  /// 小组件自己补价的取数方式。
  ///
  /// 直连：`hosts` 是币安 REST 那一台，路径是 `/fapi/v1/...`，回的就是载荷本身。
  /// 网关：`hosts` 是主、备两台网关，路径是 `/market/v1/...&source=...`，载荷包在信封的
  /// `tickerField` / `closesField` 字段里。两条线路的载荷形状一样（币安 `ticker/24hr` 对象、
  /// `klines` 数组），所以解析只有一份。
  public struct Refresh: Codable, Sendable, Equatable {
    /// 能自己补价的市场（`InstrumentID.marketKey`）。别的市场的品种只用快照。
    public var market: String
    /// 候选主机（可带端口），按顺序试，第一台回得上就用。
    public var hosts: [String]
    /// 单品种 24h 行情的「路径?查询」模板，`{symbol}` 是交易所裸代号。
    public var ticker: String
    /// 1 小时收盘价的「路径?查询」模板，`{symbol}`、`{limit}` 两个占位。
    public var closes: String
    /// 网关信封里装载荷的字段；直连是 nil（回的就是载荷）。
    public var tickerField: String?
    public var closesField: String?

    public init(market: String, hosts: [String], ticker: String, closes: String,
                tickerField: String? = nil, closesField: String? = nil) {
      self.market = market; self.hosts = hosts; self.ticker = ticker; self.closes = closes
      self.tickerField = tickerField; self.closesField = closesField
    }

    public func tickerURL(host: String, symbol: String) -> URL? {
      Self.url(host: host, template: ticker, symbol: symbol, limit: WidgetSnapshot.sparkBars)
    }

    public func closesURL(host: String, symbol: String) -> URL? {
      Self.url(host: host, template: closes, symbol: symbol, limit: WidgetSnapshot.sparkBars)
    }

    static func url(host: String, template: String, symbol: String, limit: Int) -> URL? {
      guard symbol.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
      let filled = template.replacingOccurrences(of: "{symbol}", with: symbol)
        .replacingOccurrences(of: "{limit}", with: String(limit))
      return URL(string: "https://" + host + filled)
    }

    /// 一口 24h 行情：`(最新价, 滚动涨跌幅, 时间)`。取不出价就 nil。
    public func parseTicker(_ data: Data) -> (price: Double, change: Double?, timeMs: Int64?)? {
      guard let root = try? JSONSerialization.jsonObject(with: data),
            let object = Self.unwrap(root, field: tickerField) as? [String: Any],
            let price = Self.number(object["lastPrice"]) else { return nil }
      let time = Self.number(object["closeTime"]).map { Int64($0) }
      return (price, Self.number(object["priceChangePercent"]), time)
    }

    /// 一段 1 小时收盘价（第 5 列）。不足两根就 nil。
    public func parseCloses(_ data: Data) -> [Double]? {
      guard let root = try? JSONSerialization.jsonObject(with: data),
            let rows = Self.unwrap(root, field: closesField) as? [[Any]] else { return nil }
      let closes = rows.compactMap { row in row.count > 4 ? Self.number(row[4]) : nil }
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
  /// 交易所给的百分比，按日口径拿快照里那口开盘价重算——开盘价跨了一天就不算
  /// （`boundary` 由调用方按口径算好），宁可沿用快照里的旧百分比也不给错的。
  public mutating func apply(symbol: String, price: Double, rollingChange: Double?, timeMs: Int64,
                             closes: [Double]? = nil) {
    guard price.isFinite, price > 0, var quote = quotes[symbol], timeMs >= quote.timeMs else { return }
    quote.price = price
    quote.timeMs = timeMs
    if rolling {
      if let rollingChange, rollingChange.isFinite { quote.change = rollingChange }
    } else if let open = quote.open, open > 0 {
      quote.change = (price / open - 1) * 100
    }
    if let closes, closes.count >= 2 { quote.closes = Array(closes.suffix(Self.sparkLimit)) }
    quotes[symbol] = quote
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

  // MARK: 读写

  public static func url(in container: URL) -> URL { container.appendingPathComponent(fileName) }

  public static func read(from url: URL) -> WidgetSnapshot? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }

  public func write(to url: URL) throws {
    let data = try JSONEncoder().encode(self)
    try data.write(to: url, options: .atomic)
  }
}
