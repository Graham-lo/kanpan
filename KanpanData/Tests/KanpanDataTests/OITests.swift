import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport
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

  @Test("历史网关失败换备用，保留周期且不重复下载ZIP", arguments: [200, 429, 503])
  func gatewayPeriodRequest(firstStatus: Int) async throws {
    let day = Aggregator.utcMs(year: 2021, month: 12, day: 1)
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 15)
    let pacer = StepPacer()
    let server = FakeServer(pacer: pacer) { url in
      if url.host == "gateway.example", firstStatus != 200 { return HTTPReply(status: firstStatus) }
      if ["gateway.example", "backup.example"].contains(url.host ?? ""), url.path.hasSuffix("/range") {
        return json("[[\(day),120]]")
      }
      return HTTPReply(status: 500)
    }
    let transport = FakeTransport(server)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = OISource(hosts: BinanceHosts(oiProxy: "gateway.example", oiProxyFallbacks: ["backup.example"]),
      rest: BinanceREST(transport: transport, pacer: pacer), transport: transport,
      store: OIStore(paths: Paths(root: dir)))
    let result = await source.rawPoints(symbol: "BTCUSDT", interval: .h4,
      from: day, to: day + 86_399_999, now: now)
    #expect(result == [.init(time: day, value: 120)])
    let urls = await server.urls()
    #expect(urls.count == (firstStatus == 200 ? 1 : 2))
    #expect(urls.last?.host == (firstStatus == 200 ? "gateway.example" : "backup.example"))
    #expect(URLComponents(url: urls.last!, resolvingAgainstBaseURL: false)?.queryItems?.contains(
      URLQueryItem(name: "interval", value: "4h")) == true)
  }

  @Test("图表管线按周期取最后持仓量，不求和、不直接取原始首点", arguments: Interval.allCases)
  func chartPipeline(interval: Interval) {
    let origin = Aggregator.utcMs(year: 2024, month: 2, day: 15)
    let bucket = Aggregator.bucketStart(ms: origin, interval: interval)
    let raw = [OIPoint(time: bucket, value: 100),
               OIPoint(time: bucket + 300_000, value: 120),
               OIPoint(time: bucket + 600_000, value: 110)]
    let chart = OISource.chartSeries(raw, interval: interval)
    let bars = BarSeries(symbol: "X", interval: interval,
      bars: makeBars(t0: bucket, step: interval.stepMs, count: 1))
    let expected = interval.stepMs > 600_000 ? 110.0 : 100.0
    #expect(chart.aligned(to: bars) == [expected])
  }

  @Test("月OI用真实日历桶，缺失二月不把一月或三月数据填进去")
  func calendarGap() {
    let jan = Aggregator.utcMs(year: 2024, month: 1, day: 1)
    let feb = Aggregator.utcMs(year: 2024, month: 2, day: 1)
    let mar = Aggregator.utcMs(year: 2024, month: 3, day: 1)
    let apr = Aggregator.utcMs(year: 2024, month: 4, day: 1)
    let chart = OISource.chartSeries([
      .init(time: jan + 300_000, value: 10), .init(time: mar + 600_000, value: 30)
    ], interval: .mo1)
    var bars = BarSeries(symbol: "X", interval: .mo1,
      bars: makeBars(t0: jan, step: Interval.mo1.stepMs, count: 4))
    bars.openTime = [jan, feb, mar, apr]
    let aligned = chart.aligned(to: bars)
    #expect(aligned[0] == 10 && aligned[2] == 30)
    #expect(aligned[1].isNaN && aligned[3].isNaN)
  }

  @Test("分钟图仅在5分钟采样有效窗内复用OI，不提前取未来点或跨缺口延长")
  func fineGap() {
    let chart = OISource.chartSeries([.init(time: 300_000, value: 10),
                                     .init(time: 900_000, value: 20)], interval: .m1)
    let bars = BarSeries(symbol: "X", interval: .m1, bars: makeBars(t0: 0, step: 60_000, count: 17))
    let aligned = chart.aligned(to: bars)
    #expect(aligned[4].isNaN && aligned[10].isNaN && aligned[14].isNaN)
    #expect(aligned[5] == 10 && aligned[9] == 10 && aligned[15] == 20)
  }

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

@Suite("OI 增量：只补缺的那一段")
struct OIIncrementalTests {

  private static let step: Int64 = 3_600_000

  @Test("手里没有：整段都要")
  func nothingCached() {
    let out = OISource.missingSegments(have: nil, want: (100, 200), step: Self.step, refresh: false)
    #expect(out.count == 1)
    #expect(out[0] == (100, 200))
  }

