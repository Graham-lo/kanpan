import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
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

  @Test(".oi 日切片：编解码一致，保留四个比率列")
  func sliceCodec() throws {
    let pts = try OIArchive.parseZip(Fixture.data("metrics-btcusdt-2025-01-15.zip"))
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let blob = OIArchive.encodeSlice(pts, dayStartMs: day)
    #expect(blob.count == 16 + pts.count * 44)
    #expect(OIArchive.decodeSlice(blob) == pts)
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
        return json("[[\(day),120,null,null,null,null]]")
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

  @Test("网关那一台不行换下一台时，失败原因进日志而不是被吞掉")
  func gatewayFailureIsLogged() async throws {
    let day = Aggregator.utcMs(year: 2021, month: 12, day: 1)
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 15)
    let server = FakeServer { url in
      if url.host == "gateway.example" { return HTTPReply(status: 503) }
      if url.host == "backup.example", url.path.hasSuffix("/range") {
        return json("[[\(day),120,null,null,null,null]]")
      }
      return HTTPReply(status: 500)
    }
    let transport = FakeTransport(server)
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let lines = LogLines()
    let source = OISource(hosts: BinanceHosts(oiProxy: "gateway.example", oiProxyFallbacks: ["backup.example"]),
      rest: BinanceREST(transport: transport), transport: transport,
      store: OIStore(paths: Paths(root: dir)), log: FeedLog { lines.append($0) })
    let result = await source.rawPoints(symbol: "BTCUSDT", interval: .h4,
      from: day, to: day + 86_399_999, now: now)
    #expect(result == [.init(time: day, value: 120)])
    #expect(lines.all.contains { $0.contains("gateway.example") && $0.contains("503") })
  }

  @Test("取数失败归类：限流、地域拒绝、上游状态码、响应解不开、超时")
  func classifiesFailures() {
    #expect(OISource.classify(UpstreamError(status: 429)) == "限流")
    #expect(OISource.classify(UpstreamError(status: 451)) == "地域拒绝")
    #expect(OISource.classify(UpstreamError(status: 502)) == "上游 502")
    #expect(OISource.classify(FeedError.badResponse("x")) == "响应解不开")
    #expect(OISource.classify(URLError(.timedOut)) == "超时")
    #expect(OISource.classify(URLError(.notConnectedToInternet)).hasPrefix("网络"))
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

  // -------------------------------------------------- 区间内部的洞（端点看不见的那种）

  /// `now` 取一个固定值，所有用例都在它的近 30 天窗口里摆点，免得跟着真实时间漂。
  private static let now = Aggregator.utcMs(year: 2025, month: 1, day: 15)

  @Test("旧盘里的洞：端点法看不见，扫点序列才扫得出来")
  func holeInsideRegionIsInvisibleToEndpoints() throws {
    let step = Self.step, now = Self.now
    let first = now - 20 * step
    // 桶 3 被旧版本漏掉了：它落在已有区间**内部**，右端还虚高了两根。
    var times = (0...11).map { first + Int64($0) * step }
    times.remove(at: 3)
    let pts = times.map { OIPoint(time: $0, value: 1_000) }
    let have = (from: first, to: first + 13 * step)          // 盘上记的虚高右端
    let want = (from: first, to: first + 13 * step)

    // 端点法：区间全在手里，一个请求都不发——洞就这么被带进下一次会话。
    #expect(OISource.missingSegments(have: have, want: want, step: step, refresh: false).isEmpty)

    let holes = OISource.holeSegments(points: pts, want: want, interval: .h1, now: now)
    let hole = try #require(holes.first)
    #expect(holes.count == 1)
    #expect(hole.from <= first + 3 * step)                   // 端点要真的把桶 3 圈进去
    #expect(hole.to >= first + 3 * step)
  }

  @Test("1m 图上 OI 本来就是 5 分钟一条：正常间隔不许当成洞")
  func minuteChartKeepsFiveMinuteCadence() {
    let now = Self.now
    let first = now - 100 * 300_000
    let pts = (0...100).map { OIPoint(time: first + Int64($0) * 300_000, value: 1_000) }
    let want = (from: first, to: now)
    #expect(OISource.holeSegments(points: pts, want: want, interval: .m1, now: now).isEmpty)
    #expect(OISource.holeSegments(points: pts, want: want, interval: .m3, now: now).isEmpty)
    // 同一串点在 5m 图上也是齐的；真缺一根才扫得出来。
    #expect(OISource.holeSegments(points: pts, want: want, interval: .m5, now: now).isEmpty)
    var holed = pts; holed.remove(at: 50)
    #expect(OISource.holeSegments(points: holed, want: want, interval: .m5, now: now).count == 1)
  }

  @Test("30 天以外的洞：不扫，别为归档站本来就没有的那几天每次开图白发请求")
  func oldHolesAreLeftAlone() {
    let step: Int64 = 86_400_000, now = Self.now
    let first = now - 90 * step
    var times = (0...80).map { first + Int64($0) * step }
    times.remove(at: 10)                                     // 90 天前那一天，归档站可能真没有
    let pts = times.map { OIPoint(time: $0, value: 1_000) }
    let want = (from: first, to: now)
    #expect(OISource.holeSegments(points: pts, want: want, interval: .d1, now: now).isEmpty)
    // 同样一个洞挪进近 30 天：那就是我们自己漏的，要补。
    var recent = (0...80).map { first + Int64($0) * step }
    recent.remove(at: 70)                                    // now - 20 天
    let inWindow = recent.map { OIPoint(time: $0, value: 1_000) }
    #expect(OISource.holeSegments(points: inWindow, want: want, interval: .d1, now: now).count == 1)
  }

  @Test("两个挨着的洞并成一段；洞太碎就退化成一整段，不发一串小请求")
  func holesMergeAndDegrade() throws {
    let step = Self.step, now = Self.now
    let first = now - 60 * step
    let want = (from: first, to: now)
    // 相邻的两个洞（中间只隔一根）：并成一段。
    var times = (0...59).map { first + Int64($0) * step }
    times.removeAll { $0 == first + 10 * step || $0 == first + 12 * step }
    let near = times.map { OIPoint(time: $0, value: 1_000) }
    #expect(OISource.holeSegments(points: near, want: want, interval: .h1, now: now).count == 1)
    // 五个散落的洞，上限 4：退化成从第一个洞一直取到 want.to 的一段。
    var many = (0...59).map { first + Int64($0) * step }
    let gone: Set<Int64> = [5, 15, 25, 35, 45].reduce(into: []) { $0.insert(first + $1 * step) }
    many.removeAll { gone.contains($0) }
    let scattered = OISource.holeSegments(points: many.map { OIPoint(time: $0, value: 1_000) },
                                          want: want, interval: .h1, now: now)
    try #require(scattered.count == 1)
    #expect(scattered[0].from <= first + 5 * step)
    #expect(scattered[0].to >= want.to)
  }

  @Test("洞段和端点段一起并：同一截数据不发两次请求")
  func holeAndEdgeSegmentsMerge() throws {
    let step = Self.step, now = Self.now
    let first = now - 20 * step
    var times = (0...11).map { first + Int64($0) * step }
    times.remove(at: 10)                                     // 洞紧挨着右端露出来的那截
    let pts = times.map { OIPoint(time: $0, value: 1_000) }
    let have = OISource.coveredRegion(want: (from: first, to: first + 13 * step), points: pts, step: step)
    let want = (from: first, to: first + 15 * step)
    let edges = OISource.missingSegments(have: have, want: want, step: step, refresh: false)
    let holes = OISource.holeSegments(points: pts, want: want, interval: .h1, now: now)
    let merged = OISource.mergeSegments(edges + holes)
    #expect(merged.count == 1)
    let all = try #require(merged.first)
    #expect(all.from <= first + 10 * step)                   // 洞在里面
    #expect(all.to >= want.to)                               // 右边那截也在里面
  }

  @Test("1M / 1y 月长年长不等：连着的两根不许当成洞")
  func calendarIntervalsHaveNoFakeHoles() {
    // 12 个自然月的桶头，一根不缺。月是 30 天的名义 step，2 月只有 28 天——
    // 拿 step 做减法就会把 1 月→2 月判成「隔了一根」。
    let months = (1...12).map { OIPoint(time: Aggregator.utcMs(year: 2024, month: $0, day: 1), value: 1_000) }
    let now = Aggregator.utcMs(year: 2025, month: 1, day: 1)
    // 月线的近 30 天窗口只装得下最后一两根桶，这里只要求「不误报」。
    #expect(OISource.holeSegments(points: months, want: (from: months[0].time, to: now),
                                  interval: .mo1, now: now).isEmpty)
    #expect(OISource.nextBucket(Aggregator.utcMs(year: 2024, month: 1, day: 1), interval: .mo1)
            == Aggregator.utcMs(year: 2024, month: 2, day: 1))
    #expect(OISource.nextBucket(Aggregator.utcMs(year: 2024, month: 1, day: 1), interval: .y1)
            == Aggregator.utcMs(year: 2025, month: 1, day: 1))
  }

  @Test("点不够 / 窗口退化：不扫出任何段")
  func holeDegenerate() {
    let now = Self.now
    #expect(OISource.holeSegments(points: [], want: (now - 10 * Self.step, now), interval: .h1, now: now).isEmpty)
    let one = [OIPoint(time: now - Self.step, value: 1)]
    #expect(OISource.holeSegments(points: one, want: (now - 10 * Self.step, now), interval: .h1, now: now).isEmpty)
    #expect(OISource.holeSegments(points: one, want: (now, now), interval: .h1, now: now).isEmpty)
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

  @Test("坏盘面：不是 KOI4 / 被截断 / 区间倒着，一律当没有")
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

  /// `onPartial` 是在 `rawPoints` 里的两个 `async let` 里**同步**调的，两者都在
  /// `rawPoints` 返回之前收尾，所以回调里当场记下就够了，返回时一定已经记全。
  /// 原来这里是个 actor、回调里再 `Task { await batches.add(...) }` 跳一次，测试只好
  /// `sleep(120ms)` 去猜那几个 Task 跑完没有——整包并行跑、机器被占满时 120ms 根本
  /// 轮不到它们，就读成「一次都没回调」。
  private final class Batches: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[OIPoint]] = []
    func add(_ points: [OIPoint]) { lock.lock(); items.append(points); lock.unlock() }
    var all: [[OIPoint]] { lock.lock(); defer { lock.unlock() }; return items }
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
                                  onPartial: { points in batches.add(points) })
    let seen = batches.all
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
                                  onPartial: { points in batches.add(points) })
    #expect(batches.all.isEmpty)
    #expect(!out.isEmpty)
  }
}

