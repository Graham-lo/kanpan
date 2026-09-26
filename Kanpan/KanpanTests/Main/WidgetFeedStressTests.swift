import Foundation
import KanpanCore
import Observation
import Testing

@testable import Kanpan

/// 整机压测 2026-09-26 · 小组件那条线：只在真该写的时候写、只给真在画的那几只取走势。
@MainActor
@Suite("小组件数据源 · 整机压测")
struct WidgetFeedStressTests {
  struct FakePrefs { var skin = "moss"; var interval = "1h" }
  @MainActor @Observable final class FakeStore { var prefs = FakePrefs() }
  @MainActor final class Counter { var shapes = 0; var collects = 0 }
  final class Calls: @unchecked Sendable {
    private let lock = NSLock(); private var list: [String] = []
    func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return list }
  }

  /// 主线程上排着的 `Task` 跑完为止（不看墙钟：只让出执行权，条件到了就停）。
  func settle(_ done: () -> Bool) async {
    for _ in 0..<500 where !done() { await Task.yield() }
  }

  func tempDir() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("widget-feed-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("偏好里和小组件无关的字段变了（换周期、缩放、记最近看过）不写快照、不重载")
  func unrelatedPrefsChangeDoesNotFlush() async {
    let store = FakeStore(), count = Counter()
    let feed = WidgetFeed(directory: nil)
    feed.bind(collect: { _ in count.collects += 1; return nil },
              shape: { count.shapes += 1; return [store.prefs.skin] },
              fetchCloses: { _ in nil })
    #expect(count.shapes == 1 && count.collects == 0)
    store.prefs.interval = "4h"
    await settle { count.shapes >= 2 }
    #expect(count.shapes == 2, "观察没有重新挂上")
    #expect(count.collects == 0, "换个周期就整份折快照、落盘、叫扩展重排时间线")
    store.prefs.skin = "clay"
    await settle { count.shapes >= 3 }
    #expect(count.collects == 1, "皮肤真变了却没写")
  }

  @Test("只给中号小组件正在画、还在自选里的那几只取走势；一只都没摆就一发不取")
  func closesOnlyForDrawnSymbols() async throws {
    #expect(WidgetFeed.sparklineTargets(favorites: ["A", "B", "C"], wanted: []).isEmpty)
    #expect(WidgetFeed.sparklineTargets(favorites: ["A", "B", "C"], wanted: ["C", "Z"]) == ["C"])

    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    // 自选存的是规范写法：从 `SymbolPrefs` 手里拿回来再用。
    let prefs = SymbolPrefs(favorites: (0..<300).map { "S\($0)USDT" } + ["DRAWNUSDT"])
    let drawn = try #require(prefs.favorites.last)
    #expect(prefs.favorites.count == 301)
    WidgetSparklineWants.note(drawn, in: dir)
    let calls = Calls()
    let feed = WidgetFeed(directory: dir)
    feed.bind(collect: { closes in
      WidgetFeed.snapshot(symbols: prefs, quotes: [:], decimals: { _ in nil },
                          closes: closes, skin: Prefs.defaults.skin, appearance: .system, redUp: false,
                          refresh: nil, basis: .rolling24h)
    }, shape: { [] }, fetchCloses: { symbol in calls.add(symbol); return nil })
    feed.flush(reload: false)
    await settle { !calls.all.isEmpty }
    // 让可能的第二、第三发也有机会跑起来。
    for _ in 0..<50 { await Task.yield() }
    #expect(calls.all == [drawn], "给全部 \(prefs.favorites.count) 只自选都去取了走势：\(calls.all.prefix(5))…")
  }

  @Test("走势清单：记下的品种能读回来，两天没再画的过期")
  func wantsFileRoundTripAndExpiry() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    WidgetSparklineWants.note("BTC", in: dir, now: t0)
    WidgetSparklineWants.note("ETH", in: dir, now: t0.addingTimeInterval(3600))
    #expect(WidgetSparklineWants.symbols(in: dir, now: t0.addingTimeInterval(7200)) == ["BTC", "ETH"])
    let later = t0.addingTimeInterval(WidgetSparklineWants.lifetime + 60)
    #expect(WidgetSparklineWants.symbols(in: dir, now: later) == ["ETH"])
    #expect(WidgetSparklineWants.symbols(in: tempDir()).isEmpty)
  }

  @Test("账本只留还要画的那几只，在路上的那笔不动")
  func ledgerRetainDropsOthers() throws {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    var l = WidgetClosesLedger(every: 900, retry: 60, concurrency: 2)
    let aTicket = l.begin("A", now: t0)
    let a = try #require(aTicket)
    _ = l.finish(a, success: true, now: t0 + 1)
    _ = l.begin("B", now: t0)
    _ = l.begin("C", now: t0)
    l.retain(["A"])
    #expect(Set(l.dueAt.keys) == ["A", "B", "C"], "B、C 在路上，不能丢")
    let bTicket = try #require(l.inFlight["B"])
    _ = l.finish(bTicket, success: true, now: t0 + 2)
    l.retain(["A"])
    #expect(Set(l.dueAt.keys) == ["A", "C"])
    #expect(Set(l.acceptedAt.keys) == ["A"])
  }

  @Test("行情没带时刻：用收到它的那一刻；都不知道就写 0，不冒充「现在」")
  func missingTickerTimeFallsBackToReceivedAt() {
    func ticker(_ s: String) -> Ticker {
      Ticker(symbol: s, last: 100, changePercent: 1, high: 100, low: 100, quoteVolume: 1, open24h: 99, timeMs: nil)
    }
    let received = Date(timeIntervalSince1970: 1_800_000_000)
    let prefs = SymbolPrefs(favorites: ["AAAUSDT", "BBBUSDT"])
    let a = prefs.favorites[0], b = prefs.favorites[1]
    let snap = WidgetFeed.snapshot(symbols: prefs, quotes: [a: ticker(a), b: ticker(b)],
                                   decimals: { _ in nil }, closes: [:], skin: Prefs.defaults.skin, appearance: .system,
                                   redUp: false, refresh: nil, basis: .rolling24h,
                                   receivedAt: { $0 == a ? received : nil },
                                   now: received.addingTimeInterval(3600))
    #expect(snap.quotes[a]?.timeMs == 1_800_000_000_000)
    #expect(snap.quotes[b]?.timeMs == 0, "时刻不明的种子价被盖成「现在」，30 分钟淡化对它失效")
  }
}
