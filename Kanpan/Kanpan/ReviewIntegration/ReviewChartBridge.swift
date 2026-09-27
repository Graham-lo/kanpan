import Foundation
import Observation
import KanpanCore
import KanpanChart
import KanpanData
import KanpanNetwork
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
  /// 交易回放（自动复盘 3d）这一趟：哪一笔、按什么节奏播、开仓那一停带出的那句话。
  /// 笔记重温时是 `nil`。
  struct TradeSession: Equatable {
    let id: String
    let plan: TradeReplayPlan
    let note: String?
  }
  var trade: TradeSession?
  /// 交易回放停在开仓那一根的 1.2 秒里，页头下面那一行「当时怎么想」。
  var caption: String?
  /// 交易回放停在开仓 / 平仓那一根时轻震一下（宿主接 `Haptics.tap`）。
  @ObservationIgnored var onTradeMark: () -> Void = {}
  /// 交易回放取不到数：宿主用那一个吐司说一句、退回这笔的详情。
  @ObservationIgnored var onTradeFailed: (String) -> Void = { _ in }
  var notice: String?
  /// 回放那一卷 K 线，以及推进时喂给图的那一段（增量追加、画线快照只解一次，见 `ReviewReplayTape`）。
  private var tape: ReviewReplayTape?
  private var bars: [Bar] { tape?.bars ?? [] }
  private var replayBase: ChartState?
  private var playback: Task<Void, Never>?
  private var loadTask: Task<Void, Never>?
  private var loadID = UUID()
  /// 「不许看到未来」的那条线，只有蒙眼找相似（`openMatch`）才给得出来：那条记录当时
  /// 就只该看到那一刻为止，所以它是冻住的。平常复盘自己记的一条笔记时这里是 `nil`，
  /// 上限跟着真实时间走。
  ///
  /// 冻住的代价 2026-09-21 在兼容性矩阵上现了形（三台机器一起红）：刚记下的笔记，
  /// 打开时最后一根正是当时的最新收盘，上限也就冻在了那一秒。之后再往后播（当时还有「后一根」按钮），
  /// `loadReplayPage(forward:)` 算出来的 `start >= end`，后来收的那些 K 线永远取不回来，
  /// 光标顶在末根上——按了没反应。复盘要挡的是「记录当时看不见的未来」，
  /// 不是「打开这条记录之后又过去的时间」。
  private var replayCutoff: Int64?
  /// 此刻的上限：蒙眼那条冻着，其余跟着钟走。
  private var replayLimit: Int64 { replayCutoff ?? ReviewClock.now }
  /// 上一拍那根最新 K 线的开盘时刻。用来判断「人还跟着播放头吗」（审查 B-05）。
  private var replayLastTime: Int64?
  private var replayProvider: (any MarketProvider)?
  /// 这一卷是哪只品种（补页时用）。
  private var replayKey: String?
  /// 手指按在进度线上：播放那一拍先让一让。
  private var scrubbing = false
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
  // 月线 / 年线按日历走，只有 `Interval.advancing` 一份（KanpanCore/UTCCalendar）。
  static func closeTime(_ time: Int64, interval: Interval) -> Int64 {
    interval.advancing(time, by: 1)
  }
  static func shifted(_ time: Int64, interval: Interval, bars: Int) -> Int64 {
    let moved = interval.advancing(time, by: bars)
    return interval.isIrregular ? moved : max(0, moved)
  }
  /// 当前这张实时图是从哪家取的数。
  ///
  /// 记录一落地就带着 `range.venue`，而记号该不该画在这张图上要拿它和**现在这张图的
  /// 行情源**比（审查 B.4）。每次发起捕获时从这张图的品种键里取出交易所，
  /// 这儿顺手记住，落图那一层就不必再跟宿主要一次。
  private(set) var liveVenue = VenueRegistry.default.id
  func beginCapture(feature: ReviewFeature, live: ChartState?, prefs: Prefs) {
    liveVenue = live.map { InstrumentID($0.series.symbol).venue } ?? VenueRegistry.default.id
    guard var live, live.series.count >= 3 else { notice = "等待 K 线加载后再记录"; return }
    // 服务端收不下的组合，圈之前就说（审查 B-06）。原来这儿只挡了年线，于是
    // BTCUSDC、美股代号照样能圈完、写完、按保存，最后被服务端 400 顶回来，
    // 还把那条永远成不了的操作留在了上传队列里。这一句和
    // `native_review.rs` 的 `validate_range` 是同一份名单（`ReviewContract`）。
    if let reason = ReviewContract.captureFailure(venue: liveVenue, symbol: live.series.symbol,
                                                  interval: live.series.interval.rawValue) {
      notice = reason; return
    }
    playing = false; playback?.cancel(); loadTask?.cancel()
    let s = live.series, now = ReviewClock.now
    let closed = (0..<s.count).filter { Self.closeTime(s.time(at: $0), interval: s.interval) <= now }
    guard let last = closed.last, closed.count >= 3 else { notice = "至少需要 3 根已收盘 K 线"; return }
    live.series = slice(s, count: last + 1); live.crosshair = nil; live.nowMs = nil
    var draft: ReviewDraft
    if let saved = feature.draft, saved.reusable(venue: liveVenue, symbol: s.symbol, interval: s.interval.rawValue) {
      draft = saved
    } else {
      let right = min(last, s.index(atTime: live.view.to)), left = max(0, right - 48)
      draft = ReviewDraft(range: ReviewRange(venue: liveVenue, symbol: s.symbol, interval: s.interval.rawValue,
        start: s.time(at: left), end: Self.closeTime(s.time(at: right), interval: s.interval), bars: right - left + 1),
        reference: s.close.last ?? s.close[last], high: s.high[left...right].max() ?? 0,
        low: s.low[left...right].min() ?? 0, now: now)
      draft.chartSettings = try? PersonalSyncCodec.snapshot(prefs)
      draft.drawingSnapshot = try? JSONEncoder().encode(live.drawings)
    }
    proxy = ChartProxy(); state = live; mode = .capture; feature.begin(draft)
  }
  /// 选区落到第 `left…right` 根：起止写成那两根的开盘 / 收盘边界，目标、失效没被手改过的
  /// 就跟着区间的高低点重算。图上拖手柄和卡片上改时刻走的是这同一段（P3.7）。
  static func snap(_ draft: inout ReviewDraft, left: Int, right: Int, series s: BarSeries) {
    guard s.count > 0 else { return }
    let left = max(0, min(s.count - 1, left)), right = max(left, min(s.count - 1, right))
    draft.range.start = s.time(at: left)
    draft.range.end = closeTime(s.time(at: right), interval: s.interval)
    draft.range.bars = right - left + 1
    let high = s.high[left...right].max() ?? draft.rule.target, low = s.low[left...right].min() ?? draft.rule.invalidation
    if !draft.rule.targetEdited { draft.rule.target = draft.rule.direction == .short ? low : high }
    if !draft.rule.invalidationEdited { draft.rule.invalidation = draft.rule.direction == .short ? high : low }
  }
  /// 卡片上两颗时间钮改出来的起止（`ReviewFeature.editRange`）。挑到的时刻落在哪根 K 线里
  /// 就吸到哪根（向下取整，不是就近——「从 10:05 起」说的是 10:00 那根）；少于三根时
  /// 由没动的那一头让位；选区不在屏上就把图挪过去，人改完一眼就能看见它落在哪。
  func editRange(start: Int64, end: Int64, feature: ReviewFeature) {
    guard mode == .capture, var draft = feature.draft,
          let s = proxy.box?.chart.state?.series ?? state?.series, s.count >= 3 else { return }
    func floorIndex(_ t: Int64) -> Int {
      var i = s.index(atTime: Double(t))
      while i > 0 && s.time(at: i) > t { i -= 1 }
      return i
    }
    var left = floorIndex(start), right = floorIndex(end - 1)
    if right - left < 2 {
      if start != draft.range.start { left = max(0, right - 2) } else { right = min(s.count - 1, left + 2) }
      if right - left < 2 { left = max(0, right - 2); right = min(s.count - 1, left + 2) }
    }
    Self.snap(&draft, left: left, right: right, series: s)
    feature.draft = draft; feature.saveDraft()
    proxy.box?.chart.reveal(from: Double(draft.range.start), to: Double(draft.range.end))
  }
  func endCapture(feature: ReviewFeature) {
    feature.saveDraft(); feature.captureOpen = false; mode = .live; state = nil; proxy = ChartProxy()
  }
  func open(_ record: ReviewRecord, feature: ReviewFeature, live: ChartState?, route: MarketRoute,
            cutoff: Int64? = nil) {
    let provider = VenueRegistry.descriptor(record.draft.range.venue)?.market == record.draft.range.market
      ? RouteResolver(route: route).ownDataProvider(venue: record.draft.range.venue) : nil
    open(record, feature: feature, live: live, provider: provider, cutoff: cutoff)
  }

  /// 两种回放开始取数前的同一段收拾：停播、撤掉上一趟的取数与补页、换一个请求号。
  private func beginLoad(provider: any MarketProvider) -> UUID {
    playback?.cancel(); playing = false; loadTask?.cancel(); pageTask?.cancel(); paging = false; loading = true
    scrubbing = false; caption = nil
    replayProvider = provider
    let request = UUID(); loadID = request
    return request
  }

  /// 回放要取的一卷：哪只、什么周期、从哪到哪、带不带画线快照。
  private struct TapeRequest {
    let key: String
    let shortSymbol: String
    let interval: Interval
    let start: Int64
    let end: Int64
    let drawingSnapshot: Data?
  }

  /// 两种回放（笔记重温、交易回放）共用的取数：分页取本家 K 线、验连续、落卷、定精度，
  /// 返回装好这一卷的底图。中途被新的一趟顶掉返回 `nil`。
  private func fetchTape(_ request: TapeRequest, base: ChartState, provider: any MarketProvider,
                         feature: ReviewFeature, id: UUID) async throws -> ChartState? {
    let caps = provider.capabilities
    let interval = request.interval, end = request.end
    var start = request.start
    var fetched: [Bar] = []
    while start < end {
      try Task.checkCancellation()
      let page = try await provider.klines(symbol: request.key, interval: interval, limit: caps.maxKlines, startTime: start, endTime: end - 1)
      guard let last = page.last else { break }
      fetched.append(contentsOf: page)
      let next = Self.closeTime(last.openTime, interval: caps.source(for: interval))
      guard next > start else { break }; start = next
      guard fetched.count <= 6000 else { throw ReviewBridgeError.rangeTooLarge }
    }
    try Task.checkCancellation(); guard loadID == id else { return nil }
    let series = MarketSeries.series(symbol: request.key, interval: interval, bars: fetched, capabilities: caps)
    let ordered = (0..<series.count).filter { Self.closeTime(series.time(at: $0), interval: interval) <= end }.map {
      Bar(openTime: series.time(at: $0), open: series.open[$0], high: series.high[$0], low: series.low[$0], close: series.close[$0], volume: series.volume[$0], takerBuy: series.takerBuy[$0])
    }
    guard ordered.count >= 3 else { throw ReviewBridgeError.noHistory }
    for i in 1..<ordered.count where Self.closeTime(ordered[i - 1].openTime, interval: interval) != ordered[i].openTime { throw ReviewBridgeError.historyGap }
    tape = ReviewReplayTape(symbol: request.key, interval: interval, bars: ordered,
                            drawingSnapshot: request.drawingSnapshot)
    replayKey = request.key
    var base = base
    base.series = BarSeries(symbol: request.key, interval: interval, bars: ordered)
    // 先用记录所属品种的目录精度。目录缺失才从历史报价推，不能继承另一张图的精度。
    let decimals = feature.priceDecimals(request.key)
      ?? (base.symbol.symbol == request.key ? base.symbol.knownPriceDecimals : nil)
      ?? ReviewPricePrecision.decimals(of: ordered.flatMap { [$0.open, $0.high, $0.low, $0.close] })
      ?? priceDecimalsFallback(ordered.last!.close)
    base.symbol = SymbolInfo(symbol: request.key, base: request.shortSymbol, pricePrecision: decimals,
                             tickSize: pow(10, -Double(decimals)))
    // 存储的显示位数与这次替换的品种一起更新。
    base.decimals = base.symbol.priceDecimals
    return base
  }

  /// 回放取数认的是记录所属那一家的本家数据（`RouteResolver.ownDataProvider`）。
  private func open(_ record: ReviewRecord, feature: ReviewFeature, live: ChartState?,
                    provider: (any MarketProvider)?, cutoff: Int64?) {
    guard let interval = Interval(rawValue: record.draft.range.interval), let provider
    else { notice = "这个市场暂未接入原生行情"; return }
    guard var base = live else { notice = "等待行情加载"; return }
    let request = beginLoad(provider: provider)
    trade = nil
    replayCutoff = cutoff
    // 这一次取数的三个边界得用同一个上限，中途别让钟走掉一根。
    let limit = replayLimit
    let range = record.draft.range
    let savedPosition = feature.savedReplay(record.id)?.cursor ?? range.end
    let initialAnchor = min(limit, max(range.end, savedPosition))
    let windowStart = Self.shifted(initialAnchor == range.end ? range.start : initialAnchor, interval: interval, bars: -300)
    let end = min(limit, Self.shifted(initialAnchor, interval: interval, bars: 300))
    if let data = record.draft.chartSettings, let prefs = try? PersonalSyncCodec.snapshotPrefs(data) {
      base.options = prefs.chartOptions; base.params = prefs.params
      base.overlays = prefs.overlays; base.subs = prefs.subs.filter { $0 != .oi }
      base.indicatorColors = prefs.indicatorColors; base.hiddenOutputs = prefs.hiddenOutputs
      base.price = PriceTransform(mode: prefs.priceMode)
    }
    // No live OI or later annotations may enter the replay indicator engine.
    base.oi = nil; base.subs.removeAll { $0 == .oi }; base.drawings = []
    base.crosshair = nil; base.nowMs = nil
    let tapeRequest = TapeRequest(key: range.key, shortSymbol: range.shortSymbol, interval: interval,
                                  start: windowStart, end: end, drawingSnapshot: record.draft.drawingSnapshot)
    loadTask = Task {
      do {
        guard let base = try await fetchTape(tapeRequest, base: base, provider: provider, feature: feature, id: request)
        else { return }
        replayBase = base; replayRecord = record; speed = preferredSpeed()
        let saved = savedPosition
        cursor = max(2, bars.lastIndex(where: { Self.closeTime($0.openTime, interval: interval) <= saved }) ?? 2)
        // 只有从别的模式（实时、取景）进回放才换一张新画布：那时图表那棵树会按 `mode`
        // 重建，旧 proxy 指着的是上一张图。已经在回放里再开一条（「跳到判断处」要重新取数、
        // 从「找相似」直接换一条记录）必须留着同一张：树的 id 没变，`ChartView` 不会重建，
        // 换了 proxy 下面那句「把算好的视野直接写进图里」就落空，`ChartHost.updateUIView`
        // 接着拿屏幕上那份旧视野盖回来，人看到的就是「按了没反应」。
        if mode != .replay { proxy = ChartProxy() }
        mode = .replay; replayLastTime = nil
        // 第一次进来才重设视野（80 根）：这是「打开这条记录」，不是「推进一根」。
        updateReplay(feature: feature, reset: true); loading = false
      } catch is CancellationError {} catch { if loadID == request { loading = false; notice = Self.message(for: error) } }
    }
  }

  /// 交易回放（自动复盘 3d）：已平仓的一笔，从详情页点一下图就回到行情图上，
  /// 从开仓前 20 根自动播到平仓后 5 根。
  ///
  /// * 品种、交易所取自这一回合；数据走那一家的本家接口（和笔记重温同一个取数口）。
  /// * 周期按 `TradeReplayPlan.interval` 的优先级挑：人自己的周期 → 服务端复盘图的周期 → 按持仓时长挑。
  /// * 取数这段不弹任何东西：图先换成这只品种、这个周期的空图（人当前的样式），数一到就开播；
  ///   取不到交给宿主说一句、退回这笔的详情（`onTradeFailed`）。
  /// * 不记游标（不写 `rememberReplay`）：交易回放每次都是从头看一遍这笔单子，
  ///   它的「位置」没有意义；倍速按这一趟的根数自己挑（`ReplayPace`）。
  /// * 不画副图、对比、持仓量和画线：这张图只讲这一笔。
  func openTrade(_ item: TradeItem, feature: ReviewFeature, live: ChartState?, route: MarketRoute,
                 preferred: Interval?) {
    let round = item.round
    let spec = item.record?.result?.chart
    guard let plan = TradeReplayPlan(round: round, spec: spec, preferred: preferred) else { return }
    guard VenueRegistry.descriptor(round.venue)?.market == round.market,
          let provider = RouteResolver(route: route).ownDataProvider(venue: round.venue)
    else { onTradeFailed("这个市场暂未接入原生行情"); return }
    guard var base = live else { onTradeFailed("等待行情加载"); return }
    let request = beginLoad(provider: provider)
    replayRecord = nil; replayCutoff = nil; tape = nil; replayBase = nil; replayKey = nil
    let key = round.instrument.key
    let note = item.record?.note?.text.trimmingCharacters(in: .whitespacesAndNewlines)
    trade = TradeSession(id: item.id, plan: plan, note: note?.isEmpty == false ? note : nil)
    base.oi = nil; base.subs = []; base.compare = []; base.percentAxis = false; base.external = [:]
    base.drawings = []; base.crosshair = nil; base.nowMs = nil; base.depth = nil; base.orderFlow = nil
    base.series = BarSeries(symbol: key, interval: plan.interval, bars: [])
    if mode != .replay { proxy = ChartProxy() }
    state = base; mode = .replay; replayLastTime = nil; cursor = 0
    let window = plan.fetchWindow(spec: spec)
    let tapeRequest = TapeRequest(key: key, shortSymbol: SymbolInfo.placeholder(symbol: key).base,
                                  interval: plan.interval, start: window.start,
                                  end: min(window.end, ReviewClock.now), drawingSnapshot: nil)
    loadTask = Task {
      do {
        guard let base = try await fetchTape(tapeRequest, base: base, provider: provider, feature: feature, id: request)
        else { return }
        guard bars.contains(where: { $0.openTime >= plan.openBar }) else { throw ReviewBridgeError.noHistory }
        replayBase = base
        cursor = index(atOrBefore: plan.startBar)
        // 倍速按这一趟的根数挑（`ReplayPace`）：整趟连同进来那一静、开仓平仓两停落在 20–40 秒。
        speed = ReplayPace.speed(bars: index(atOrBefore: plan.stopBar) - cursor,
                                 fixedMs: TradeReplayPlan.holdMs + 2 * TradeReplayPlan.pauseMs)
        updateReplay(feature: feature, reset: true); loading = false
        // 先静止 0.8 秒让人看清起点，再自己开播。
        startPlayback(feature: feature, holdMs: TradeReplayPlan.holdMs)
      } catch is CancellationError {} catch {
        if loadID == request { loading = false; onTradeFailed(Self.message(for: error)) }
      }
    }
  }

  func openMatch(_ match: ReviewMatch, cutoff: Int64, feature: ReviewFeature, live: ChartState?,
                 route: MarketRoute) {
    var draft = ReviewDraft(range: match.range, reference: 1, high: 1, low: 1, now: cutoff)
    draft.rule.expires = cutoff
    open(ReviewRecord(draft: draft), feature: feature, live: live, route: route, cutoff: cutoff)
  }
  /// 回放条上那颗倍速按钮：1× → 2× → 4× → 1×。写回偏好，跟着人走。
  func cycleSpeed() {
    speed = speed == 4 ? 1 : speed * 2
    onSpeedChange(speed)
  }

  /// 卷里开盘时刻不晚于 `time` 的最后一根（游标最小是 2：图上至少要有三根）。
  private func index(atOrBefore time: Int64) -> Int {
    max(2, bars.lastIndex(where: { $0.openTime <= time }) ?? 2)
  }

  /// 回放条上那根进度线。交易回放：开仓前 20 根 → 平仓后 5 根，刻度在开仓、平仓两根；
  /// 笔记回放：这卷首根 → 末根，刻度在判断那根（往前补了历史，线跟着长）。
  var track: ReviewReplayTrack? {
    guard mode == .replay, !loading, bars.count >= 3 else { return nil }
    if let plan = trade?.plan {
      return ReviewReplayTrack(lower: index(atOrBefore: plan.startBar), upper: index(atOrBefore: plan.stopBar),
                               marks: [index(atOrBefore: plan.openBar), index(atOrBefore: plan.closeBar)])
    }
    guard let record = replayRecord, let interval = replayBase?.series.interval else { return nil }
    let judgment = record.submitted ?? record.draft.created
    let mark = bars.lastIndex(where: { Self.closeTime($0.openTime, interval: interval) <= judgment })
    return ReviewReplayTrack(lower: 2, upper: bars.count - 1, marks: mark.map { [max(2, $0)] } ?? [])
  }

  /// 播到尾了：播放钮变「重播」。交易回放是走到平仓后第 5 根；笔记回放是走到最后一根、
  /// 而且下一根还没收盘（再往后没有可看的了）。
  var ended: Bool {
    guard mode == .replay, !loading, !playing, bars.count >= 3 else { return false }
    if trade != nil, let track { return cursor >= track.upper }
    guard trade == nil, replayRecord != nil, cursor >= bars.count - 1, !paging, let last = bars.last,
          let interval = replayBase?.series.interval else { return false }
    return Self.closeTime(Self.closeTime(last.openTime, interval: interval), interval: interval) > replayLimit
  }

  /// 交易回放此刻的浮动盈亏（比值），只在持仓那一段有。
  var floatingReturn: Double? {
    guard let plan = trade?.plan, let series = state?.series, series.count > 0, let close = series.close.last
    else { return nil }
    return plan.floatingReturn(close: close, at: series.lastTime)
  }

  func step(_ amount: Int, feature: ReviewFeature) {
    if amount > 0 && cursor >= bars.count - 2 { loadReplayPage(forward: true, feature: feature) }
    if amount < 0 && cursor <= 2 { loadReplayPage(forward: false, feature: feature) }
    cursor = min(max(2, cursor + amount), max(2, bars.count - 1)); updateReplay(feature: feature)
    if cursor >= bars.count - 1 && !paging { playing = false; playback?.cancel() }
  }

  /// 播放钮：播 ↔ 停；播到尾是「重播」，从头再来。
  func togglePlay(feature: ReviewFeature) {
    guard mode == .replay, !loading, bars.count >= 3 else { return }
    if ended { restart(feature: feature); return }
    if playing { playing = false; playback?.cancel() } else { startPlayback(feature: feature) }
  }

  /// 一秒一根 × 倍速往前走。交易回放走到开仓、平仓那根各停 1.2 秒、轻震一下
  /// （开仓那一停带出「当时怎么想」），走到平仓后第 5 根自己停下、不震。
  /// 手指按在进度线上时这一拍让一让，松手接着播。
  private func startPlayback(feature: ReviewFeature, holdMs: Int = 0) {
    playback?.cancel(); playing = true; caption = nil
    playback = Task {
      if holdMs > 0 { do { try await Task.sleep(for: .milliseconds(holdMs)) } catch { return } }
      while !Task.isCancelled && playing {
        do { try await Task.sleep(for: .milliseconds(1000 / max(1, speed))) } catch { return }
        guard playing, !scrubbing else { continue }
        caption = nil
        guard let plan = trade?.plan else { step(1, feature: feature); continue }
        guard let track, cursor < track.upper else { playing = false; return }
        cursor += 1; updateReplay(feature: feature)
        let bar = bars[cursor].openTime
        if cursor >= track.upper || plan.finished(at: bar) { playing = false; return }
        if plan.pauses(at: bar) {
          onTradeMark()
          if plan.isOpenBar(bar), let note = trade?.note { caption = note }
          do { try await Task.sleep(for: .milliseconds(TradeReplayPlan.pauseMs)) } catch { return }
          if playing { caption = nil }
        }
      }
    }
  }

  /// 「重播」：回到起点（交易是开仓前 20 根，笔记是圈的那段起点），重设视野，接着播。
  func restart(feature: ReviewFeature) {
    if let plan = trade?.plan {
      cursor = index(atOrBefore: plan.startBar)
    } else if let record = replayRecord {
      let start = record.draft.range.start
      cursor = max(2, bars.firstIndex(where: { $0.openTime >= start }) ?? 2)
    }
    caption = nil; replayLastTime = nil
    updateReplay(feature: feature, reset: true)
    startPlayback(feature: feature)
  }

  /// 拖进度线：游标跟着手指走，视野跟着播放头、根宽不动。
  func seek(to index: Int, feature: ReviewFeature) {
    guard mode == .replay, !loading, bars.count >= 3 else { return }
    var target = min(max(2, index), bars.count - 1)
    if trade != nil, let track { target = min(max(track.lower, target), track.upper) }
    guard target != cursor else { return }
    cursor = target; caption = nil; replayLastTime = nil
    updateReplay(feature: feature)
  }

  /// 按下 / 松开进度线。松手停在哪就是哪，原来在播接着播；笔记回放拖到卷的两头就去补一页。
  func scrub(_ active: Bool, feature: ReviewFeature) {
    scrubbing = active
    guard !active, trade == nil, mode == .replay, bars.count >= 3 else { return }
    if cursor >= bars.count - 2 { loadReplayPage(forward: true, feature: feature) }
    if cursor <= 2 { loadReplayPage(forward: false, feature: feature) }
  }

  /// 回放条最右那颗：交易回放「开仓处」，笔记回放「判断处」。
  func jumpToKey(feature: ReviewFeature) {
    guard let plan = trade?.plan else { jumpToJudgment(feature: feature); return }
    guard mode == .replay, !loading, bars.count >= 3 else { return }
    cursor = index(atOrBefore: plan.openBar); caption = nil
    updateReplay(feature: feature, reset: true)
  }

  func loadReplayPage(forward: Bool, feature: ReviewFeature) {
    guard !paging, trade == nil, let provider = replayProvider, let key = replayKey, let base = replayBase, let first = bars.first, let last = bars.last else { return }
    let interval = base.series.interval
    let start = forward ? Self.closeTime(last.openTime, interval: interval) : Self.shifted(first.openTime, interval: interval, bars: -500)
    let end = forward ? min(replayLimit, Self.shifted(start, interval: interval, bars: 500)) : first.openTime
    guard start < end else { return }
    paging = true; let request = loadID
    pageTask = Task {
      defer { if request == loadID { paging = false } }
      do {
        let fetched = try await provider.klines(symbol: key, interval: interval, limit: min(1000, provider.capabilities.maxKlines), startTime: start, endTime: end - 1)
        try Task.checkCancellation(); guard request == loadID else { return }
        let series = MarketSeries.series(symbol: key, interval: interval, bars: fetched, capabilities: provider.capabilities)
        let page = (0..<series.count).filter { Self.closeTime(series.time(at: $0), interval: interval) <= end }.map {
          Bar(openTime: series.time(at: $0), open: series.open[$0], high: series.high[$0], low: series.low[$0], close: series.close[$0], volume: series.volume[$0], takerBuy: series.takerBuy[$0])
        }
        guard !page.isEmpty else { playing = false; playback?.cancel(); return }
        let position = bars[cursor].openTime
        let known = Set(bars.map(\.openTime)); let incoming = page.filter { !known.contains($0.openTime) }
        var combined = (bars + incoming).sorted { $0.openTime < $1.openTime }
        for i in 1..<combined.count where Self.closeTime(combined[i - 1].openTime, interval: interval) != combined[i].openTime { throw ReviewBridgeError.historyGap }
        if combined.count > 6000 { combined = forward ? Array(combined.suffix(6000)) : Array(combined.prefix(6000)) }
        tape?.replace(bars: combined); cursor = max(2, bars.firstIndex(where: { $0.openTime == position }) ?? 2)
        // 取回来了就得画上去。`bars` 只是这边的一个数组，屏幕上那张图是 `updateReplay`
        // 按 `cursor` 现切的；不补这一句，往前翻到头拿回来的五百根要等到人再动一下
        // （再拖一下进度线、或者播放走到下一拍）才显形——看起来就是「翻到头了没反应，
        // 隔一会儿又突然多出来一截」。不 `reset`：人自己挑的视野不能被这趟补数顶掉。
        updateReplay(feature: feature)
      } catch is CancellationError {} catch { if request == loadID { notice = Self.message(for: error); playing = false; playback?.cancel() } }
    }
  }
  func jumpToJudgment(feature: ReviewFeature) {
    guard let record = replayRecord, let base = replayBase else { return }
    let judgment = record.submitted ?? record.draft.created
    // 判断那一刻落在已经取回来的这段之外，才值得重新取一次数。右边那一侧还要多问一句
    // 「再取一次真能多出一根吗」：刚记下的那条，判断时刻就落在最后一根收盘之后、下一根
    // 还没收，重取回来的还是同一批 K 线——白跑一趟网络，还会把这张画布连同人刚挑好的
    // 视野一起换掉，于是「判断处」按下去一动不动（审查 B-05）。
    let interval = base.series.interval
    var outside = false
    if let first = bars.first, let last = bars.last {
      let lastClose = Self.closeTime(last.openTime, interval: interval)
      outside = judgment < first.openTime
        || (judgment > lastClose && Self.closeTime(lastClose, interval: interval) <= replayLimit)
    }
    if outside, let provider = replayProvider {
      feature.rememberReplay(record.id, position: ReviewReplayPosition(cursor: judgment, speed: speed))
      // 传 `replayCutoff` 而不是 `replayLimit`：蒙眼那条要把冻住的时刻原样带过去，
      // 平常那条要保持「没有上限，跟着钟走」，别在这儿被钉成当前时刻。
      open(record, feature: feature, live: base, provider: provider, cutoff: replayCutoff)
      return
    }
    cursor = max(2, bars.lastIndex(where: { Self.closeTime($0.openTime, interval: interval) <= judgment }) ?? 2)
    // 「跳到判断处」是人自己要求换地方，这一次重设视野是他点的。
    updateReplay(feature: feature, reset: true)
  }

  /// 屏幕上这一刻的视野。
  ///
  /// 手势直接写 `ChartView.state.view`（`ChartView+Gesture.swift` 里捏合、拖动、
  /// 惯性都往那儿写），所以人捏成什么样，答案在图那边，不在 `bridge.state` 这份
  /// 快照里。图还没挂上去（第一次进来）就退回自己这份。
  private var liveWindow: ReviewReplayWindow? {
    guard let view = proxy.box?.chart.state?.view ?? state?.view else { return nil }
    return ReviewReplayWindow(to: view.to, span: view.span)
  }

  /// 推进一根之后，把新的这一段喂给图。
  ///
  /// `reset` 只有两处给 `true`：刚打开一条记录、以及人点「跳到判断处」。其余每一拍
  /// 都保留人的根宽（审查 B-05）——原来这儿每次都写死 `span = 80 根`、右缘贴最新一根，
  /// 于是人在回放里放大看一根的细节，按一下「下一根」就被缩回 80 根，拖去看历史也
  /// 会被拽回最右边。那颗按钮等于一次次把人的手拨开。
  private func updateReplay(feature: ReviewFeature, reset: Bool = false) {
    guard var base = replayBase, !bars.isEmpty, let series = tape?.series(through: cursor) else { return }
    // 往后推一根只追加那一根（图表认得出「后面长了一根」，指标只算末根）；
    // 画线快照整条回放只解一次。原来每一拍都整段重摊、整份重解（第 25 项）。
    base.series = series
    let known = Self.closeTime(base.series.lastTime, interval: base.series.interval)
    if let record = replayRecord, known >= record.draft.created { base.drawings = tape?.drawings() ?? [] }
    let window = ReviewReplayViewport.next(current: liveWindow, previousLastTime: replayLastTime,
                                           lastTime: base.series.lastTime, step: base.series.step, reset: reset)
    base.view = ViewWindow(to: window.to, span: window.span)
    replayLastTime = base.series.lastTime
    state = base
    if let chart = proxy.box?.chart { chart.state = base }
    // 交易回放不记游标（见 `openTrade`）：只有笔记重温才记下看到哪儿。
    if let record = replayRecord {
      feature.rememberReplay(record.id, position: ReviewReplayPosition(cursor: known, speed: speed))
    }
  }
  func exitReplay(feature: ReviewFeature) {
    playing = false; playback?.cancel(); loadTask?.cancel(); pageTask?.cancel(); paging = false; replayProvider = nil; loadID = UUID(); loading = false
    state = nil; replayBase = nil; tape = nil; replayRecord = nil; replayKey = nil; mode = .live; proxy = ChartProxy()
    trade = nil; caption = nil; scrubbing = false
  }
  private func slice(_ s: BarSeries, count: Int) -> BarSeries {
    BarSeries(symbol: s.symbol, interval: s.interval, t0: s.t0, open: Array(s.open.prefix(count)), high: Array(s.high.prefix(count)), low: Array(s.low.prefix(count)), close: Array(s.close.prefix(count)), volume: Array(s.volume.prefix(count)), takerBuy: Array(s.takerBuy.prefix(count)), openTime: Array(s.openTime.prefix(count)))
  }
}
extension ReviewChartBridge {
  /// 重温取数失败时摆在图上的那句话。自己判出来的几种（没历史、有缺口、区间太长）照原话说；
  /// 取 K 线那一路抛上来的（超时、断网、解码）一律只说「暂时取不到」——原来直接摆
  /// `localizedDescription`，弱网下是「请求超时。」这类系统原文，非本地化错误还会拼出
  /// 「未能完成操作。（KanpanData.XXX错误 0。）」把类型名露给人看。原始错误不上屏。
  static func message(for error: Error) -> String {
    if let own = error as? ReviewBridgeError, let text = own.errorDescription { return text }
    return "这段历史暂时取不到，稍后再试"
  }
}

enum ReviewBridgeError: LocalizedError {
  case noHistory, historyGap, rangeTooLarge
  var errorDescription: String? { switch self { case .noHistory: "这段历史暂时无法获取"; case .historyGap: "这段行情有缺口，暂不进入重温"; case .rangeTooLarge: "区间过长，请缩短后重温" } }
}
