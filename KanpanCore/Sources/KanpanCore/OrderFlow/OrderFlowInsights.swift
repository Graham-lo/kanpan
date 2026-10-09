import Foundation

/// Server aggregates of actual large executions. Prices are per base asset; never candle typical prices.
public struct OrderFlowInsightsPage: Sendable, Equatable, Decodable {
  public struct Source: Sendable, Equatable, Decodable {
    public var venueID: String
    public var exchange: String
    public var product: OrderFlowProduct
    public var buyUsd: Double
    public var sellUsd: Double
    public var total: Double { buyUsd + sellUsd }
  }
  public struct Window: Sendable, Equatable, Decodable {
    public var minutes: Int
    public var sources: [Source]
  }
  public struct Zone: Sendable, Equatable, Decodable, Identifiable {
    public var venueID: String
    public var exchange: String
    public var product: OrderFlowProduct
    public var low: Double
    public var high: Double
    public var buyUsd: Double
    public var sellUsd: Double
    public var recentBuyUsd: Double
    public var recentSellUsd: Double
    public var firstMs: Int64
    public var lastMs: Int64
    public var total: Double { buyUsd + sellUsd }
    public var recentTotal: Double { recentBuyUsd + recentSellUsd }
    public var id: String { "\(venueID):\(low):\(high)" }
  }
  public var base: String
  public var generatedAtMs: Int64
  public var dayStartMs: Int64
  public var tracked: Bool
  public var coverageSinceMs: Int64?
  public var lastTradeMs: Int64?
  public var bigUsd: Double?
  public var windows: [Window]
  public var zones: [Zone]

  /// Invalid amounts or timestamps must not become apparently valid zero observations.
  public var isValid: Bool {
    func amount(_ x: Double) -> Bool { x.isFinite && x >= 0 }
    guard generatedAtMs > 0, generatedAtMs < Int64.max - 86_400_000, dayStartMs >= 0, dayStartMs <= generatedAtMs, dayStartMs == BigTradeDigest.dayStart8(generatedAtMs),
          coverageSinceMs.map({ $0 >= 0 && $0 <= generatedAtMs }) ?? true,
          lastTradeMs.map({ $0 >= 0 && $0 <= generatedAtMs + 60_000 }) ?? true,
          bigUsd.map({ $0.isFinite && $0 > 0 }) ?? true else { return false }
    return windows.allSatisfy { w in
      [5, 15, 60].contains(w.minutes) && w.sources.allSatisfy {
        !$0.venueID.isEmpty && amount($0.buyUsd) && amount($0.sellUsd) && $0.total.isFinite
      }
    } && zones.allSatisfy {
      !$0.venueID.isEmpty && $0.low.isFinite && $0.low > 0 && $0.high.isFinite && $0.high >= $0.low
        && [$0.buyUsd, $0.sellUsd, $0.recentBuyUsd, $0.recentSellUsd].allSatisfy(amount)
        && $0.total.isFinite && $0.firstMs >= dayStartMs && $0.lastMs >= $0.firstMs
        && $0.lastMs <= generatedAtMs + 60_000
    }
  }
}

/// Evidence only. No forecast, cross-venue execution assumptions, or liquidation/trade double counting.
public enum OrderFlowInsightDigest {
  public static let directionalShare = 0.60
  public static let priceMovePercent = 0.05

  public static func isPrimary(venueID: String, product: OrderFlowProduct, instrument: InstrumentID) -> Bool {
    let parts = venueID.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count == 3, parts[0] == instrument.venue, parts[1] == product.rawValue,
          product == (instrument.market == "spot" ? .spot : .usdtPerp) else { return false }
    func normalized(_ s: String) -> String {
      var v = s.uppercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
      for suffix in ["SWAP", "PERP"] where v.hasSuffix(suffix) { v = String(v.dropLast(suffix.count)) }
      return v
    }
    return normalized(parts[2]) == normalized(instrument.symbol)
  }

  public static func currentOrders(_ snapshot: OrderFlowSnapshot?, symbol: String, nowMs: Int64) -> [BigOrder] {
    guard let snapshot, InstrumentID.canonical(snapshot.symbol) == InstrumentID.canonical(symbol),
          snapshot.phase == .ready, snapshot.asOfMs <= nowMs + 60_000,
          nowMs - snapshot.asOfMs <= 30_000 else { return [] }
    return snapshot.orders.filter { order in
      snapshot.venues.contains { $0.ready && $0.label == order.exchange && $0.product == order.product
        && order.venueID.hasSuffix(":" + $0.instrument) }
    }
  }

