import Foundation
import Testing
@testable import KanpanData
import KanpanCore

/// 缓存这一层：预热的错误分级、快照目录的进程内索引、不 touch 的读。
@Suite("缓存层：预热分级与目录索引")
struct CacheLayerTests {

  private func tempDir() -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-cache-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  // ----------------------------------------------------------- 预热的错误分级

  @Test("预热：品种级的 4xx 跳过接着跑，线路级的错误才停")
  func prefetchErrorsAreGraded() {
    // 这一个品种不行：跳过，后面的还要预热。
    #expect(RoutedMarketFeed.skippable(BinanceError(status: 404)))
    #expect(RoutedMarketFeed.skippable(BinanceError(status: 400, code: -1121, msg: "Invalid symbol.")))
    #expect(RoutedMarketFeed.skippable(BinanceError(status: 451)))

    // 整条线路不行：必须停，不然是拿一串失败去砸交易所。
    #expect(!RoutedMarketFeed.skippable(BinanceError(status: 429)))
    #expect(!RoutedMarketFeed.skippable(BinanceError(status: 418)))
    #expect(!RoutedMarketFeed.skippable(BinanceError(status: 408)))
    #expect(!RoutedMarketFeed.skippable(BinanceError(status: 500)))
    #expect(!RoutedMarketFeed.skippable(BinanceError(status: 503)))
    #expect(!RoutedMarketFeed.skippable(URLError(.notConnectedToInternet)))
    #expect(!RoutedMarketFeed.skippable(FeedError.badResponse("坏了")))
    #expect(!RoutedMarketFeed.skippable(CancellationError()))
  }

  // ----------------------------------------------------------- 目录索引

  @Test("目录索引：写盘增量记账，不用每次扫目录")
  func indexTracksWrites() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let index = SeriesIndex()

    var total = 0
    var bytes0 = 0
    for i in 0..<5 {
      let n = try SeriesStore.write(makeSeries("S\(i)USDT", .m5, count: 40), in: dir)
      total += n
      if i == 0 { bytes0 = n }
      let url = try #require(SeriesStore.url(symbol: "S\(i)USDT", interval: .m5, in: dir))
      await index.wrote(url, in: dir, bytes: n, at: Date())
    }
    let stats = await index.stats(dir)
    #expect(stats.count == 5)
    #expect(stats.bytes == total)

    // 同一对再写一遍是覆盖，不是新增：条数不变，字节要换掉那一份而不是累加。
    let url0 = try #require(SeriesStore.url(symbol: "S0USDT", interval: .m5, in: dir))
    await index.wrote(url0, in: dir, bytes: 999, at: Date())
    let after = await index.stats(dir)
    #expect(after.count == 5)
    #expect(after.bytes == total - bytes0 + 999)
  }

  @Test("目录索引：第一次碰到目录扫一遍，之后删掉的、忘掉的都对得上")
  func indexScansOnceThenTracks() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    for i in 0..<4 {
      _ = try SeriesStore.write(makeSeries("T\(i)USDT", .h1, count: 30), in: dir)
    }
    // 全新的索引：第一次问它就得把这 4 份扫出来。
    let index = SeriesIndex()
    let scanned = await index.stats(dir)
    #expect(scanned.count == 4)
    #expect(scanned.bytes > 0)

    let url = try #require(SeriesStore.url(symbol: "T0USDT", interval: .h1, in: dir))
    await index.dropped(url, in: dir)
    let dropped = await index.stats(dir)
    #expect(dropped.count == 3)
    #expect(dropped.bytes < scanned.bytes)

    // 磁盘被别人动过就作废重扫：文件还在，所以又回到 4 份。
    await index.forget(dir)
    #expect(await index.stats(dir).count == 4)
  }

  @Test("目录索引：读一次只挪 LRU 位置，不改条数也不改字节")
  func touchMovesOnlyTheMark() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try SeriesStore.write(makeSeries("BTCUSDT", .m15, count: 20), in: dir)

    let index = SeriesIndex()
    let url = try #require(SeriesStore.url(symbol: "BTCUSDT", interval: .m15, in: dir))
    let before = await index.stats(dir)
    let old = try #require(await index.mark(url, in: dir))

    let later = old.addingTimeInterval(120)
    await index.touched(url, in: dir, at: later)
    #expect(await index.mark(url, in: dir) == later)
    let after = await index.stats(dir)
    #expect(after.count == before.count)
    #expect(after.bytes == before.bytes)
  }

  // ----------------------------------------------------------- 不 touch 的读

  @Test("冷启动那一读可以不写 mtime")
  func coldReadDoesNotTouch() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try SeriesStore.write(makeSeries("ETHUSDT", .m1, count: 50), in: dir)
    let url = try #require(SeriesStore.url(symbol: "ETHUSDT", interval: .m1, in: dir))

    // 把 mtime 按到一个很老的时刻，再读一次——`touch: false` 不许动它。
    let old = Date(timeIntervalSince1970: 1_600_000_000)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    let series = try #require(SeriesStore.read(symbol: "ETHUSDT", interval: .m1, in: dir, touch: false))
    #expect(series.count == 50)

    let mtime = (try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
    #expect(abs((mtime ?? .distantPast).timeIntervalSince(old)) < 1)
  }

  @Test("默认那条读仍然会把 mtime 顶上去，只是不在调用线程上做")
  func normalReadStillTouches() async throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    _ = try SeriesStore.write(makeSeries("ETHUSDT", .m1, count: 50), in: dir)
    let url = try #require(SeriesStore.url(symbol: "ETHUSDT", interval: .m1, in: dir))

    let old = Date(timeIntervalSince1970: 1_600_000_000)
    try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: url.path)
    #expect(SeriesStore.read(symbol: "ETHUSDT", interval: .m1, in: dir) != nil)

    // touch 挪到后台去了，等它落地（最多 2 秒）。
    var bumped = false
    for _ in 0..<200 {
      let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? nil
      if let mtime, mtime.timeIntervalSince(old) > 1 { bumped = true; break }
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(bumped)
  }
}
