import Foundation
import Observation
import Testing
import KanpanCore
import KanpanNetwork
@testable import Kanpan

/// 压测 M2 / L1：板块页的口径快照与品种列表的行，输入没变就不重算。
@MainActor @Suite struct SectorMemoTests {
  /// 代替行情源：一项会被算的时候读到，一项不会。
  @MainActor @Observable final class Source {
    var quotes: [String: SectorQuote] = [:]
    var unrelated = 0
  }

  private struct Key: Equatable { var market: SectorMarket; var window: SectorWindow }

  private func quote(_ base: String, _ pct: Double) -> SectorQuote {
    SectorQuote(base: base, pct: pct, quoteVolume: 1_000, price: 1)
  }

  @Test("同一份输入来回下钻三趟只算一次")
  func sameInputsComputeOnce() {
    let source = Source(); source.quotes = ["BTC": quote("BTC", 1)]
    let memo = SectorMemo<Key, Int>()
    let key = Key(market: .crypto, window: .today)
    // 首屏一次，之后三趟「下钻 → 返回」各让 body 重跑两次。
    for _ in 0..<7 { #expect(memo.value(for: key) { source.quotes.count } == 1) }
    #expect(memo.computations == 1)
  }

  @Test("算的时候没读到的状态变了不重算，读到的变了重算")
  func onlyReadStateInvalidates() {
    let source = Source(); source.quotes = ["BTC": quote("BTC", 1)]
    let memo = SectorMemo<Key, Int>()
    let key = Key(market: .crypto, window: .today)
    _ = memo.value(for: key) { source.quotes.count }
    source.unrelated += 1
    _ = memo.value(for: key) { source.quotes.count }
    #expect(memo.computations == 1)
    source.quotes["ETH"] = quote("ETH", 2)
    #expect(memo.value(for: key) { source.quotes.count } == 2)
    #expect(memo.computations == 2)
    // 再来一趟没变：仍是新那份。
    #expect(memo.value(for: key) { source.quotes.count } == 2)
    #expect(memo.computations == 2)
  }

  @Test("作废时拨一下，读它的视图会被叫回来")
  func invalidationNotifiesReaders() {
    let source = Source()
    let memo = SectorMemo<Key, Int>()
    let key = Key(market: .crypto, window: .today)
    final class Fired: @unchecked Sendable { var count = 0 }
    let fired = Fired()
    // 缓存命中那一趟，视图只读到 memo 自己；行情变了也得叫它。
    _ = memo.value(for: key) { source.quotes.count }
    withObservationTracking {
      _ = memo.value(for: key) { source.quotes.count }
    } onChange: { fired.count += 1 }
    #expect(memo.computations == 1)
    source.quotes["BTC"] = quote("BTC", 1)
    #expect(fired.count == 1)
  }

  @Test("钥匙换了（切市场、切今日 / 5 日）重算")
  func keyChangeRecomputes() {
    let source = Source()
    let memo = SectorMemo<Key, String>()
    _ = memo.value(for: Key(market: .crypto, window: .today)) { "c" + String(source.quotes.count) }
    #expect(memo.value(for: Key(market: .us, window: .today)) { "u" } == "u")
    #expect(memo.value(for: Key(market: .us, window: .d5)) { "u5" } == "u5")
    #expect(memo.computations == 3)
  }

  @Test("上一趟留下的回调晚到，不作废这一趟")
  func staleCallbackIsIgnored() {
    let source = Source()
    let memo = SectorMemo<Key, Int>()
    _ = memo.value(for: Key(market: .crypto, window: .today)) { source.quotes.count }
    // 换了钥匙重算，这一趟不读 quotes。
    _ = memo.value(for: Key(market: .us, window: .today)) { 7 }
    source.quotes["BTC"] = quote("BTC", 1) // 只挂在上一趟上
    #expect(memo.value(for: Key(market: .us, window: .today)) { 7 } == 7)
    #expect(memo.computations == 2)
  }

  @Test("真行情源：品种表换了，兜底桶那份快照作废")
  func catalogChangeInvalidatesSnapshot() {
    let feed = SectorFeed(route: RouteResolver(policy: .direct))
    feed.setCatalog([SymbolInfo(symbol: "ZZZAUSDT", base: "ZZZA", pricePrecision: 2, tickSize: 0.01)])
    let memo = SectorMemo<Key, [SectorFallbackBucket]>()
    let key = Key(market: .crypto, window: .today)
    _ = memo.value(for: key) { feed.fallbackBuckets(for: key.market) }
    for _ in 0..<3 { _ = memo.value(for: key) { feed.fallbackBuckets(for: key.market) } }
    #expect(memo.computations == 1)
    feed.setCatalog([SymbolInfo(symbol: "ZZZAUSDT", base: "ZZZA", pricePrecision: 2, tickSize: 0.01),
                     SymbolInfo(symbol: "ZZZBUSDT", base: "ZZZB", pricePrecision: 2, tickSize: 0.01)])
    _ = memo.value(for: key) { feed.fallbackBuckets(for: key.market) }
    #expect(memo.computations == 2)
  }

}
