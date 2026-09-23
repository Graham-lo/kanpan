import Foundation

/// One quote per symbol. REST and WS share the exchange's snapshot clock.
/// Equal revisions are idempotent; network arrival order is never a price clock.
public enum LatestQuote {
  public static func accepts(_ next: Ticker, after current: Ticker?) -> Bool {
    guard next.last.isFinite, next.last > 0 else { return false }
    guard let current else { return true }
    guard InstrumentID.canonical(next.symbol) == InstrumentID.canonical(current.symbol) else { return false }
    if let a = next.lastTradeID, let b = current.lastTradeID, a < b { return false }
    switch (next.timeMs, current.timeMs) {
    case let (a?, b?):
      if a != b { return a > b }
      // Several trades can share a millisecond. A trade ID is the tie breaker.
      return (next.lastTradeID ?? -1) > (current.lastTradeID ?? -1)
    case (_?, nil): return true
    case (nil, _?): return false
    case (nil, nil): return next != current // Legacy fixtures; production decodes the clock.
    }
  }

  public static func sameDisplay(_ a: Ticker, _ b: Ticker) -> Bool {
    func equal(_ a: Double, _ b: Double) -> Bool { a == b || (a.isNaN && b.isNaN) }
    return a.symbol == b.symbol && equal(a.last, b.last) && equal(a.changePercent, b.changePercent)
      && equal(a.high, b.high) && equal(a.low, b.low) && equal(a.quoteVolume, b.quoteVolume)
      && a.priceChange == b.priceChange && a.markPrice == b.markPrice && a.open24h == b.open24h
  }

  public static func newest(_ a: Ticker?, _ b: Ticker?, symbol: String) -> Ticker? {
    let a = a.flatMap { InstrumentID.canonical($0.symbol) == InstrumentID.canonical(symbol) ? $0 : nil }
    let b = b.flatMap { InstrumentID.canonical($0.symbol) == InstrumentID.canonical(symbol) ? $0 : nil }
    guard let b else { return a }
    return accepts(b, after: a) ? b : a
  }
}

/// Identified last trade from a live WS frame, never a REST/cache candle close.
public struct TradeQuote: Sendable, Equatable {
  public var symbol: String
  public var price: Double
  public var timeMs: Int64
  public var tradeID: Int64
  public init(symbol: String, price: Double, timeMs: Int64, tradeID: Int64) {
    self.symbol = InstrumentID.canonical(symbol); self.price = price; self.timeMs = timeMs; self.tradeID = tradeID
  }
}

/// 24h 成交额（计价币）自己一条时钟。
///
/// 有的推送源的 24h 统计帧不带成交额（网关线路上 OKX 替身的推送就只有价、高低、开盘、
/// 基础币成交量），成交额只能从 REST 那份表里拿。整帧替换会把刚补上的成交额又冲成空，
/// 所以成交额按「带着它的那一帧」的交易所时间单独记：不带成交额的帧沿用已知值，
/// 带着的帧只要不比已知的旧就收下。换品种清空，从不跨品种、跨来源借。
public struct TurnoverCarry: Sendable, Equatable {
  public private(set) var symbol: String?
  public private(set) var value: Double?
  /// 带来这份成交额的那一帧的交易所时间。
  public private(set) var timeMs: Int64?
  public init() {}

  public mutating func reset() { self = TurnoverCarry() }

  /// 收下一帧里的成交额：没带的、比已知的旧的不收；换了品种就从头记。返回值表示手里的值变了。
  @discardableResult public mutating func note(_ next: Ticker) -> Bool {
    guard next.quoteVolume.isFinite, next.quoteVolume >= 0 else { return false }
    if let symbol, symbol != next.symbol { self = TurnoverCarry() }
    if value != nil, let known = timeMs {
      guard let time = next.timeMs, time >= known else { return false }
    }
    let changed = value != next.quoteVolume || timeMs != next.timeMs
    symbol = next.symbol; value = next.quoteVolume; timeMs = next.timeMs ?? timeMs
    return changed
  }

  /// 帧里缺成交额时用已知的那份垫上；帧里自己带着的一概不动。
  public func apply(_ ticker: Ticker) -> Ticker {
    guard !ticker.quoteVolume.isFinite, let value, symbol == ticker.symbol else { return ticker }
    var next = ticker
    next.quoteVolume = value
    return next
  }
}

/// Price and rolling statistics have independent exchange revisions. A delayed
/// ticker may fill statistics without replacing a newer trade already on screen.
public struct QuoteState: Sendable {
  private var statistics: Ticker?
  private var trade: TradeQuote?
  private var turnover = TurnoverCarry()
  public private(set) var value: Ticker?
  public init() {}

  /// 手里的成交额是哪一刻的（交易所时间）；`nil` 表示还没有成交额。
  public var turnoverTimeMs: Int64? { turnover.value == nil ? nil : (turnover.timeMs ?? 0) }
  public var hasTurnover: Bool { turnover.value != nil }

  @discardableResult public mutating func receive(_ next: TradeQuote) -> Bool {
    guard next.price.isFinite, next.price > 0, next.timeMs > 0, next.tradeID >= 0,
          value == nil || value?.symbol == next.symbol else { return false }
    if let trade { guard next.tradeID > trade.tradeID else { return false } }
    else if let current = value, let clock = current.timeMs, next.timeMs < clock { return false }
    trade = next
    rebuild()
    return true
  }

  @discardableResult public mutating func receive(_ next: Ticker) -> Bool {
    guard next.last.isFinite, next.last > 0,
          value == nil || value?.symbol == next.symbol else { return false }
    // 成交额单独过：整帧被判旧的 REST 回包，成交额可能仍比手里的新（推送帧不带它）。
    var accepted = turnover.note(next)
    if let time = next.timeMs, let id = next.lastTradeID {
      accepted = receive(TradeQuote(symbol: next.symbol, price: next.last, timeMs: time, tradeID: id))
    }
    if LatestQuote.accepts(next, after: statistics) {
      statistics = next; accepted = true
    }
    if accepted { rebuild() }
    return accepted
  }

  /// 只收一帧里的成交额，价和其余统计一概不碰。给「整帧来晚了、被会话版本挡掉」的
  /// REST 回包用：它带的成交额仍然是最新的那份。
  @discardableResult public mutating func receiveTurnover(_ next: Ticker) -> Bool {
    guard value == nil || value?.symbol == next.symbol, turnover.note(next) else { return false }
    if value != nil { rebuild() }
    return value != nil
  }

  private mutating func rebuild() {
    guard let symbol = trade?.symbol ?? statistics?.symbol else { return }
    var next = statistics ?? Ticker(symbol: symbol, last: .nan, changePercent: .nan,
      high: .nan, low: .nan, quoteVolume: .nan)
    if let trade {
      // 保留 ticker 的涨跌额；成交先到时只补这份统计之后的价差。
      if let change = statistics?.priceChange, let last = statistics?.last {
        next.priceChange = change + (trade.price - last)
      }
      next.last = trade.price
      next.timeMs = max(value?.timeMs ?? 0, max(trade.timeMs, statistics?.timeMs ?? 0))
      next.lastTradeID = trade.tradeID
      if let open = next.open24h, open.isFinite, open > 0 {
        next.changePercent = (trade.price - open) / open * 100
      } else if statistics?.lastTradeID != trade.tradeID { next.changePercent = .nan }
      if next.high.isFinite { next.high = max(next.high, trade.price) }
      if next.low.isFinite { next.low = min(next.low, trade.price) }
    }
    value = turnover.apply(next)
  }
}
