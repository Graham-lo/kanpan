import Foundation

/// 自选五分钟波动提醒（P3.1）：自选里某只五分钟内涨或跌超过幅度，叫一声。
///
/// 只有一种判定，没有口径可选（`kanpan-sector-page-no-basis-picker`）：
///
/// - **五分钟涨跌幅** = 现价 ÷ 「五分钟前那一根 1 分钟 K 线的收盘价」− 1。
///   「五分钟前那一根」指开盘时刻 = 当前这一根的开盘时刻 − 5 分钟的那一根。
/// - **缺口不冒充零波动**：那一根没有（刚开始盯、断过线、那一分钟一口价都没有），
///   这一口就不判——既不响，也不把「已经回到阈值以内」记上。
/// - **去重**：同品种、同方向、同一个对齐的五分钟窗口（开盘时刻按 5 分钟取整）
///   只响一次；响过之后，幅度要先回到阈值以内（「退出阈值」）才重新上膛。
///
/// 前台（`WatchMoveMonitor`）与服务端（`Backend/kanpan-api/src/watch_move.rs`）按
/// 这同一段文字各实现一份，两边都拿 1 分钟 K 线的收盘价当参照。
public enum WatchMove {
  public static let barMs: Int64 = 60_000
  public static let windowMs: Int64 = 300_000
  /// 出厂幅度（百分数）。
  public static let defaultThreshold = 1.5
  /// 用户能填的范围（百分数）。服务端 `sync_validation.rs` 卡同一个区间。
  public static let thresholdRange: ClosedRange<Double> = 0.1...50

  public enum Direction: String, Sendable, CaseIterable { case up, down }

  public struct Event: Sendable, Equatable {
    public var symbol: String
    public var direction: Direction
    /// 小数（0.018 = 1.8%），带符号。
    public var change: Double
    public var price: Double
    /// 对齐的五分钟窗口起点（毫秒）。通知 id 用它去重。
    public var window: Int64
  }

  /// 把用户输入的幅度夹进合法区间；读不出来的退回出厂值。
  public static func clampThreshold(_ value: Double) -> Double {
    guard value.isFinite else { return defaultThreshold }
    return min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
  }

  /// 通知标题：「BTC 五分钟涨 1.82%」。服务端 `watch_move::title` 一字不差。
  public static func title(for event: Event) -> String {
    let verb = event.direction == .up ? "涨" : "跌"
    return Alert.base(of: event.symbol) + " 五分钟" + verb + " " + String(format: "%.2f%%", abs(event.change) * 100)
  }

  /// 一只品种的 1 分钟收盘价（最近七根够用）。
  public struct Series: Sendable, Equatable {
    /// 开盘时刻 → 收盘价，只存已经收了的。
    var closes: [Int64: Double] = [:]
    var currentOpen: Int64?
    var currentClose: Double?

    public init() {}

    /// 喂一口价。`closed == true` 表示这一根到这儿已经收了（服务端的 `k.x`）。
    /// 返回这一口的五分钟涨跌幅；参照那一根缺着就返回 nil。
    public mutating func observe(barOpen: Int64, price: Double, closed: Bool = false) -> Double? {
      guard price.isFinite, price > 0 else { return nil }
      if let open = currentOpen, barOpen < open { return nil }   // 乱序的旧帧一概不要
      if let open = currentOpen, let close = currentClose, barOpen > open {
        closes[open] = close   // 换根了 ⇒ 上一根收了
      }
      currentOpen = barOpen
      currentClose = price
      if closed { closes[barOpen] = price }
      closes = closes.filter { $0.key >= barOpen - 7 * WatchMove.barMs }
      guard let reference = closes[barOpen - WatchMove.windowMs], reference > 0 else { return nil }
      return price / reference - 1
    }
  }

  /// 一只品种一个方向上的闸：同窗口只响一次、退出阈值才重新上膛。
  public struct Gate: Sendable, Equatable {
    var armed = true
    var lastWindow: Int64?
    public init() {}

    /// `signed` 是这个方向上的幅度（涨的方向就是涨跌幅本身，跌的方向取反），小数。
    public mutating func pass(signed: Double, threshold: Double, window: Int64) -> Bool {
      if signed < threshold {
        armed = true
        return false
      }
      guard armed, lastWindow != window else { return false }
      armed = false
      lastWindow = window
      return true
    }
  }

  /// 一个人的全部状态：各品种的收盘价 + 各品种各方向的闸。
  public struct Tracker: Sendable, Equatable {
    var series: [String: Series] = [:]
    var gates: [String: Gate] = [:]
    public init() {}

    /// 喂一口价。`threshold` 是百分数（1.5 = 1.5%）。
    public mutating func observe(symbol: String, barOpen: Int64, price: Double, closed: Bool = false,
                                 threshold: Double) -> Event? {
      let key = symbol.uppercased()
      var s = series[key] ?? Series()
      let change = s.observe(barOpen: barOpen, price: price, closed: closed)
      series[key] = s
      guard let change else { return nil }
      let limit = WatchMove.clampThreshold(threshold) / 100
      let window = barOpen - barOpen % WatchMove.windowMs
      var fired: Event?
      for direction in Direction.allCases {
        let gateKey = key + "|" + direction.rawValue
        var gate = gates[gateKey] ?? Gate()
        let signed = direction == .up ? change : -change
        if gate.pass(signed: signed, threshold: limit, window: window), fired == nil {
          fired = Event(symbol: key, direction: direction, change: change, price: price, window: window)
        }
        gates[gateKey] = gate
      }
      return fired
    }

    /// 只留这几只（自选改了）。拿掉的品种连同它的闸一起忘掉：以后再加回来，从缺口重新开始。
    public mutating func keep(_ symbols: Set<String>) {
      // 品种键本身带「/」（`BINANCE/USD_M/BTCUSDT`），闸的键用「|」接方向，拆的时候按最后一个「|」。
      // 原来按第一个「/」拆，拆出来的是交易所名，自选一改所有闸全被清掉，同一个窗口能再响一次。
      let keys = Set(symbols.map { $0.uppercased() })
      series = series.filter { keys.contains($0.key) }
      gates = gates.filter { keys.contains(String($0.key[..<($0.key.lastIndex(of: "|") ?? $0.key.endIndex)])) }
    }

    /// 断过（切后台、关掉开关）：收盘价全扔，闸留着——同一个窗口里回来不许再响一次。
    public mutating func forgetPrices() { series.removeAll() }

    public var symbols: Set<String> { Set(series.keys) }
  }
}
