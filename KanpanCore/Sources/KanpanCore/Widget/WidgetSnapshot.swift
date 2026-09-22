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
  /// 小组件自己补价走的 REST 主机（和 app 当前直连那台一致）。
  public var fapiHost: String
  /// `fapiHost` 供的是哪个市场（`InstrumentID.marketKey`）。别的市场的品种小组件不自己补价，
  /// 只用 app 写进来的快照。旧快照没有这一栏（nil），那时自选里只有这一个市场。
  public var hostMarket: String?
  /// 涨跌幅口径是不是滚动 24 小时。
  public var rolling: Bool

  public init(updatedAt: Int64, favorites: [String], groups: [Group], quotes: [String: Quote],
              light: Colors, dark: Colors, appearance: Appearance, fapiHost: String, hostMarket: String? = nil, rolling: Bool) {
    self.updatedAt = updatedAt; self.favorites = favorites; self.groups = groups; self.quotes = quotes
    self.light = light; self.dark = dark; self.appearance = appearance; self.fapiHost = fapiHost
    self.hostMarket = hostMarket
    self.rolling = rolling
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
