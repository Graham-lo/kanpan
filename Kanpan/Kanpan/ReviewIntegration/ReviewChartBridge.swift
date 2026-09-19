import Foundation
import Observation
import KanpanCore
import KanpanChart
import KanpanData
import ReviewDomain
import ReviewUI

@MainActor @Observable final class ReviewChartBridge {
  enum Mode: String { case live, capture, replay }
  var mode: Mode = .live
  var state: ChartState?
  var proxy = ChartProxy()
  var loading = false
  var playing = false
  /// 此刻的回放倍速（1 / 2 / 4）。
  ///
  /// **倍速是人的习惯，不是这条记录的属性。** 以前它从 `ReviewReplayPosition` 里读
  /// （每条记录各存一份），于是调到 4× 点「退出」再进同一条记录回 1×，换一条记录
  /// 也回 1×——那颗按钮改的东西没有一条路径留得住。现在初值从偏好来
  /// （`Prefs.replaySpeed`，随账号同步），改一下就写回去；游标位置仍按记录存，
  /// 那个是这条记录自己的属性，没跟着一起动。
  var speed = 1
  /// 偏好里那一份倍速。宿主接上（见 `MainScreen.wireReview`）。
  @ObservationIgnored var preferredSpeed: () -> Int = { 1 }
  /// 倍速改了，写回偏好。宿主接上。
  @ObservationIgnored var onSpeedChange: (Int) -> Void = { _ in }
  var cursor = 0
  var replayRecord: ReviewRecord?
  var notice: String?
  private var bars: [Bar] = []
  private var replayBase: ChartState?
  private var playback: Task<Void, Never>?
  private var loadTask: Task<Void, Never>?
  private var loadID = UUID()
  private var replayLimit = Int64.max
  private var replayHosts: BinanceHosts?
  private var pageTask: Task<Void, Never>?
  private var paging = false
  var active: Bool { mode != .live }
  var lastPrice: Double? { state?.series.close.last }
  var replayTime: Int64 { state?.series.lastTime ?? 0 }