  public struct Wall: Sendable, Equatable, Identifiable {
    public var order: BigOrder
    public var distancePercent: Double
    public var durationMs: Int64
    public var id: String { order.id }
  }

  /// Exact chart instrument only. Books which have lost readiness cannot claim current liquidity.
  public static func nearestWalls(_ orders: [BigOrder], instrument: InstrumentID, price: Double,
                                  nowMs: Int64) -> (ask: Wall?, bid: Wall?) {
    guard price.isFinite, price > 0 else { return (nil, nil) }
    let live = orders.filter { $0.isLive && $0.price.isFinite && $0.price > 0 && $0.notional.isFinite
      && $0.notional > 0 && isPrimary(venueID: $0.venueID, product: $0.product, instrument: instrument) }
    func wall(_ order: BigOrder?) -> Wall? {
      order.map { Wall(order: $0, distancePercent: ($0.price / price - 1) * 100,
                       durationMs: max(0, nowMs - $0.firstSeenMs)) }
    }
    return (wall(live.filter { $0.side == .ask && $0.price >= price }.min { $0.price < $1.price }),
            wall(live.filter { $0.side == .bid && $0.price <= price }.max { $0.price < $1.price }))
  }

  public struct Reaction: Sendable, Equatable {
    public var fromMs: Int64
    public var toMs: Int64
    public var percent: Double
  }

  /// Requires continuous, completed one-minute bars through the latest completed minute.
  public static func reaction(bars: [Bar], fromMs: Int64, toMs: Int64) -> Reaction? {
    let from = ((fromMs + 59_999) / 60_000) * 60_000
    let end = (toMs / 60_000) * 60_000
    guard end - from >= 120_000 else { return nil }
    let rows = bars.filter { $0.openTime >= from && $0.openTime < end && $0.isValidMarketBar && $0.open > 0 }
      .sorted { $0.openTime < $1.openTime }
    guard let first = rows.first, let last = rows.last,
          first.openTime == from, last.openTime + 60_000 == end,
          rows.count == Int((end - from) / 60_000),
          zip(rows, rows.dropFirst()).allSatisfy({ $1.openTime - $0.openTime == 60_000 }) else { return nil }
    let percent = (last.close / first.open - 1) * 100
    guard percent.isFinite else { return nil }
    return Reaction(fromMs: from, toMs: end, percent: percent)
  }

  public enum Observation: Sendable, Equatable { case buyAdvance, sellAdvance, buyNoAdvance, sellNoAdvance, buyAgainst, sellAgainst, balanced, insufficient }

  public static func observation(buy: Double, sell: Double, reaction: Reaction?, covered: Bool) -> Observation {
    let total = buy + sell
    guard covered, buy.isFinite, sell.isFinite, buy >= 0, sell >= 0, total.isFinite, total > 0,
          let reaction else { return .insufficient }
    if buy / total >= directionalShare {
      if reaction.percent >= priceMovePercent { return .buyAdvance }
      if reaction.percent <= -priceMovePercent { return .buyAgainst }
      return .buyNoAdvance
    }
    if sell / total >= directionalShare {
      if reaction.percent <= -priceMovePercent { return .sellAdvance }
      if reaction.percent >= priceMovePercent { return .sellAgainst }
      return .sellNoAdvance
    }
    return .balanced
  }

  /// Keep original source and range identity. Different exchanges are never fused into a wall.
  public static func rankedZones(_ page: OrderFlowInsightsPage, chartScale: Double, limit: Int = 3) -> [OrderFlowInsightsPage.Zone] {
    guard chartScale.isFinite, chartScale > 0, page.isValid else { return [] }
    return page.zones.filter { $0.total > 0 }.sorted {
      $0.total == $1.total ? $0.lastMs > $1.lastMs : $0.total > $1.total
    }.prefix(max(0, limit)).compactMap {
      var zone = $0; zone.low *= chartScale; zone.high *= chartScale
      return zone.low.isFinite && zone.high.isFinite ? zone : nil
    }
  }

  /// Include lost as unknown; never translate a disconnect into cancellation.
  public static func recentEvents(_ orders: [BigOrder], nowMs: Int64, limit: Int = 4) -> [BigOrder] {
    orders.filter { o in
      let eventTime = o.endMs ?? o.firstSeenMs
      return !o.isLive && eventTime <= nowMs && eventTime >= nowMs - 15 * 60_000 && o.price.isFinite && o.price > 0
    }.sorted { ($0.endMs ?? $0.firstSeenMs) > ($1.endMs ?? $1.firstSeenMs) }.prefix(max(0, limit)).map { $0 }
  }
}