  @Test("往左拖：只取左边多出来的一截")
  func panLeft() {
    let out = OISource.missingSegments(have: (1_000, 2_000), want: (500, 1_800),
                                       step: Self.step, refresh: false)
    #expect(out.count == 1)
    #expect(out[0] == (500, 1_000))
  }

  @Test("窗口整个落在已有区间里：一个请求都不发")
  func fullyCovered() {
    #expect(OISource.missingSegments(have: (1_000, 2_000), want: (1_200, 1_800),
                                     step: Self.step, refresh: false).isEmpty)
  }

  @Test("两头都缺：拆成左右两段，不重不漏")
  func bothEnds() throws {
    let out = OISource.missingSegments(have: (1_000, 2_000), want: (500, 2_500),
                                       step: Self.step, refresh: false)
    try #require(out.count == 2)
    #expect(out[0] == (500, 1_000))
    #expect(out[1] == (2_000, 2_500))
  }

  @Test("和已有区间完全不挨着：整段重取")
  func disjoint() {
    let out = OISource.missingSegments(have: (1_000, 2_000), want: (5_000, 6_000),
                                       step: Self.step, refresh: false)
    #expect(out.count == 1)
    #expect(out[0] == (5_000, 6_000))
  }

  @Test("60 秒定时刷新：全都在手里也要把尾巴几根重取一次")
  func refreshTail() {
    let have = (from: Int64(0), to: 100 * Self.step)
    let want = (from: Int64(0), to: 100 * Self.step)
    let out = OISource.missingSegments(have: have, want: want, step: Self.step, refresh: true)
    #expect(out.count == 1)
    #expect(out[0].to == want.to)
    #expect(out[0].from == want.to - 3 * Self.step)   // 最后三根
    // 不刷新时同样的入参一个请求都不发。
    #expect(OISource.missingSegments(have: have, want: want, step: Self.step, refresh: false).isEmpty)
  }

  @Test("刷新时左边也缺：尾巴并进右边那段，不会多发一个请求")
  func refreshMergesIntoRightGap() throws {
    let base = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let have = (from: base, to: base + 1_000 * Self.step)
    let want = (from: base - 500 * Self.step, to: base + 1_100 * Self.step)
    let out = OISource.missingSegments(have: have, want: want, step: Self.step, refresh: true)
    try #require(out.count == 2)                     // 左缺口 + 右缺口（尾巴被右缺口盖住）
    #expect(out[0] == (want.from, have.from))
    #expect(out[1] == (have.to, want.to))
  }

  @Test("空窗口 / 倒着的窗口：不发请求")
  func degenerate() {
    #expect(OISource.missingSegments(have: nil, want: (100, 100), step: Self.step, refresh: true).isEmpty)
    #expect(OISource.missingSegments(have: nil, want: (200, 100), step: Self.step, refresh: false).isEmpty)
  }

  @Test("请求区间收敛成实际覆盖：伸到未来那两根不许记成已有")
  func coveredClampsFuture() {
    let step = Self.step
    let last = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let pts = (0...9).map { OIPoint(time: last - Int64(9 - $0) * step, value: 1_000 + Double($0)) }
    // `loadOI` 的 want.to 最远到「最后一根开盘 + 2 × step」，而数据只到 last。
    let region = OISource.coveredRegion(want: (from: pts[0].time, to: last + 2 * step),
                                        points: pts, step: step)
    #expect(region.from == pts[0].time)
    #expect(region.to == last + step)               // 只到真拿到的那根桶的末尾
    // 一个点都没拿到：右端不推进，也不许倒过来。
    let empty = OISource.coveredRegion(want: (from: pts[0].time, to: last + 2 * step),
                                       points: [], step: step)
    #expect(empty.from == pts[0].time)
    #expect(empty.to == pts[0].time)
    #expect(empty.to >= empty.from)
  }

  @Test("左端不收：上市前那一截照样算问过，不会每次平移重下一遍")
  func coveredKeepsLeftEdge() {
    let step = Self.step
    let listing = Aggregator.utcMs(year: 2025, month: 1, day: 15)   // 这根之前没有任何数据
    let want = (from: listing - 500 * step, to: listing + 2 * step)
    let pts = [OIPoint(time: listing, value: 1_000), OIPoint(time: listing + step, value: 1_001)]
    let region = OISource.coveredRegion(want: want, points: pts, step: step)
    #expect(region.from == want.from)               // 左端保持 want.from，没被推到右边去
    #expect(region.to == listing + 2 * step)
    // 下一轮同样的视野：左边不再重取，只剩尾巴那一小段。
    let again = OISource.missingSegments(have: region, want: want, step: step, refresh: true)
    #expect(again.allSatisfy { $0.from >= want.to - 3 * step })
  }

  @Test("会话接缝不留洞：下一轮从空洞那根接着补，不是从虚高的右端")
  func seamLeavesNoHole() throws {
    let step = Self.step
    let last = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let first = last - 100 * step
    let pts = (0...100).map { OIPoint(time: first + Int64($0) * step, value: 1_000) }
    // 第一轮：请求伸到「最后一根 K 线 + 2 × step」，但币安最新只给得到 last 这一根。
    let have = OISource.coveredRegion(want: (from: first, to: last + 2 * step), points: pts, step: step)
    // 第二轮（下次开图 / 后台待过两根桶再回前台）：又走了 5 根，照样请求到「最后一根 + 2 × step」。
    let want = (from: first, to: last + 7 * step)
    let out = OISource.missingSegments(have: have, want: want, step: step, refresh: true)
    let head = try #require(out.first)
    // last + 1 × step 那根桶必须被重新取到，否则它永远是 NaN，曲线中间断一格。
    #expect(head.from <= last + step)
  }

  @Test("已聚好的一段存盘：编解码一致，区间跟着回来")
  func rangeCodec() throws {
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let pts = (0..<240).map { OIPoint(time: day + Int64($0) * 3_600_000, value: 1_000 + Double($0) * 0.5) }
    let blob = OIArchive.encodeRange(pts, from: day, to: day + 240 * 3_600_000)
    let back = try #require(OIArchive.decodeRange(blob))
    #expect(back.from == day)
    #expect(back.to == day + 240 * 3_600_000)
    #expect(back.points.map(\.time) == pts.map(\.time))
    #expect(back.points.map(\.value) == pts.map(\.value))
  }

  @Test("坏盘面：不是 KOI2 / 被截断 / 区间倒着，一律当没有")
  func rangeCodecRejects() {
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let pts = [OIPoint(time: day, value: 1), OIPoint(time: day + 3_600_000, value: 2)]
    let good = OIArchive.encodeRange(pts, from: day, to: day + 7_200_000)
    #expect(OIArchive.decodeRange(Data("hello".utf8)) == nil)
    #expect(OIArchive.decodeRange(good.prefix(good.count - 4)) == nil)
    #expect(OIArchive.decodeRange(Data()) == nil)
    #expect(OIArchive.decodeRange(OIArchive.encodeRange(pts, from: day + 7_200_000, to: day)) == nil)
    // 日切片和聚合段两个格式互不认账。
    #expect(OIArchive.decodeSlice(good) == nil)
  }

  @Test("聚合段存取：换一张图回来先有旧的可画")
  func seriesStore() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = OIStore(paths: Paths(root: dir))
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let pts = (0..<48).map { OIPoint(time: day + Int64($0) * 3_600_000, value: Double(100 + $0)) }
    await store.saveSeries(symbol: "BTCUSDT", interval: .h1, points: pts,
                           from: day, to: day + 48 * 3_600_000)
    let back = try #require(await store.loadSeries(symbol: "BTCUSDT", interval: .h1))
    #expect(back.points.count == 48)
    #expect(back.from == day)
    // 一个周期一份，别的周期不串味。
    #expect(await store.loadSeries(symbol: "BTCUSDT", interval: .h4) == nil)
    #expect(await store.loadSeries(symbol: "ETHUSDT", interval: .h1) == nil)
    // 关掉开关就读不到，也不该留在盘上。
    await store.setEnabled(false)
    #expect(await store.loadSeries(symbol: "BTCUSDT", interval: .h1) == nil)
    #expect(await store.usage() == 0)
  }

  @Test("REST 翻到一半断了：已经到手的几页要留住，不是整条空")
  func partialRestPages() async throws {
    let now = Aggregator.utcMs(year: 2025, month: 2, day: 20)
    let to = now
    let pacer = StepPacer()
    let server = FakeServer(pacer: pacer) { url in
      guard url.path == "/futures/data/openInterestHist" else { return HTTPReply(status: 404) }
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let endTime = q.first { $0.name == "endTime" }?.value.flatMap { Int64($0) }
      // 第一页正常给满 500 条，第二页（更早的那一页）直接断。
      guard endTime == to else { return HTTPReply(status: 500) }
      let rows = (0..<500).map { i -> String in
        let t = to - Int64(499 - i) * 3_600_000
        return #"{"symbol":"BTCUSDT","sumOpenInterest":"50.0","sumOpenInterestValue":"1","timestamp":\#(t)}"#
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }
    let transport = FakeTransport(server)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = OISource(rest: BinanceREST(transport: transport, pacer: pacer), transport: transport,
                       store: OIStore(paths: Paths(root: dir)))
    let out = await src.rawPoints(symbol: "BTCUSDT", interval: .h1,
                                  from: now - 29 * 86_400_000, to: to, now: now)
    #expect(out.count == 500)
    #expect(out.last?.time == to)
    #expect(await server.urls().count == 2)          // 断掉的那一页确实试过
  }
}

