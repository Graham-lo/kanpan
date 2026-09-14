import Foundation
import Testing
@testable import KanpanData
import KanpanCore

@Suite("OI 归档：自写 ZIP + CSV")
struct OIArchiveTests {

  // ---------------------------------------------------------------- A2.11 归档

  @Test("真实 metrics zip：解出 288 行 5 分钟粒度")
  func realZip() throws {
    let data = Fixture.data("metrics-btcusdt-2025-01-15.zip")
    let e = try Zip.firstEntry(data)
    #expect(e.name.hasSuffix(".csv"))
    #expect(e.method == 8)                       // deflate
    let csv = try Zip.unzipFirst(data)
    #expect(csv.count == e.uncompressedSize)
    #expect(String(decoding: csv.prefix(11), as: UTF8.self) == "create_time")

    let pts = try OIArchive.parseZip(data)
    #expect(pts.count == 288)                    // 一天 288 个 5 分钟点
    #expect(Set(pts.map(\.time)).count == 288)
    // 解析出来必须是等距递增的（有的原文件是乱序的，见下一条用例）。
    for i in 1..<pts.count { #expect(pts[i].time == pts[i - 1].time + 300_000) }
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    #expect(pts[0].time == day)
    #expect(pts[287].time == day + 287 * 300_000)
    #expect(pts.allSatisfy { $0.value > 0 } == true)
    // §4.5 的四个附加列一起读回来。
    #expect(pts[0].topTraderAccountRatio != nil)
    #expect(pts[0].topTraderPositionRatio != nil)
    #expect(pts[0].accountRatio != nil)
    #expect(pts[0].takerVolumeRatio != nil)
  }

  @Test("归档站有的文件本身是乱序的：解析器必须自己排")
  func csvOrdering() throws {
    func rawTimes(_ name: String) throws -> [Int64] {
      let csv = try Zip.unzipFirst(Fixture.data(name))
      var out: [Int64] = []
      String(decoding: csv, as: UTF8.self).enumerateLines { line, _ in
        guard !line.hasPrefix("create_time"), !line.isEmpty else { return }
        if let t = OIArchive.parseTime(line.split(separator: ",")[0]) { out.append(t) }
      }
      return out
    }
    // 2025-01-15 这天文件本来就有序；2026-09-01 这天是乱的（实测，归档站近期的文件都乱）。
    let ordered = try rawTimes("metrics-btcusdt-2025-01-15.zip")
    let shuffled = try rawTimes("metrics-btcusdt-2026-09-01.zip")
    #expect(ordered == ordered.sorted())
    #expect(shuffled != shuffled.sorted())
    #expect(Set(shuffled).count == 288)
    // 不管哪种，解析出来都得是等距递增的 288 条。
    for name in ["metrics-btcusdt-2025-01-15.zip", "metrics-btcusdt-2026-09-01.zip"] {
      let pts = try OIArchive.parseZip(Fixture.data(name))
      #expect(pts.count == 288)
      for i in 1..<pts.count { #expect(pts[i].time == pts[i - 1].time + 300_000) }
    }
  }

  @Test("不是 zip / 方法不认 / 截断，都抛明确错误不崩")
  func zipFailures() {
    #expect(throws: Zip.Failure.notZip) { _ = try Zip.firstEntry(Data("hello".utf8)) }
    #expect(throws: Zip.Failure.notZip) { _ = try Zip.firstEntry(Data()) }
    var trunc = Fixture.data("metrics-btcusdt-2025-01-15.zip")
    trunc = trunc.prefix(40)
    #expect(throws: (any Error).self) { _ = try Zip.unzipFirst(trunc) }
  }

  @Test(".oi 日切片：编解码一致，一天 ≈ 3.4KB")
  func sliceCodec() throws {
    let pts = try OIArchive.parseZip(Fixture.data("metrics-btcusdt-2025-01-15.zip"))
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let blob = OIArchive.encodeSlice(pts, dayStartMs: day)
    #expect(blob.count < 4096)
    let back = try #require(OIArchive.decodeSlice(blob))
    #expect(back.count == pts.count)
    #expect(back.map(\.time) == pts.map(\.time))
    #expect(back.map(\.value) == pts.map(\.value))
  }

  @Test("日期工具：dayString / dayStart / days / 中间优先")
  func dayHelpers() {
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    #expect(OIArchive.dayString(day) == "2025-01-15")
    #expect(OIArchive.dayString(day + 86_399_999) == "2025-01-15")
    #expect(OIArchive.dayStart(day + 12345) == day)
    let ds = OIArchive.days(from: day, to: day + 3 * 86_400_000)
    #expect(ds.count == 4)
    #expect(ds.first == day)
    #expect(OIArchive.centerOut([1, 2, 3, 4, 5]) == [3, 4, 2, 5, 1])
  }

  @Test("存取日切片：关掉开关就不落盘")
  func store() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    let paths = Paths(root: dir)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = OIStore(paths: paths)
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let pts = try OIArchive.parseZip(Fixture.data("metrics-btcusdt-2025-01-15.zip"))
    await store.save(symbol: "BTCUSDT", dayStart: day, points: pts)
    #expect(await store.load(symbol: "BTCUSDT", dayStart: day)?.count == 288)
    #expect(await store.usage() > 0)

    await store.setEnabled(false)
    #expect(await store.load(symbol: "BTCUSDT", dayStart: day) == nil)
    #expect(await store.usage() == 0)
    await store.save(symbol: "BTCUSDT", dayStart: day, points: pts)
    #expect(await store.usage() == 0)
  }
}

@Suite("OI 对齐：两源合一条")
struct OIAlignTests {

