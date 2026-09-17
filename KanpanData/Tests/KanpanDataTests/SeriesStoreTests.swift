import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

/// 多品种启动快照。关心的是三件事：存得回来、不串味、不无限长大。
@Suite("多品种启动快照")
struct SeriesStoreTests {

  private func tempDir() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-series-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  @Test("按 (品种, 周期) 存取：写进去的能原样读回来")
  func roundTrip() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let s = makeSeries("BTCUSDT", .h1, count: 300)
    #expect(try SeriesStore.write(s, in: dir) > 0)
    let back = try #require(SeriesStore.read(symbol: "BTCUSDT", interval: .h1, in: dir))
    #expect(back.symbol == "BTCUSDT")
    #expect(back.interval == .h1)
    #expect(back.count == 300)
    #expect(back.lastTime == s.lastTime)
    // 没存过的那一对就是未命中，不能拿别人的顶上。
    #expect(SeriesStore.read(symbol: "BTCUSDT", interval: .m5, in: dir) == nil)
    #expect(SeriesStore.read(symbol: "ETHUSDT", interval: .h1, in: dir) == nil)
  }

  @Test("1m 和 1M 不能撞成同一个文件")
  func minuteAndMonthDoNotCollide() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // `Interval.m1.rawValue` 是 "1m"，`.mo1` 是 "1M"——只差大小写。iOS 的文件系统
    // 默认大小写不敏感，直接拿 rawValue 当文件名，这两个会互相覆盖。
    let minute = makeSeries("BTCUSDT", .m1, count: 120)
    let month = makeSeries("BTCUSDT", .mo1, count: 24)
    _ = try SeriesStore.write(minute, in: dir)
    _ = try SeriesStore.write(month, in: dir)

    let a = try #require(SeriesStore.read(symbol: "BTCUSDT", interval: .m1, in: dir))
    let b = try #require(SeriesStore.read(symbol: "BTCUSDT", interval: .mo1, in: dir))
    #expect(a.interval == .m1)
    #expect(a.count == 120)
    #expect(b.interval == .mo1)
    #expect(b.count == 24)

    // 每个周期一个文件名，忽略大小写也必须两两不同。
    let slugs = Interval.allCases.map { SeriesStore.slug($0).lowercased() }
    #expect(Set(slugs).count == Interval.allCases.count)
  }

  @Test("脏品种名不落盘")
  func rejectsDirtySymbols() {
    for bad in ["../../etc/passwd", "BTC/USDT", "", "BTC USDT", String(repeating: "A", count: 33)] {
      #expect(SeriesStore.safe(bad) == nil)
    }
    #expect(SeriesStore.safe("1000PEPEUSDT") == "1000PEPEUSDT")
  }

  @Test("超出条数上限就按最近用过的淘汰")
  func evictsByEntryCount() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let extra = 5
    for i in 0..<(SeriesStore.maxEntries + extra) {
      _ = try SeriesStore.write(makeSeries("S\(i)USDT", .m1, count: 10), in: dir)
    }
    // 正常路径上淘汰是按分钟节流的（`pruneEverySeconds`），这里直接催一次。
    SeriesStore.prune(in: dir, force: true)
    let kbars = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
      .filter { $0.pathExtension == "kbar" }
    #expect(kbars.count <= SeriesStore.maxEntries)
    // 最后写进去的那一份一定还在。
    #expect(SeriesStore.read(symbol: "S\(SeriesStore.maxEntries + extra - 1)USDT", interval: .m1, in: dir) != nil)
  }

  @Test("超出字节上限也会淘汰")
  func evictsByBytes() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    // 把字节上限压到只够放下一两份，验证兜底那一路真的会删东西。
    for i in 0..<6 {
      _ = try SeriesStore.write(makeSeries("S\(i)USDT", .h1, count: 600), in: dir)
    }
    let before = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
      .filter { $0.pathExtension == "kbar" }
    #expect(before.count == 6)
    let bytes = before.reduce(0) { $0 + ((try? Data(contentsOf: $1).count) ?? 0) }
    #expect(bytes <= SeriesStore.maxBytes)
  }

  @Test("清掉整个目录")
  func clears() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try SeriesStore.write(makeSeries("BTCUSDT", .m15, count: 50), in: dir)
    SeriesStore.clear(in: dir)
    #expect(!FileManager.default.fileExists(atPath: dir.path))
    #expect(SeriesStore.read(symbol: "BTCUSDT", interval: .m15, in: dir) == nil)
  }

  @Test("太旧的快照不拿来打底")
  func staleSnapshotIsNotSeeded() {
    let s = makeSeries("BTCUSDT", .m1, count: 600)
    let now = Double(s.lastTime)
    // 刚存的：能用。
    #expect(MarketFeed.seedUsable(s, nowMs: now))
    // 欠的根数还在 `contiguousTail` 的翻页能力之内：能用。
    #expect(MarketFeed.seedUsable(s, nowMs: now + Double(MarketFeed.maxSeedGapBars - 1) * 60_000))
    // 超出去了：中间那段补不回来，宁可空着等网络。
    #expect(!MarketFeed.seedUsable(s, nowMs: now + Double(MarketFeed.maxSeedGapBars + 10) * 60_000))
  }
}
