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
/// - **幅度按这只自己的波动自动定**（收设置项 E 组，2026-09-28 起不再让人填）：
///   取这只最近至多 1440 根相邻 1 分钟收盘价的对数收益 r（只算开盘时刻正好差 1 分钟的
///   两根，缺口两边不连），σ1 = 1.4826 × median(|r|)（MAD 稳健估计，不被几根插针带偏），
///   σ5 = √5 · σ1，幅度 = clamp(5 · σ5, 0.5%, 10%)；不满 30 个收益时用 1.5%（原出厂值）。
///   BTC 这种安静的大币落在 0.5% 附近，山寨币自动放宽——一个数对所有品种都合适是不可能的。
///   两端共用夹具 `Backend/kanpan-api/contract/watch-move-threshold.json`。
///
/// 前台（`WatchMoveMonitor`）与服务端（`Backend/kanpan-api/src/watch_move.rs`）按
/// 这同一段文字各实现一份，两边都拿 1 分钟 K 线的收盘价当参照。
public enum WatchMove {
  public static let barMs: Int64 = 60_000
  public static let windowMs: Int64 = 300_000
  /// 收益不够（不满 `minReturns` 个）时的幅度（百分数），即原来的出厂值。
  public static let fallbackThreshold = 1.5
  /// 自动幅度的上下限（百分数）。
  public static let thresholdRange: ClosedRange<Double> = 0.5...10
  /// 至少这么多个 1 分钟收益才信得过估计。
  public static let minReturns = 30
  /// 最多看最近这么多个 1 分钟收益（一天）。
  public static let maxReturns = 1440
  /// MAD → σ 的换算系数（正态下 σ = 1.4826 × MAD）。
  public static let madScale = 1.4826

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

  /// 自动幅度（百分数）：`returns` 是按时间先后排的 1 分钟对数收益，只看最后 `maxReturns` 个。
  /// 服务端 `watch_move::auto_threshold` 一字对一字。
  public static func autoThreshold(returns: [Double]) -> Double {
    let recent = returns.suffix(maxReturns).filter(\.isFinite).map(abs).sorted()
    guard recent.count >= minReturns else { return fallbackThreshold }
    let n = recent.count
    let median = n % 2 == 1 ? recent[n / 2] : (recent[n / 2 - 1] + recent[n / 2]) / 2
    let sigma5 = (5.0).squareRoot() * madScale * median
    let percent = 5 * sigma5 * 100
    guard percent.isFinite else { return fallbackThreshold }
    return min(max(percent, thresholdRange.lowerBound), thresholdRange.upperBound)
  }

  /// 通知标题：「BTC 五分钟涨 1.82%」。服务端 `watch_move::title` 一字不差。
  public static func title(for event: Event) -> String {
    let verb = event.direction == .up ? "涨" : "跌"
    return Alert.name(of: event.symbol) + " 五分钟" + verb + " " + String(format: "%.2f%%", abs(event.change) * 100)
  }

  /// 一只品种的 1 分钟收盘价（最近七根够用）与估幅度用的收益（最近 `maxReturns` 个）。
  struct Series: Sendable, Equatable {
    /// 开盘时刻 → 收盘价，只存已经收了的。
    var closes: [Int64: Double] = [:]
    var currentOpen: Int64?
    var currentClose: Double?
    /// 相邻两根收盘价的对数收益，按时间先后。断线只扔收盘价、不扔它（缺口两边本来就不连）。
    var returns: [Double] = []
    /// 按 `returns` 算好的幅度（百分数），收一根重算一次，不是每口价都排一遍序。
    var threshold = WatchMove.fallbackThreshold

    public init() {}