@Suite("OI 覆盖记账：只有真问到的那一段才算覆盖")
struct OICoverageTests {

  private static let step: Int64 = 3_600_000
  private static let day: Int64 = 86_400_000

  /// 覆盖记账只有一对端点（`MarketModel.oiRegion`，落盘成 `KOI2` 的 from/to）。
  /// 请求失败时把 `want.from` 记成已有，那一截就永远补不回来：`missingSegments`
  /// 只比端点，`holeSegments` 又只看得见**点与点之间**的洞。
  @Test("左边那截整段失败：记账一步都不推进，下一轮还会再问它")
  func aFailedSegmentIsNotCoverage() throws {
    let step = Self.step
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 19)
    // 会话一：右边这 10 根真拿到了，落盘的区间就是它。
    let have = (from: now - 10 * step, to: now)
    let points = (0...10).map { OIPoint(time: now - Int64(10 - $0) * step, value: 100) }
    // 用户往左拖，想要更早的 20 根。
    let want = (from: now - 30 * step, to: now + 2 * step)
    let left = try #require(OISource.missingSegments(have: have, want: want, step: step,
                                                     refresh: false).first)
    #expect(left.from == want.from)
    // 这一段整段没问到（网络错 / 451 / 网关超时 / 归档站给不出）。
    let failed = OIFetch(want: left, points: [], complete: false)
    #expect(OISource.coveredRegion(of: [failed], step: step) == nil)
    // `mergeOI` 拿到 nil 就一步都不推进，记账还是老样子 → 下一轮照样认得出缺这一截。
    let again = OISource.missingSegments(have: have, want: want, step: step, refresh: false)
    #expect(again.contains { $0.from == want.from })
    // 另一条路救不了它：缺的是第一个点**之前**那一截，扫点序列只看得见点与点之间的洞。
    #expect(OISource.holeSegments(points: points, want: want, interval: .h1, now: now).isEmpty)
  }

  /// 「问到了、但这几天本来就没有」不是失败：上市前那一截收进覆盖，
  /// 否则每平移一次就把它重下一遍。
  @Test("问到了却是空的：照样算覆盖，不会每平移一次重下一遍")
  func anAnsweredEmptySegmentIsStillCoverage() throws {
    let step = Self.step
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 19)
    let have = (from: now - 10 * step, to: now)
    let want = (from: now - 30 * step, to: now + 2 * step)
    let left = try #require(OISource.missingSegments(have: have, want: want, step: step,
                                                     refresh: false).first)
    let answered = OIFetch(want: left, points: [], complete: true)
    let span = try #require(OISource.coveredRegion(of: [answered], step: step))
    #expect(span.from == want.from)
    let region = (from: min(have.from, span.from), to: max(have.to, span.to))
    #expect(!OISource.missingSegments(have: region, want: (want.from, have.to), step: step,
                                      refresh: false).contains { $0.from == want.from })
  }

  /// 右端仍然只认真到手的点：`want.to` 伸到最后一根 K 线之后两根，那两根还没发生。
  @Test("几段合起来：失败的那段不算，右端只认真到手的点")
  func mixedSegmentsOnlyCountTheAnsweredOnes() throws {
    let step = Self.step
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 19)
    let left = (from: now - 30 * step, to: now - 10 * step)
    let right = (from: now - 10 * step, to: now + 2 * step)
    let got = (0...10).map { OIPoint(time: now - Int64(10 - $0) * step, value: 100) }
    let span = try #require(OISource.coveredRegion(
      of: [OIFetch(want: left, points: [], complete: false),
           OIFetch(want: right, points: got, complete: true)], step: step))
    #expect(span.from == right.from)          // 失败的左边那段没被收进去
    #expect(span.to == now + step)            // 未来那两根没发生，右端停在最后一个点之后一格
    #expect(OISource.coveredRegion(of: [], step: step) == nil)
  }

  // ---------------------------------------------------------------- 到线上那一头

  private static func source(_ handler: @escaping @Sendable (URL) -> HTTPReply,
                             dir: URL) -> OISource {
    let pacer = StepPacer()
    let transport = FakeTransport(FakeServer(pacer: pacer, handler: handler))
    return OISource(rest: BinanceREST(transport: transport, pacer: pacer), transport: transport,
                    store: OIStore(paths: Paths(root: dir)))
  }

  @Test("REST 整段报错：点是空的，而且说清楚「没问到」")
  func restFailureIsReported() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let src = Self.source({ _ in HTTPReply(status: 500) }, dir: dir)
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 19)
    let got = await src.fetch(symbol: "BTCUSDT", interval: .h1,
                              from: now - 5 * Self.step, to: now, now: now)
    #expect(got.points.isEmpty)
    #expect(!got.complete)
    #expect(OISource.coveredRegion(of: [got], step: Self.step) == nil)
  }

  @Test("REST 翻到一半断了：到手的几页留住，但这一段仍然不算问全")
  func partialPagesAreNotFullCoverage() async throws {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
    defer { try? FileManager.default.removeItem(at: dir) }
    let now = Aggregator.utcMs(year: 2026, month: 2, day: 20)
    let src = Self.source({ url in
      guard url.path == "/futures/data/openInterestHist" else { return HTTPReply(status: 404) }
      let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
      let endTime = q.first { $0.name == "endTime" }?.value.flatMap { Int64($0) }
      guard endTime == now else { return HTTPReply(status: 500) }   // 更早的那一页断掉
      let rows = (0..<500).map { i -> String in
        let t = now - Int64(499 - i) * 3_600_000
        return #"{"symbol":"BTCUSDT","sumOpenInterest":"50.0","sumOpenInterestValue":"1","timestamp":\#(t)}"#
      }
      return json("[" + rows.joined(separator: ",") + "]")
    }, dir: dir)
    let got = await src.fetch(symbol: "BTCUSDT", interval: .h1,
                              from: now - 29 * Self.day, to: now, now: now)
    #expect(got.points.count == 500)      // 到手的留住
    #expect(!got.complete)                // 但少的那一截下一轮还要问
  }

  @Test("归档站 404 是答复（上市前），别的状态码不是")
  func archiveAnswers() async throws {
    let now = Aggregator.utcMs(year: 2026, month: 9, day: 19)
    let window = (from: now - 100 * Self.day, to: now - 40 * Self.day)
    for (status, complete) in [(404, true), (503, false)] {
      let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("oi-\(UUID())")
      defer { try? FileManager.default.removeItem(at: dir) }
      let src = Self.source({ url in
        url.host == "data.binance.vision" ? HTTPReply(status: status) : HTTPReply(status: 500)
      }, dir: dir)
      let got = await src.fetch(symbol: "NEWUSDT", interval: .h1,
                                from: window.from, to: window.to, now: now)
      #expect(got.points.isEmpty)
      #expect(got.complete == complete)
      // 404 那一路算覆盖（上市前那一截不必每次重下），503 那一路一点都不算。
      #expect((OISource.coveredRegion(of: [got], step: Self.step) != nil) == complete)
    }
  }
}

/// 收日志用。`FeedLog` 的闭包是 `@Sendable` 的，所以要一把锁。
private final class LogLines: @unchecked Sendable {
  private let lock = NSLock()
  private var lines: [String] = []
  func append(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
}
