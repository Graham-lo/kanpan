import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
import KanpanCore

@Suite("启动快照与内存缓存")
struct StoreTests {

  private func tempPaths() -> Paths {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-test-\(UUID().uuidString)")
    let p = Paths(root: dir)
    try? p.ensureRoot()
    return p
  }

  // ---------------------------------------------------------------- A2.4

  @Test("快照文件：≤3000 根、≤300KB，读回逐字节一致")
  func snapshotRoundTrip() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    // 故意多给一截，验证写盘时确实截到 `maxBars`。
    let s = makeSeries("BTCUSDT", .h1, count: Snapshot.maxBars + 500)
    let n = try Snapshot.write(s, to: p.snapshot)
    #expect(n <= Snapshot.maxBytes)

    let back = try #require(Snapshot.read(p.snapshot))
    #expect(back.count == Snapshot.maxBars)             // 只留末 maxBars 根
    #expect(back.symbol == "BTCUSDT")
    #expect(back.interval == .h1)
    #expect(back.lastTime == s.lastTime)
    for i in 0..<back.count {
      let j = s.count - back.count + i
      #expect(back.time(at: i) == s.time(at: j))
      #expect(back.open[i] == s.open[j])
      #expect(back.high[i] == s.high[j])
      #expect(back.low[i] == s.low[j])
      #expect(back.close[i] == s.close[j])
      #expect(back.volume[i] == s.volume[j])
    }
    // 再编一次，逐字节一致（编解码是幂等的）。
    #expect(Snapshot.encode(back) == Snapshot.encode(Snapshot.decode(Snapshot.encode(back))!))
  }

  @Test("读快照 + 建 BarSeries < 20ms")
  func snapshotSpeed() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    _ = try Snapshot.write(makeSeries("BTCUSDT", .h1, count: 600), to: p.snapshot)
    // 先热一次文件系统，再计时。
    _ = Snapshot.read(p.snapshot)
    // 计的是这条线程真正花掉的 CPU 时间，不是墙上时钟：读快照是同步的、就在这条线程上
    // 做完（文件刚热过，读盘就是一次页缓存拷贝），它的开销全在这里面。墙上时钟会把
    // 「这条线程被抢走的那段」也算进去——整包并行跑、外面还有别的编译时负载到 50，
    // 一次 5ms 的读能被量成 60ms，那量的是机器忙不忙，不是读快照快不快。
    let t0 = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    let s = Snapshot.read(p.snapshot)
    let ms = Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - t0) / 1e6
    #expect(s?.count == 600)
    #expect(ms < 20)
  }

  @Test("不规则周期（1M）带 openTime 表，也能原样读回")
  func snapshotIrregular() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    var bars: [Bar] = []
    for y in 2020...2024 {
      for m in 1...12 {
        let t = Aggregator.utcMs(year: y, month: m, day: 1)
        bars.append(Bar(openTime: t, open: 1, high: 2, low: 0, close: 1.5, volume: 9))
      }
    }
    let s = BarSeries(symbol: "ETHUSDT", interval: .mo1, bars: bars)
    _ = try Snapshot.write(s, to: p.snapshot)
    let back = try #require(Snapshot.read(p.snapshot))
    #expect(back.interval == .mo1)
    #expect(back.count == s.count)
    #expect((0..<back.count).allSatisfy { back.time(at: $0) == s.time(at: $0) })
  }

  @Test("坏文件不崩，返回 nil")
  func snapshotGarbage() throws {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }
    try Data([1, 2, 3, 4, 5]).write(to: p.snapshot)
    #expect(Snapshot.decode(Data([1, 2, 3, 4, 5])) == nil)
    #expect(Snapshot.read(p.snapshot) == nil)
    #expect(Snapshot.decode(Data()) == nil)
  }

  // ---------------------------------------------------------------- A2.12

  @Test("内存缓存：总量封顶、LRU 淘汰最久没用的")
  func cacheLRU() async throws {
    // 每根 40B，1000 根 = 40KB；上限给 100KB，只放得下 2 份。
    let cache = BarCache(limitBytes: 100 * 1024)
    await cache.put(makeSeries("AAAUSDT", .h1, count: 1000))
    await cache.put(makeSeries("BBBUSDT", .h1, count: 1000))
    _ = await cache.get(SeriesKey("AAAUSDT", .h1))          // A 刚用过
    await cache.put(makeSeries("CCCUSDT", .h1, count: 1000))
    let keys = await cache.keys.map(\.symbol)
    #expect(!keys.contains("BBBUSDT"))                       // 最久没用的先走
    #expect(keys.contains("CCCUSDT"))
    #expect(await cache.totalBytes <= 100 * 1024)
  }

  @Test("30 品种 × 14 周期跑一遍，缓存不超 40MB")
  func cacheFlood() async throws {
    let cache = BarCache()
    for i in 0..<30 {
      for iv in Interval.allCases {
        await cache.put(makeSeries("S\(i)USDT", iv, count: 1500))
      }
    }
    #expect(await cache.totalBytes <= BarCache.defaultLimitBytes)
    #expect(await cache.count > 0)
  }

  @Test("内存警告后只剩当前 (品种, 周期)")
  func cachePurge() async throws {
    let cache = BarCache()
    for i in 0..<5 { await cache.put(makeSeries("S\(i)USDT", .h1, count: 100)) }
    await cache.purge(keeping: SeriesKey("S3USDT", .h1))
    #expect(await cache.keys == [SeriesKey("S3USDT", .h1)])
    await cache.purge(keeping: nil)
    #expect(await cache.count == 0)
  }

  @Test("单个 key 超长会裁掉最老的")
  func cacheTrim() async throws {
    let cache = BarCache(limitBytes: BarCache.defaultLimitBytes, perKeyCap: 500)
    await cache.put(makeSeries("BTCUSDT", .m1, count: 2000))
    let s = try #require(await cache.get(SeriesKey("BTCUSDT", .m1)))
    #expect(s.count == 500)
    #expect(s.lastTime == makeSeries("BTCUSDT", .m1, count: 2000).lastTime)
  }
}