  /// 复盘那份老档案（并入看盘之前的位置）在哪。只剩 `AppAccountBridge.migrateLegacy`
  /// 一个读者：把它搬进访客档案。
  ///
  /// 测试子目录这条岔路原来只看一个 `KANPAN_PERSISTENCE_PROFILE`——不要求测试模式、
  /// 不要求它是个 UUID，原样拼进路径。于是 Release 包里一串环境变量就能把复盘档案的
  /// 位置挪走，而 `../` 这类片段还能把它挪出 `kanpan-review` 之外。现在三道闸一起上：
  /// `#if DEBUG`、`KANPAN_TEST_PROFILE=1`、以及**必须是一个合法 UUID**——
  /// UUID 这一条顺手把所有路径片段（`..`、`/`、`%2e%2e`）都挡在外面，口径和
  /// `AppAccountBridge` / `PrefsStore.deviceStorage()` 对齐。
  static func storageDirectory() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("kanpan-review")
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let test = env["KANPAN_PERSISTENCE_PROFILE"],
       let uuid = UUID(uuidString: test) {
      return root.appendingPathComponent("tests/" + uuid.uuidString)
    }
    #endif
    return root
  }
  static func closeTime(_ time: Int64, interval: Interval) -> Int64 {
    guard interval.isIrregular else { return time + interval.stepMs }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: Double(time) / 1000)
    return Int64((calendar.date(byAdding: interval == .y1 ? .year : .month, value: 1, to: date)?.timeIntervalSince1970 ?? date.timeIntervalSince1970) * 1000)
  }
  static func shifted(_ time: Int64, interval: Interval, bars: Int) -> Int64 {
    guard interval.isIrregular else { return max(0, time + Int64(bars) * interval.stepMs) }
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let date = Date(timeIntervalSince1970: Double(time) / 1000)
    return Int64((calendar.date(byAdding: interval == .y1 ? .year : .month, value: bars, to: date)?.timeIntervalSince1970 ?? date.timeIntervalSince1970) * 1000)
  }
  func beginCapture(feature: ReviewFeature, live: ChartState?, prefs: Prefs, source: MarketSource = .binance) {
    guard var live, live.series.count >= 3 else { notice = "等待 K 线加载后再记录"; return }
    guard live.series.interval != .y1 else { notice = "年线暂不支持复盘，请切换周期"; return }
    playing = false; playback?.cancel(); loadTask?.cancel()
    let s = live.series, now = ReviewClock.now
    let closed = (0..<s.count).filter { Self.closeTime(s.time(at: $0), interval: s.interval) <= now }
    guard let last = closed.last, closed.count >= 3 else { notice = "至少需要 3 根已收盘 K 线"; return }
    live.series = slice(s, count: last + 1); live.crosshair = nil; live.nowMs = nil
    var draft: ReviewDraft
    if let saved = feature.draft, saved.range.venue == source.rawValue, saved.range.symbol == s.symbol, saved.range.interval == s.interval.rawValue {
      draft = saved
    } else {
      let right = min(last, s.index(atTime: live.view.to)), left = max(0, right - 48)
      draft = ReviewDraft(range: ReviewRange(venue: source.rawValue, symbol: s.symbol, interval: s.interval.rawValue,
        start: s.time(at: left), end: Self.closeTime(s.time(at: right), interval: s.interval), bars: right - left + 1),
        reference: s.close.last ?? s.close[last], high: s.high[left...right].max() ?? 0,
        low: s.low[left...right].min() ?? 0, now: now)
      draft.chartSettings = try? PersonalSyncCodec.snapshot(prefs)
      draft.drawingSnapshot = try? JSONEncoder().encode(live.drawings)
    }
    proxy = ChartProxy(); state = live; mode = .capture; feature.begin(draft)
  }
  func endCapture(feature: ReviewFeature) {
    feature.saveDraft(); feature.captureOpen = false; mode = .live; state = nil; proxy = ChartProxy()
  }
  func open(_ record: ReviewRecord, feature: ReviewFeature, live: ChartState?, hosts: BinanceHosts, cutoff: Int64? = nil) {
    guard let interval = Interval(rawValue: record.draft.range.interval), MarketSource(rawValue: record.draft.range.venue) != nil, record.draft.range.market == "usd_m" else { notice = "这个市场暂未接入原生行情"; return }
    guard var base = live else { notice = "等待行情加载"; return }
    playback?.cancel(); playing = false; loadTask?.cancel(); pageTask?.cancel(); paging = false; loading = true
    replayHosts = hosts
    let request = UUID(); loadID = request
    replayLimit = cutoff ?? ReviewClock.now
    let range = record.draft.range
    let savedPosition = feature.savedReplay(record.id)?.cursor ?? range.end
    let initialAnchor = min(replayLimit, max(range.end, savedPosition))
    let windowStart = Self.shifted(initialAnchor == range.end ? range.start : initialAnchor, interval: interval, bars: -300)
    let end = min(replayLimit, Self.shifted(initialAnchor, interval: interval, bars: 300))
    if let data = record.draft.chartSettings, let prefs = try? PersonalSyncCodec.snapshotPrefs(data) {
      base.style = prefs.style; base.options = prefs.chartOptions; base.params = prefs.params
      base.overlays = prefs.overlays; base.subs = prefs.subs.filter { $0 != .oi }
      base.indicatorColors = prefs.indicatorColors; base.hiddenOutputs = prefs.hiddenOutputs
      base.price = PriceTransform(mode: prefs.priceMode)
    }
    // No live OI or later annotations may enter the replay indicator engine.
    base.oi = nil; base.subs.removeAll { $0 == .oi }; base.drawings = []
    base.crosshair = nil; base.nowMs = nil
    loadTask = Task {
      do {
        let rest = BinanceREST.upstream(MarketSource(rawValue: range.venue)!, hosts: hosts)
        var start = windowStart
        var fetched: [Bar] = []
        while start < end {
          try Task.checkCancellation()
          let page = try await rest.klines(symbol: range.symbol, interval: interval, limit: 1500, startTime: start, endTime: end - 1)
          guard let last = page.last else { break }
          fetched.append(contentsOf: page)
          let next = Self.closeTime(last.openTime, interval: interval.source)
          guard next > start else { break }; start = next
          guard fetched.count <= 6000 else { throw ReviewBridgeError.rangeTooLarge }
        }
        try Task.checkCancellation(); guard loadID == request else { return }
        let series = BinanceREST.series(symbol: range.symbol, interval: interval, bars: fetched)
        let ordered = (0..<series.count).filter { Self.closeTime(series.time(at: $0), interval: interval) <= end }.map {
          Bar(openTime: series.time(at: $0), open: series.open[$0], high: series.high[$0], low: series.low[$0], close: series.close[$0], volume: series.volume[$0])
        }
        guard ordered.count >= 3 else { throw ReviewBridgeError.noHistory }
        for i in 1..<ordered.count where Self.closeTime(ordered[i - 1].openTime, interval: interval) != ordered[i].openTime { throw ReviewBridgeError.historyGap }
        bars = ordered
        base.series = BarSeries(symbol: range.symbol, interval: interval, bars: ordered)
        base.symbol = SymbolInfo(symbol: range.symbol, base: String(range.symbol.dropLast(4)), pricePrecision: base.decimals, tickSize: pow(10, -Double(base.decimals)))
        replayBase = base; replayRecord = record; speed = preferredSpeed()
        let saved = savedPosition
        cursor = max(2, ordered.lastIndex(where: { Self.closeTime($0.openTime, interval: interval) <= saved }) ?? 2)
        proxy = ChartProxy(); mode = .replay; updateReplay(feature: feature); loading = false
      } catch is CancellationError {} catch { if loadID == request { loading = false; notice = error.localizedDescription } }
    }
  }
  func openMatch(_ match: ReviewMatch, cutoff: Int64, feature: ReviewFeature, live: ChartState?, hosts: BinanceHosts) {
    var draft = ReviewDraft(range: match.range, reference: 1, high: 1, low: 1, now: cutoff)
    draft.rule.expires = cutoff
    open(ReviewRecord(draft: draft), feature: feature, live: live, hosts: hosts, cutoff: cutoff)
  }
  /// 回放条上那颗倍速按钮：1× → 2× → 4× → 1×。写回偏好，跟着人走。
  func cycleSpeed() {
    speed = speed == 4 ? 1 : speed * 2
    onSpeedChange(speed)
  }
  func step(_ amount: Int, feature: ReviewFeature) {
    if amount > 0 && cursor >= bars.count - 2 { loadReplayPage(forward: true, feature: feature) }
    if amount < 0 && cursor <= 2 { loadReplayPage(forward: false, feature: feature) }
    cursor = min(max(2, cursor + amount), max(2, bars.count - 1)); updateReplay(feature: feature)
    if cursor >= bars.count - 1 && !paging { playing = false; playback?.cancel() }
  }
  func togglePlay(feature: ReviewFeature) {
    playing.toggle(); playback?.cancel()
    guard playing else { return }
    playback = Task {
      while !Task.isCancelled && playing {
        do { try await Task.sleep(for: .milliseconds(1000 / max(1, speed))) } catch { return }
        step(1, feature: feature)
      }
    }
  }
  func loadReplayPage(forward: Bool, feature: ReviewFeature) {
    guard !paging, let hosts = replayHosts, let record = replayRecord, let base = replayBase, let first = bars.first, let last = bars.last else { return }
    let interval = base.series.interval
    let start = forward ? Self.closeTime(last.openTime, interval: interval) : Self.shifted(first.openTime, interval: interval, bars: -500)
    let end = forward ? min(replayLimit, Self.shifted(start, interval: interval, bars: 500)) : first.openTime
    guard start < end else { return }
    paging = true; let request = loadID
    pageTask = Task {
      defer { if request == loadID { paging = false } }
      do {
        let fetched = try await BinanceREST.upstream(MarketSource(rawValue: record.draft.range.venue)!, hosts: hosts).klines(symbol: record.draft.range.symbol, interval: interval, limit: 1000, startTime: start, endTime: end - 1)
        try Task.checkCancellation(); guard request == loadID else { return }
        let series = BinanceREST.series(symbol: record.draft.range.symbol, interval: interval, bars: fetched)
        let page = (0..<series.count).filter { Self.closeTime(series.time(at: $0), interval: interval) <= end }.map {
          Bar(openTime: series.time(at: $0), open: series.open[$0], high: series.high[$0], low: series.low[$0], close: series.close[$0], volume: series.volume[$0])
        }
        guard !page.isEmpty else { playing = false; playback?.cancel(); return }
        let position = bars[cursor].openTime
        let known = Set(bars.map(\.openTime)); let incoming = page.filter { !known.contains($0.openTime) }
        var combined = (bars + incoming).sorted { $0.openTime < $1.openTime }
        for i in 1..<combined.count where Self.closeTime(combined[i - 1].openTime, interval: interval) != combined[i].openTime { throw ReviewBridgeError.historyGap }
        if combined.count > 6000 { combined = forward ? Array(combined.suffix(6000)) : Array(combined.prefix(6000)) }
        bars = combined; cursor = max(2, bars.firstIndex(where: { $0.openTime == position }) ?? 2)
      } catch is CancellationError {} catch { if request == loadID { notice = error.localizedDescription; playing = false; playback?.cancel() } }
    }
  }
  func jumpToJudgment(feature: ReviewFeature) {
    guard let record = replayRecord, let base = replayBase else { return }
    let judgment = record.submitted ?? record.draft.created
    if let first = bars.first, let last = bars.last,
      judgment < first.openTime || judgment > Self.closeTime(last.openTime, interval: base.series.interval), let hosts = replayHosts {
      feature.rememberReplay(record.id, position: ReviewReplayPosition(cursor: judgment, speed: speed))
      open(record, feature: feature, live: base, hosts: hosts, cutoff: replayLimit)
      return
    }
    cursor = max(2, bars.lastIndex(where: { Self.closeTime($0.openTime, interval: base.series.interval) <= judgment }) ?? 2)
    updateReplay(feature: feature)
  }
  private func updateReplay(feature: ReviewFeature) {
    guard var base = replayBase, let record = replayRecord, !bars.isEmpty else { return }
    base.series = BarSeries(symbol: record.draft.range.symbol, interval: base.series.interval, bars: Array(bars.prefix(cursor + 1)))
    let known = Self.closeTime(base.series.lastTime, interval: base.series.interval)
    if known >= record.draft.created, let data = record.draft.drawingSnapshot { base.drawings = (try? JSONDecoder().decode([Drawing].self, from: data)) ?? [] }
    base.view = ViewWindow(to: Double(base.series.lastTime + base.series.step * 6), span: Double(base.series.step * 80))
    state = base
    if let chart = proxy.box?.chart { chart.state = base }
    feature.rememberReplay(record.id, position: ReviewReplayPosition(cursor: known, speed: speed))
  }
  func exitReplay(feature: ReviewFeature) {
    playing = false; playback?.cancel(); loadTask?.cancel(); pageTask?.cancel(); paging = false; replayHosts = nil; loadID = UUID(); loading = false
    state = nil; replayBase = nil; bars = []; replayRecord = nil; mode = .live; proxy = ChartProxy()
  }
  private func slice(_ s: BarSeries, count: Int) -> BarSeries {
    BarSeries(symbol: s.symbol, interval: s.interval, t0: s.t0, open: Array(s.open.prefix(count)), high: Array(s.high.prefix(count)), low: Array(s.low.prefix(count)), close: Array(s.close.prefix(count)), volume: Array(s.volume.prefix(count)), openTime: Array(s.openTime.prefix(count)))
  }
}
private enum ReviewBridgeError: LocalizedError {
  case noHistory, historyGap, rangeTooLarge
  var errorDescription: String? { switch self { case .noHistory: "这段历史暂时无法获取"; case .historyGap: "这段行情有缺口，暂不进入重温"; case .rangeTooLarge: "区间过长，请缩短后重温" } }
}