  private func pts(from: Int64, step: Int64, n: Int, base: Double = 1000) -> [OIPoint] {
    (0..<n).map { OIPoint(time: from + Int64($0) * step, value: base + Double($0)) }
  }

  @Test("1m / 3m 比 5m 细：原样保留，相邻几根共用一个值")
  func finerThanSource() {
    let five = pts(from: 0, step: 300_000, n: 4)
    #expect(OISource.downsample(five, to: .m1).count == 4)
    #expect(OISource.downsample(five, to: .m3).count == 4)

    let series = BarSeries(symbol: "X", interval: .m1,
                           bars: makeBars(t0: 0, step: 60_000, count: 15))
    let a = OISource.align(five, to: series)
    // 0..4 分钟取第 0 个点，5..9 取第 1 个，依此类推。
    #expect(a[0] == 1000); #expect(a[4] == 1000)
    #expect(a[5] == 1001); #expect(a[9] == 1001)
    #expect(a[10] == 1002)
  }

  @Test("1w / 1M / 1y：按桶取最后一条")
  func bucketLast() {
    // 2024 年每天一个点，聚到 1M：每月拿该月最后一天的值。
    var p: [OIPoint] = []
    var t = Aggregator.utcMs(year: 2024, month: 1, day: 1)
    var v = 0.0
    while t < Aggregator.utcMs(year: 2024, month: 4, day: 1) {
      p.append(OIPoint(time: t, value: v)); v += 1; t += 86_400_000
    }
    let m = OISource.downsample(p, to: .mo1)
    #expect(m.count == 3)
    #expect(m[0].time == Aggregator.utcMs(year: 2024, month: 1, day: 1))
    #expect(m[0].value == 30)          // 1 月 31 天，最后一条是第 31 个（0 起）
    #expect(m[1].value == 59)          // 2 月 29 天（闰年）
    #expect(m[2].time == Aggregator.utcMs(year: 2024, month: 3, day: 1))
  }

  @Test("对齐取「之前最近」一条，没有就是 NaN")
  func alignFloor() {
    let series = BarSeries(symbol: "X", interval: .h1,
                           bars: makeBars(t0: 10_800_000, step: 3_600_000, count: 5))
    // 点从第 2 根才开始，前两根应为 NaN。
    let p = [OIPoint(time: 18_000_000, value: 7), OIPoint(time: 21_600_000, value: 8)]
    let a = OISource.align(p, to: series)
    #expect(a[0].isNaN)
    #expect(a[1].isNaN)
    #expect(a[2] == 7)                 // 18_000_000 正好是第 3 根开盘
    #expect(a[3] == 8)
    #expect(a[4] == 8)                 // 之后没有新点，续用最后一条
  }

