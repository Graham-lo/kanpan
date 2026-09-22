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

/// Price and rolling statistics have independent exchange revisions. A delayed
/// ticker may fill statistics without replacing a newer trade already on screen.
public struct QuoteState: Sendable {
  private var statistics: Ticker?
  private var trade: TradeQuote?
  public private(set) var value: Ticker?
  public init() {}

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
    var accepted = false
    if let time = next.timeMs, let id = next.lastTradeID {
      accepted = receive(TradeQuote(symbol: next.symbol, price: next.last, timeMs: time, tradeID: id))
    }
    if LatestQuote.accepts(next, after: statistics) {
      statistics = next; accepted = true
    }
    if accepted { rebuild() }
    return accepted
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
    value = next
  }
}
