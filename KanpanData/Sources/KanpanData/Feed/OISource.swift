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
  /// 历史切块后同时在飞的块数。块本身已经是并发下载，再多只是抢同一条链路。
  public static let maxParallelChunks = 4
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
  /// `onPartial` 在两段中先到的那一段落地时调一次：并发不等于同时到，REST 那半秒
  /// 就回来的东西没有理由陪着归档一起等。只有真的分了两段才会调。
  public func rawPoints(symbol: String, interval: Interval, from: Int64, to: Int64,
                        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
                        onDay: (@Sendable (Int64, [OIPoint]) -> Void)? = nil,
                        onPartial: (@Sendable ([OIPoint]) -> Void)? = nil) async -> [OIPoint] {
    let cutoff = now - Self.restWindowMs
    // 两段谁也不等谁：① 近 30 天问币安 REST，② 更早的问网关归档。串着做等于把两次
    // 往返加起来，而它们各查各的、互不依赖——历史那段本来就是慢的那一段。
    let wantsRecent = to > cutoff, wantsHistory = from < cutoff
    // 只有一段时不必回调：那一段就是全部，调了等于让调用方把同一批点画两遍。
    let partial = wantsRecent && wantsHistory ? onPartial : nil
    async let recent: [OIPoint] = {
      guard wantsRecent else { return [] }
      let points = await restSegment(symbol: symbol, interval: interval, from: max(from, cutoff), to: to)
      if !points.isEmpty, !Task.isCancelled { partial?(points) }
      return points
    }()
    async let history: [OIPoint] = {
      guard wantsHistory else { return [] }
      let points = await historySegment(symbol: symbol, interval: interval,
                                        from: max(from, Self.archiveEpoch),
                                        to: min(to, cutoff), onDay: onDay)
      if !points.isEmpty, !Task.isCancelled { partial?(points) }
      return points
    }()
    let (early, late) = await (history, recent)
    guard !Task.isCancelled else { return [] }
    return Self.dedup(early + late)  // 接缝重叠时近期统计优先。
  }

  /// ① 近 30 天。取不到就是没有——OI 副图少一段总比整条空着强。
  private func restSegment(symbol: String, interval: Interval, from: Int64, to: Int64) async -> [OIPoint] {
    let period = interval.oiPeriod ?? (interval.stepMs >= 86_400_000 ? "1d" : "5m")
    do {
      return try await restRange(symbol: symbol, period: period, from: from, to: to)
    } catch {
      log("OI REST 失败：\(error)")
      return []
    }
  }

  /// ② 更早：先问网关（它自己存盘、自己聚合），网关不在才退回逐日归档。
  /// 网关一次只答这么长：不超过十年，且不超过两万根自己周期的柱子（5 分钟以下的
  /// 周期按 5 分钟算，归档本身就是五分钟一行）。和服务端同一个公式。
  ///
  /// 从前不切块：细周期看长区间会被网关以 400 顶回来，客户端把两个代理各试一遍
  /// 之后退回逐天下载几百个归档 zip。既慢，又慢得无声无息——所以宁可自己先切。
  static func historySpan(step: Int64) -> Int64 {
    min(3_660 * 86_400_000, 20_000 * max(step, 300_000))
  }

  /// 把 `[from, to]` 按上面的上限切成若干块。块与块在端点上重叠一瞬，交给 dedup。
  static func historyChunks(from: Int64, to: Int64, step: Int64) -> [(from: Int64, to: Int64)] {
    guard from <= to else { return [] }
    let span = historySpan(step: step)
    var out: [(from: Int64, to: Int64)] = []
    var start = from
    while true {
      let end = min(to, start + span)
      out.append((start, end))
      if end >= to { break }
      start = end
    }
    return out
  }

  private func historySegment(symbol: String, interval: Interval, from: Int64, to: Int64,
                              onDay: (@Sendable (Int64, [OIPoint]) -> Void)?) async -> [OIPoint] {
    guard from <= to else { return [] }
    let chunks = Self.historyChunks(from: from, to: to, step: interval.stepMs)
    guard chunks.count > 1 else {
      return await historyChunk(symbol: symbol, interval: interval, from: from, to: to, onDay: onDay)
    }
    log("OI 历史切成 \(chunks.count) 块（网关一次最多 \(Self.historySpan(step: interval.stepMs) / 86_400_000) 天）")
    var out: [OIPoint] = []
    await withTaskGroup(of: [OIPoint].self) { group in
      var next = 0
      func spawn() {
        guard next < chunks.count else { return }
        let chunk = chunks[next]
        next += 1
        group.addTask {
          await self.historyChunk(symbol: symbol, interval: interval,
                                  from: chunk.from, to: chunk.to, onDay: onDay)
        }
      }
      for _ in 0..<min(Self.maxParallelChunks, chunks.count) { spawn() }
      while let part = await group.next() {
        out += part
        spawn()
      }
    }
    return Self.dedup(out)
  }

  /// 一块历史：先问网关，网关不行才逐天下归档。回退是按块来的，一块失手不会把
  /// 已经从网关拿到的其它块也拖进逐天下载。
  private func historyChunk(symbol: String, interval: Interval, from: Int64, to: Int64,
                            onDay: (@Sendable (Int64, [OIPoint]) -> Void)?) async -> [OIPoint] {
    guard from <= to else { return [] }
    if let history = await gatewayHistory(symbol: symbol, interval: interval, from: from, to: to) {
      return history
    }
    return await archiveDays(symbol: symbol, days: OIArchive.days(from: from, to: to), onDay: onDay)
  }

  /// 这一轮真正要下的几段。
  ///
  /// 手里已经有的那段历史不会再变，没有理由跟着视野一起重下——往左拉就取左边露出来的
  /// 那截，60 秒续一次就只取尾巴（只有最后一两根桶的统计值还在动）。视野整段跳到别处、
  /// 和手里那段不沾边时不能只补一头，那会在中间留一个再也补不上的洞，所以整段重取。
  public static func missingSegments(have: (from: Int64, to: Int64)?, want: (from: Int64, to: Int64),
                                     step: Int64, refresh: Bool) -> [(from: Int64, to: Int64)] {
    guard want.to > want.from else { return [] }
    guard let have, have.to >= have.from, want.from <= have.to, want.to >= have.from else { return [want] }
    var out: [(from: Int64, to: Int64)] = []
    if want.from < have.from { out.append((want.from, min(have.from, want.to))) }
    if want.to > have.to { out.append((max(have.to, want.from), want.to)) }
    if refresh {
      let tail = (from: max(want.from, want.to - max(step, 60_000) * 3), to: want.to)
      if !out.contains(where: { $0.from <= tail.from && $0.to >= tail.to }) { out.append(tail) }
    }
    // 尾巴常常和右边露出来的那截叠在一起，叠了就并成一段，别发两次几乎一样的请求。
    return mergeSegments(out)
  }

  /// 排序、丢掉空段、把叠在一起或首尾相接的并成一段。
  /// 缺口段和端点段最后要一起进这道工序，否则会为同一截数据发两次几乎一样的请求。
  public static func mergeSegments(_ segments: [(from: Int64, to: Int64)]) -> [(from: Int64, to: Int64)] {
    var merged: [(from: Int64, to: Int64)] = []
    for segment in segments.filter({ $0.to > $0.from }).sorted(by: { $0.from < $1.from }) {
      if let last = merged.last, segment.from <= last.to {
        merged[merged.count - 1].to = max(last.to, segment.to)
      } else {
        merged.append(segment)
      }
    }
    return merged
  }

  /// 手里这串点自己断了没有——`missingSegments` 看不见的那种洞。
  ///
  /// 覆盖记账只有 `(from, to)` 一对端点（`MarketModel.oiRegion`，落盘成 `KOI2` 的
  /// from/to），这个模型**表达不了「区间内部有缺口」**：`missingSegments` 只比两个
  /// 端点，一旦某根桶漏在已有区间里面，它就再也不会被请求，跟着盘一起传到下一次
  /// 会话、下一个版本。`coveredRegion` 收敛右端只防**新**洞；已经落盘的**旧**洞得
  /// 靠这里——不看端点，直接扫点序列本身。
  ///
  /// 判定粒度按 OI 的真实粒度 `max(step, 5m)`（和 `chartSeries`、`OISeries.aligned`
  /// 同一套规矩）：1m / 3m 图的 OI 本来就只有 5 分钟一条，相邻两条差 5 分钟是数据
  /// 本来的样子，不是洞。1M / 1y 月长年长不等，靠 `nextBucket` 走日历，不做减法。
  ///
  /// 只扫近 30 天（`restWindowMs`）：这个窗口里 `openInterestHist` 是齐的，缺了就是
  /// 我们自己漏的，重问一次就补得回来；更早的历史段（归档 / 网关）本来就可能真的
  /// 没有那几天（上市前、归档站缺档），扫出来只会每次开图白发一轮永远填不上的请求。
  /// 会话接缝留下的洞必然在近期，这个窗口够用。
  ///
  /// 段数有上限：洞太碎就退化成「从第一个洞一直取到 want.to」一段，
  /// 宁可多取一截，也不发一串小请求去抢同一条链路。
  public static func holeSegments(points: [OIPoint], want: (from: Int64, to: Int64),
                                  interval: Interval, now: Int64,
                                  maxSegments: Int = 4) -> [(from: Int64, to: Int64)] {
    let granularity = max(300_000, interval.stepMs)
    let lower = max(want.from, now - restWindowMs)
    guard want.to > lower else { return [] }
    let inside = points.map(\.time).filter { $0 >= lower && $0 <= want.to }.sorted()
    guard inside.count > 1 else { return [] }

    var holes: [(from: Int64, to: Int64)] = []
    var previous = bucket(inside[0], interval: interval)
    for time in inside.dropFirst() {
      let current = bucket(time, interval: interval)
      guard current > previous else { continue }     // 同一根桶里的好几条（细周期的 5m 源）
      let expected = nextBucket(previous, interval: interval)
      if current > expected {
        // 端点各留一格余量：`rawPoints` 是闭区间 `[from, to]`，`restRange` 又是从 to
        // 往前翻页的，贴着桶头请求容易让那一根正好掉在页外。
        holes.append((from: expected - granularity, to: current + granularity))
      }
      previous = current
    }
    let merged = mergeSegments(holes)
    guard merged.count > maxSegments, let first = merged.first, let last = merged.last else { return merged }
    return [(from: first.from, to: max(want.to, last.to))]
  }

  /// OI 的桶头。和 `OISeries.aligned` 同一套规矩：5 分钟以上按图表周期的自然桶，
  /// 1m / 3m 按 5 分钟桶——数据本身就只有这个粒度。
  static func bucket(_ ms: Int64, interval: Interval) -> Int64 {
    Aggregator.bucketStart(ms: ms, interval: interval.stepMs >= 300_000 ? interval : .m5)
  }

  /// 下一根桶的桶头。1M / 1y 不等距，不能直接加一个固定 step（2 月只有 28 天，
  /// 加 30 天会跳过它）；往前挪一个半桶再落回自然边界就都对：一个半月一定落在
  /// 下个月里，一年半一定落在下一年里，等距周期上则恰好等于加一个 step。
  static func nextBucket(_ start: Int64, interval: Interval) -> Int64 {
    bucket(start + max(300_000, interval.stepMs) * 3 / 2, interval: interval)
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
      let page: [OIPoint]
      do {
        page = try await rest.openInterestHist(symbol: symbol, period: period, limit: 500, endTime: end)
      } catch {
        // 翻到第几页断了就用到第几页：已经到手的几页是好数据，为了更早的一页
        // 把它们一起丢掉，屏幕上就从「少一截」变成「整条没有」。
        if error is CancellationError || Task.isCancelled { throw error }
        log("OI REST 翻页中断：\(error)")
        break
      }
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

  /// 请求区间 → 这一轮真正覆盖到的区间。
  ///
  /// `loadOI` 为了把最后一根 K 线整根圈进来，会把 `want.to` 放到「最后一根开盘 +
  /// 2 × step」；而 `openInterestHist` 最新只答得到当前这根桶的开盘，那两根是未来，
  /// 谁也拿不到。把请求区间原样记成已有区间再落盘，下次开图（或后台待过两根桶再
  /// 回前台）就从这个虚高的右端往后补，中间那一根桶谁也不管——`OISeries.aligned`
  /// 又不肯拿前一根的持仓量往后顶，曲线上就永久留一个洞。所以右端只认「真到手的
  /// 最后一个点所在那根桶的末尾」。
  ///
  /// 左端不做同样的收敛：往左是历史，品种上市日之前本来就没有数据，收了左端等于
  /// 每平移一次就把上市前那一截重下一遍。
  ///
  /// 一个点都没拿到时不推进右端，退回 `want.from`（空区间），由调用方决定是保留
  /// 原有区间还是当作没有；总之不让区间倒过来。
  public static func coveredRegion(want: (from: Int64, to: Int64), points: [OIPoint],
                                   step: Int64) -> (from: Int64, to: Int64) {
    guard let last = points.max(by: { $0.time < $1.time })?.time else { return (want.from, want.from) }
    return (want.from, max(want.from, min(want.to, last + max(step, 1))))
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