  @Test("点列有缺口也对得上：缺口里续用缺口前那条")
  func alignWithHole() {
    let series = BarSeries(symbol: "X", interval: .h1,
                           bars: makeBars(t0: 0, step: 3_600_000, count: 6))
    let p = [OIPoint(time: 0, value: 1), OIPoint(time: 3_600_000, value: 2),
             OIPoint(time: 5 * 3_600_000, value: 6)]     // 中间缺 3 根
    #expect(OISource.align(p, to: series) == [1, 2, 2, 2, 2, 6])
  }

  @Test("两源接缝：REST 段和归档段拼起来无重复无缺口")
  func seam() {
    // 归档到 T，REST 从 T 开始重叠一段——dedup 后应当仍是等距 5 分钟。
    let t: Int64 = 1_700_000_000_000 / 300_000 * 300_000
    let archive = pts(from: t - 20 * 300_000, step: 300_000, n: 21, base: 100)
    let rest = pts(from: t, step: 300_000, n: 10, base: 200)      // 与归档重叠 1 条
    let all = OISource.dedup(archive + rest)
    #expect(all.count == 30)
    for i in 1..<all.count { #expect(all[i].time == all[i - 1].time + 300_000) }
    #expect(all.first { $0.time == t }?.value == 200)             // 重叠处以 REST 为准
  }

  @Test("空点列 / 空序列不崩")
  func empties() {
    let series = makeSeries("X", .h1, count: 3)
    #expect(OISource.align([], to: series).allSatisfy { $0.isNaN } == true)
    #expect(OISource.downsample([], to: .h1).isEmpty)
    #expect(OISource.dedup([]).isEmpty)
  }

  @Test("品种上市前：归档站 404 → 返回空而不是报错")
  func beforeListing() async throws {
    let pacer = StepPacer()
    let server = FakeServer(pacer: pacer) { url in
      if url.host == "data.binance.vision" { return HTTPReply(status: 404) }
      return json("[]")
    }
    let transport = FakeTransport(server)
    let rest = BinanceREST(transport: transport, pacer: pacer)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = OISource(rest: rest, transport: transport, store: OIStore(paths: Paths(root: dir)))
    let now: Int64 = 1_700_000_000_000
    let out = await src.rawPoints(symbol: "NEWUSDT", interval: .h1,
                                  from: now - 200 * 86_400_000, to: now, now: now)
    #expect(out.isEmpty)
    #expect(await server.urls().contains { $0.host == "data.binance.vision" })
  }

  @Test("近 30 天走 REST、更早走归档：两个源都被问到")
  func twoSources() async throws {
    let pacer = StepPacer()
    let zip = Fixture.data("metrics-btcusdt-2025-01-15.zip")
    let now = Aggregator.utcMs(year: 2025, month: 2, day: 20)
    let server = FakeServer(pacer: pacer) { url in
      if url.host == "data.binance.vision" { return HTTPReply(status: 200, body: zip) }
      if url.path == "/futures/data/openInterestHist" {
        let rows = (0..<3).map { i -> String in
          let t = now - Int64(3 - i) * 3_600_000
          return #"{"symbol":"BTCUSDT","sumOpenInterest":"50.0","sumOpenInterestValue":"1","timestamp":\#(t)}"#
        }
        return json("[" + rows.joined(separator: ",") + "]")
      }
      return json("[]")
    }
    let transport = FakeTransport(server)
    let rest = BinanceREST(transport: transport, pacer: pacer)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = OISource(rest: rest, transport: transport, store: OIStore(paths: Paths(root: dir)))
    let out = await src.rawPoints(symbol: "BTCUSDT", interval: .h1,
                                  from: now - 40 * 86_400_000, to: now, now: now)
    let hosts = Set(await server.urls().compactMap(\.host))
    #expect(hosts.contains("data.binance.vision"))
    #expect(hosts.contains("fapi.binance.com"))
    #expect(out.count > 288)                    // 归档的 288×N + REST 的几条
    for i in 1..<out.count { #expect(out[i].time > out[i - 1].time) }
  }
}
