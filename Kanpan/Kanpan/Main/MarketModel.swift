import Foundation
import KanpanCore
import KanpanData
import Observation

/// 主界面的数据源：握着 `MarketFeed`，把它吐的事件收成一份可画的快照。
///
/// 为什么中间要有这一层——`MarketFeed` 是 actor，事件在它自己的执行器上来；
/// SwiftUI 要的是 `@MainActor` 上的值。这层就是那道闸，顺便把只有界面在意的规则
/// （换周期时旧图先留着别闪白）收在一处。
@MainActor
@Observable
final class MarketModel {
  private(set) var series: BarSeries?
  private(set) var ticker: Ticker?
  private(set) var info: SymbolInfo
  private(set) var status: FeedStatus = .offline
  /// 换品种/周期还没拿到新数据的这段空档。图上用它压暗旧图（§10.4）。
  private(set) var switching = false

  private(set) var symbol: String
  private(set) var interval: Interval

  private let feed: MarketFeed
  nonisolated private let catalog: SymbolCatalog
  private var pump: Task<Void, Never>?
  /// 补历史一次只放一发在路上，别一路拖着就连喊十几次。
  private var loading = false

  init(symbol: String = "BTCUSDT", interval: Interval = .h1) {
    self.symbol = symbol
    self.interval = interval
    self.info = MarketModel.placeholder(symbol)
    let rest = BinanceREST()
    self.feed = MarketFeed(rest: rest, ws: BinanceWS())
    self.catalog = SymbolCatalog(rest: rest)
  }

  /// `exchangeInfo` 回来之前先顶上。冷启动第一帧不该等网络。
  private static func placeholder(_ symbol: String) -> SymbolInfo {
    let quote = ["USDT", "USDC", "BUSD"].first { symbol.hasSuffix($0) } ?? "USDT"
    return SymbolInfo(
      symbol: symbol, base: String(symbol.dropLast(quote.count)), quote: quote,
      pricePrecision: 2, tickSize: 0.01)
  }

  // ---------------------------------------------------------------- 生命周期

  func start(snapshot: Bool) {
    guard pump == nil else { return }
    let sym = symbol, iv = interval
    pump = Task { [feed] in
      let stream = await feed.events()
      await feed.setSnapshotEnabled(snapshot)
      await feed.start(symbol: sym, interval: iv)
      for await e in stream {
        if Task.isCancelled { break }
        await MainActor.run { self.apply(e) }
      }
    }
    Task { await refreshInfo() }
  }

  func stop() {
    pump?.cancel()
    pump = nil
    Task { [feed] in await feed.stop() }
  }

  func enterBackground() { Task { [feed] in await feed.enterBackground() } }
  func enterForeground() { Task { [feed] in await feed.enterForeground() } }
  func memoryWarning() { Task { [feed] in await feed.memoryWarning() } }
  func setSnapshotEnabled(_ on: Bool) { Task { [feed] in await feed.setSnapshotEnabled(on) } }

  // ---------------------------------------------------------------- 事件

  private func apply(_ e: FeedEvent) {
    switch e {
    case .series(let s):
      guard s.symbol == symbol, s.interval == interval else { return }
      series = s
      switching = false
    case .lastBar(let b):
      _ = series?.upsert(b)
    case .prepend:
      // `.prepend` 不带新序列，得自己去取。视野是绝对时间窗，补在左边天然不跳。
      Task { [feed] in
        let s = await feed.currentSeries
        await MainActor.run {
          if s.symbol == self.symbol, s.interval == self.interval { self.series = s }
        }
      }
    case .ticker(let t):
      guard t.symbol.uppercased() == symbol.uppercased() else { return }
      ticker = t
    case .oi:
      break                                   // 副图 OI 由指标层自己取
    case .status(let s):
      status = s
    }
  }

  // ---------------------------------------------------------------- 切换

  func switchTo(symbol newSymbol: String? = nil, interval newInterval: Interval? = nil) {
    let sym = (newSymbol ?? symbol).uppercased()
    let iv = newInterval ?? interval
    guard sym != symbol || iv != interval else { return }
    let cold = sym != symbol
    symbol = sym
    interval = iv
    switching = true
    if cold {
      ticker = nil
      info = MarketModel.placeholder(sym)
    }
    Task { [feed] in
      await feed.switchTo(symbol: sym, interval: iv, coldStart: cold)
      if cold { await refreshInfo() }
    }
  }

  /// 视野推到头部 200 根以内时叫（G9）。
  func loadMore() {
    guard !loading, series != nil else { return }
    loading = true
    Task { [feed] in
      await feed.loadMore()
      await MainActor.run { self.loading = false }
    }
  }

  /// 品种页要的品种表。`@Sendable` 是因为品种页把它当闭包存着，
  /// 跨隔离域传——所以捞的是 actor（`SymbolCatalog`），不是 `self`。
  nonisolated var catalogLoader: @Sendable () async -> [SymbolInfo] {
    let c = catalog
    return { await c.all() }
  }

  private func refreshInfo() async {
    let want = symbol
    guard let found = await catalog.find(want) else { return }
    if want == symbol { info = found }
  }
}