    /// 这一根收了。第一次收才记收益；前一分钟那一根也收着，才算一个收益。
    ///
    /// 清旧收盘价、裁收益都只在这儿做（一分钟一次），不在每一口价上做（深度审查 E-8）：
    /// `closes` 只在收根时才会长，留最近七根就够五分钟参照用；`returns` 攒到两倍上限
    /// 才一次裁回上限，`autoThreshold` 本来就只看最后 `maxReturns` 个，结论不变。
    mutating func commit(open: Int64, close: Double) {
      let fresh = closes[open] == nil
      closes[open] = close
      if closes.count > 8 { closes = closes.filter { $0.key >= open - 7 * WatchMove.barMs } }
      guard fresh, let previous = closes[open - WatchMove.barMs], previous > 0 else { return }
      returns.append(Foundation.log(close / previous))
      if returns.count >= 2 * WatchMove.maxReturns { returns.removeFirst(returns.count - WatchMove.maxReturns) }
      threshold = WatchMove.autoThreshold(returns: returns)
    }

    /// 断过线：收盘价与这一根作废，收益与幅度留着。
    mutating func forgetPrices() {
      closes.removeAll()
      currentOpen = nil
      currentClose = nil
    }

    /// 喂一口价。`closed == true` 表示这一根到这儿已经收了（服务端的 `k.x`）。
    /// 返回这一口的五分钟涨跌幅；参照那一根缺着就返回 nil。
    public mutating func observe(barOpen: Int64, price: Double, closed: Bool = false) -> Double? {
      guard price.isFinite, price > 0 else { return nil }
      if let open = currentOpen, barOpen < open { return nil }   // 乱序的旧帧一概不要
      if let open = currentOpen, let close = currentClose, barOpen > open {
        commit(open: open, close: close)   // 换根了 ⇒ 上一根收了
      }
      currentOpen = barOpen
      currentClose = price
      if closed { commit(open: barOpen, close: price) }
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
  ///
  /// 品种一律按规范键（`binance/usd_m/BTCUSDT`）记：裸代号、规范键、大写的规范键
  /// 进来都先过 `InstrumentID.canonical`，归到同一格。闸按（品种, 方向）成对记，
  /// 不再把两者拼成一个字符串——规范键里本身带 `/`，拼起来再按 `/` 拆会拆错。
  public struct Tracker: Sendable, Equatable {
    struct GateKey: Hashable, Sendable {
      var symbol: String
      var direction: Direction
    }

    var series: [String: Series] = [:]
    var gates: [GateKey: Gate] = [:]
    public init() {}

    /// 喂一口价。幅度按这只自己的波动自动定（`autoThreshold`），再乘 `sensitivity`
    /// （「按我的习惯自动调整」学到的倍数，0.5–2，出厂 1；只乘不改自动定出来的那个数）。
    public mutating func observe(symbol: String, barOpen: Int64, price: Double, closed: Bool = false,
                                 sensitivity: Double = 1) -> Event? {
      let key = InstrumentID.canonical(symbol)
      guard !key.isEmpty else { return nil }
      // 原地改：先拷出来再写回，会让收盘价表和收益数组每一口价都多拷一份（深度审查 E-8）。
      let change = series[key, default: Series()].observe(barOpen: barOpen, price: price, closed: closed)
      guard let change, let threshold = series[key]?.threshold else { return nil }
      let factor = sensitivity.isFinite ? min(max(sensitivity, 0.5), 2) : 1
      let limit = threshold * factor / 100
      let window = barOpen - barOpen % WatchMove.windowMs
      var fired: Event?
      for direction in Direction.allCases {
        let gateKey = GateKey(symbol: key, direction: direction)
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
    /// 留下的品种闸照旧——改自选不能让同一个窗口里再响一次。
    public mutating func keep(_ symbols: Set<String>) {
      let keys = Set(symbols.map(InstrumentID.canonical))
      series = series.filter { keys.contains($0.key) }
      gates = gates.filter { keys.contains($0.key.symbol) }
    }

    /// 断过（切后台）：收盘价全扔，闸留着——同一个窗口里回来不许再响一次；
    /// 估幅度的收益也留着（缺口两边不连，不会算出假收益），回来不用再等三十分钟。
    public mutating func forgetPrices() {
      for key in series.keys { series[key]?.forgetPrices() }
    }

    /// 这只现在的幅度（百分数）。没见过的品种是 `fallbackThreshold`。
    public func threshold(for symbol: String) -> Double {
      series[InstrumentID.canonical(symbol)]?.threshold ?? WatchMove.fallbackThreshold
    }

    public var symbols: Set<String> { Set(series.keys) }
  }
}