@Suite("OI 切块：细周期看长区间也要走网关那条快路")
struct OIChunkTests {

  /// 服务端的护栏：一次不超过十年，也不超过两万根自己周期的柱子。
  private static func serverLimit(step: Int64) -> Int64 {
    min(3_660 * 86_400_000, 20_000 * max(step, 300_000))
  }

  @Test("日线看一年：还是一个请求，不为切块而切块")
  func dailyStaysWhole() {
    let to = Aggregator.utcMs(year: 2026, month: 9, day: 1)
    let from = to - 365 * 86_400_000
    let chunks = OISource.historyChunks(from: from, to: to, step: 86_400_000)
    #expect(chunks.count == 1)
    #expect(chunks[0].from == from)
    #expect(chunks[0].to == to)
  }

  @Test("5 分钟看一年：切成几块，每块都在服务端的上限之内", arguments: [
    Interval.m1, .m3, .m5, .m15
  ])
  func fineIntervalsSplit(interval: Interval) throws {
    let to = Aggregator.utcMs(year: 2026, month: 9, day: 1)
    let from = to - 365 * 86_400_000
    let step = interval.stepMs
    let chunks = OISource.historyChunks(from: from, to: to, step: step)
    try #require(chunks.count > 1)             // 不切就会被服务端 400 顶回来
    let limit = Self.serverLimit(step: step)
    for chunk in chunks { #expect(chunk.to - chunk.from <= limit) }
    // 首尾对齐、块块相接：既不漏一段，也不留下需要再补的缝。
    #expect(chunks.first?.from == from)
    #expect(chunks.last?.to == to)
    for i in 1..<chunks.count { #expect(chunks[i].from == chunks[i - 1].to) }
  }

  @Test("空窗口 / 倒着的窗口：不切出任何块")
  func degenerate() {
    let t = Aggregator.utcMs(year: 2026, month: 9, day: 1)
    #expect(OISource.historyChunks(from: t, to: t - 1, step: 300_000).isEmpty)
    let single = OISource.historyChunks(from: t, to: t, step: 300_000)
    #expect(single.count == 1)
    #expect(single[0].from == t)
    #expect(single[0].to == t)
  }
}

@Suite("OI 分段上屏：先到的那一段不必陪着慢的一起等")
struct OIPartialTests {

  private actor Batches {
    private(set) var all: [[OIPoint]] = []
    func add(_ points: [OIPoint]) { all.append(points) }
  }

  /// REST 和归档都在场时，两段各自落地就各回调一次。
  @Test("两段都在：先到的先回调，不等另一段")
  func bothHalvesReport() async throws {
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
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = OISource(rest: BinanceREST(transport: transport, pacer: pacer), transport: transport,
                       store: OIStore(paths: Paths(root: dir)))
    let batches = Batches()
    let out = await src.rawPoints(symbol: "BTCUSDT", interval: .h1,
                                  from: now - 40 * 86_400_000, to: now, now: now,
                                  onPartial: { points in Task { await batches.add(points) } })
    // 回调是从别的任务里发出来的，等它们收尾。
    try await Task.sleep(for: .milliseconds(120))
    let seen = await batches.all
    #expect(seen.count == 2)                       // REST 一次、归档一次
    #expect(seen.allSatisfy { !$0.isEmpty })
    // 两段拼起来就是最终结果：回调给的不是抽样，是真的那一段。
    // （测试里每天回的是同一个 zip，所以要按去重后的条数比。）
    #expect(OISource.dedup(seen.flatMap { $0 }).count == out.count)
  }

  @Test("只有一段：不回调，免得同一批点被画两遍")
  func singleHalfIsSilent() async throws {
    let pacer = StepPacer()
    let zip = Fixture.data("metrics-btcusdt-2025-01-15.zip")
    let now = Aggregator.utcMs(year: 2025, month: 2, day: 20)
    let server = FakeServer(pacer: pacer) { url in
      if url.host == "data.binance.vision" { return HTTPReply(status: 200, body: zip) }
      return json("[]")
    }
    let transport = FakeTransport(server)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = OISource(rest: BinanceREST(transport: transport, pacer: pacer), transport: transport,
                       store: OIStore(paths: Paths(root: dir)))
    let batches = Batches()
    // 整个窗口都在 30 天之外：只有归档那一段。
    let out = await src.rawPoints(symbol: "BTCUSDT", interval: .h1,
                                  from: now - 100 * 86_400_000, to: now - 40 * 86_400_000, now: now,
                                  onPartial: { points in Task { await batches.add(points) } })
    try await Task.sleep(for: .milliseconds(120))
    #expect(await batches.all.isEmpty)
    #expect(!out.isEmpty)
  }
}
