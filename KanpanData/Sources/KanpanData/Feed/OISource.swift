import Foundation
import KanpanCore

/// 持仓量：两个源，一条序列（§4.5）。
///
/// 近 30 天走 REST，更早走归档站的每日 metrics zip。只有 OI 副图打开时才取；
/// 缺口按天并发下（上限 8），先取视野中间再往两边扩，到一天画一天，不转菊花挡着图。
public actor OISource {
  /// REST 只回最近 30 天，更早的 `startTime` 直接报 `-1130`。
  public static let restWindowMs: Int64 = 30 * 86_400_000
  /// 归档站的并发上限。
  public static let maxParallelDays = 8
  /// BTCUSDT 的归档从这天起；更早是 404。别的品种从各自上市日起。
  public static let archiveEpoch: Int64 = 1_598_918_400_000   // 2020-09-01 UTC

  private let hosts: BinanceHosts
  private let rest: BinanceREST
  private let transport: HTTPTransport
  private let store: OIStore
  private let log: FeedLog

  public init(hosts: BinanceHosts = .default, rest: BinanceREST,
              transport: HTTPTransport = URLSessionTransport(),
              store: OIStore, log: FeedLog = .silent) {
    self.hosts = hosts
    self.rest = rest
    self.transport = transport
    self.store = store
    self.log = log
  }

  // ------------------------------------------------------------------ 取数

  /// `[from, to]` 的 OI 点。REST用原生period，网关历史已经按图表周期聚合。
  /// 网关不可用时才下载5m归档供本地回退，最终统一走chartSeries对齐。
  /// `onDay` 每下完一天调一次，面板用它走进度条、画已到的部分。
  public func rawPoints(symbol: String, interval: Interval, from: Int64, to: Int64,
                        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                        onDay: (@Sendable (Int64, [OIPoint]) -> Void)? = nil) async -> [OIPoint] {
    var all: [OIPoint] = []
    var recent: [OIPoint] = []
    let cutoff = now - Self.restWindowMs

    // ① 近 30 天：REST 一次拿完（500 条一页，往前翻）。
    if to > cutoff {
      let period = interval.oiPeriod ?? (interval.stepMs >= 86_400_000 ? "1d" : "5m")
      let start = max(from, cutoff)
      do {
        recent += try await restRange(symbol: symbol, period: period, from: start, to: to)
      } catch {
        log("OI REST 失败：\(error)")
      }
    }

    guard !Task.isCancelled else { return [] }
    // ② 更早：按天列缺口，先缓存后网络。
    if from < cutoff {
      let start = max(from, Self.archiveEpoch), end = min(to, cutoff)
      if let history = await gatewayHistory(symbol: symbol, interval: interval, from: start, to: end) {
        all += history
      } else {
        let days = OIArchive.days(from: start, to: end)
        all += await archiveDays(symbol: symbol, days: days, onDay: onDay)
      }
    }

    return Self.dedup(all + recent)  // 接缝重叠时近期统计优先。
  }

  /// 对齐到 K 线：每根取「不晚于这根开盘」的最近一条（原型 `oiAligned` 的规矩）。
  public func aligned(symbol: String, interval: Interval, series: BarSeries,
                      now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async -> [Double] {
    guard series.count > 0 else { return [] }
    let from = series.time(at: 0) - interval.stepMs
    let to = series.lastTime + interval.stepMs
    let raw = await rawPoints(symbol: symbol, interval: interval, from: from, to: to, now: now)
    return Self.chartSeries(raw, interval: interval).aligned(to: series)
  }

  // ------------------------------------------------------------------ REST

  private func restRange(symbol: String, period: String, from: Int64, to: Int64) async throws -> [OIPoint] {
    var out: [OIPoint] = []
    var end = to
    // 500 条一页，最多翻 20 页（30 天 × 5m = 8640 条）。
    for _ in 0..<20 {
      try Task.checkCancellation()
      let page = try await rest.openInterestHist(symbol: symbol, period: period, limit: 500, endTime: end)
      try Task.checkCancellation()
      guard let first = page.first else { break }
      out += page
      if page.count < 500 || first.time <= from { break }
      end = first.time - 1
    }
    return out.filter { $0.time >= from && $0.time <= to }
  }

  // ------------------------------------------------------------------ 归档

  /// 正常路径：服务器解析ZIP并按请求周期聚合，手机不搬运多年原始5m数组。
  private func gatewayHistory(symbol: String, interval: Interval, from: Int64, to: Int64) async -> [OIPoint]? {
    guard from <= to else { return nil }
    for proxy in hosts.oiProxies {
      guard !Task.isCancelled else { return nil }
      guard var url = URLComponents(string: "https://\(proxy)/oi/v1/metrics/\(symbol)/range") else { continue }
      url.queryItems = [URLQueryItem(name: "interval", value: interval.rawValue),
                       URLQueryItem(name: "from", value: String(from)), URLQueryItem(name: "to", value: String(to))]
      guard let target = url.url else { continue }
      do {
        let response = try await transport.get(target, timeout: 45)
        if response.status == 200 { return try Self.decodeGateway(response.body) }
      } catch { if Task.isCancelled { return nil } }
    }
    return nil
  }

  private func archiveDays(symbol: String, days: [Int64],
                           onDay: (@Sendable (Int64, [OIPoint]) -> Void)?) async -> [OIPoint] {
    var out: [OIPoint] = []
    var missing: [Int64] = []
    for d in days {
      if let hit = await store.load(symbol: symbol, dayStart: d) {
        out += hit
        onDay?(d, hit)
      } else {
        missing.append(d)
      }
    }
    guard !missing.isEmpty else { return out }
    log("OI 归档缺 \(missing.count) 天，并发 \(Self.maxParallelDays) 下载")

    let order = OIArchive.centerOut(missing)
    let hosts = self.hosts
    let transport = self.transport
    let log = self.log
    var results: [[OIPoint]] = []
    await withTaskGroup(of: (Int64, [OIPoint]).self) { group in
      var next = 0
      func spawn() {
        guard next < order.count else { return }
        let day = order[next]
        next += 1
        group.addTask {
          let url = hosts.metricsZip(symbol: symbol, day: OIArchive.dayString(day))
          do {
            for proxy in hosts.oiProxies {
              guard !Task.isCancelled else { return (day, []) }
              if let proxyURL = URL(string: "https://\(proxy)/oi/v1/metrics/\(symbol)/\(OIArchive.dayString(day)).json"),
                 let reply = try? await transport.get(proxyURL, timeout: 6), reply.status == 200,
                 let points = try? Self.decodeGateway(reply.body) {
                return (day, points)
              }
            }
            let reply = try await transport.get(url, timeout: 20)
            if reply.status == 404 { return (day, []) }      // 上市前 / 还没归档，不是错误
            guard reply.status == 200 else { return (day, []) }
            return (day, try OIArchive.parseZip(reply.body))
          } catch {
            log("OI 归档 \(OIArchive.dayString(day)) 失败：\(error)")
            return (day, [])
          }
        }
      }
      for _ in 0..<min(Self.maxParallelDays, order.count) { spawn() }
      while let (day, pts) = await group.next() {
        if !pts.isEmpty { await store.save(symbol: symbol, dayStart: day, points: pts) }
        onDay?(day, pts)
        results.append(pts)
        spawn()
      }
    }
    for r in results { out += r }
    return out
  }

  /// Gateway returns real timestamps, including archives older than the REST window.
  public static func decodeGateway(_ data: Data) throws -> [OIPoint] {
    let rows = try JSONDecoder().decode([[Double]].self, from: data)
    guard rows.allSatisfy({ $0.count == 2 && $0[0].isFinite && $0[0] > 0
      && $0[0] < Double(Int64.max) && $0[1].isFinite && $0[1] >= 0 }) else {
      throw FeedError.badResponse("历史OI响应不完整")
    }
    return dedup(rows.map { OIPoint(time: Int64($0[0]), value: $0[1]) })
  }

  // ------------------------------------------------------------------ 纯函数

  /// 按时间排序去重，同一时刻留后来的。
  public static func dedup(_ pts: [OIPoint]) -> [OIPoint] {
    guard pts.count > 1 else { return pts }
    var m: [Int64: OIPoint] = [:]
    m.reserveCapacity(pts.count)
    for p in pts { m[p.time] = p }
    return m.keys.sorted().map { m[$0]! }
  }

  /// App 与查询入口共用这条管线，不能将原始5m归档直接交给高周期图表。
  public static func chartSeries(_ raw: [OIPoint], interval: Interval) -> OISeries {
    OISeries(points: downsample(dedup(raw), to: interval),
             step: max(300_000, interval.stepMs), bucketInterval: interval)
  }

  /// 降采样到周期：每桶取最后一条，时间戳打在桶头上。
  /// 1m / 3m 比 5m 还细，原样返回——相邻几根共用一个值，这是数据本身的粒度。
  public static func downsample(_ pts: [OIPoint], to interval: Interval) -> [OIPoint] {
    guard interval.stepMs > 5 * 60_000 || interval == .m5 else { return pts }
    guard !pts.isEmpty else { return [] }
    var out: [OIPoint] = []
    var cur: OIPoint? = nil
    var curBucket: Int64 = .min
    for p in pts.sorted(by: { $0.time < $1.time }) {
      let b = Aggregator.bucketStart(ms: p.time, interval: interval)
      if b != curBucket {
        if var c = cur { c.time = curBucket; out.append(c) }
        curBucket = b
      }
      cur = p
    }
    if var c = cur { c.time = curBucket; out.append(c) }
    return out
  }

  /// 每根 K 线取「不晚于这根开盘」的最近一条，没有就留 NaN。
  /// 点列有缺口或周期不等距时也对得上（原型那份是等距序列的 floor 下标，等价）。
  public static func align(_ pts: [OIPoint], to series: BarSeries) -> [Double] {
    var out = [Double](repeating: .nan, count: series.count)
    guard !pts.isEmpty, series.count > 0 else { return out }
    var j = 0
    for i in 0..<series.count {
      let t = series.time(at: i)
      while j + 1 < pts.count, pts[j + 1].time <= t { j += 1 }
      if pts[j].time <= t { out[i] = pts[j].value }
    }
    return out
  }
}
