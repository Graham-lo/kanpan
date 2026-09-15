import Foundation
import Observation
import KanpanCore
import KanpanData

/// 前台跨页面共享自选/可见品种WS；后台释放。日开盘只按需取一次。
@MainActor @Observable
final class QuoteBook {
  private(set) var raw: [String: Ticker] = [:]
  private(set) var lastListUpdate: Date?
  private(set) var basis: ChangeBasis = .rolling24h
  private var latestReceived: [String: QuoteState] = [:]
  private var hosts = BinanceHosts.default
  private var rest = BinanceREST()
  private var source: MarketSource = .binance
  private var socket: BinanceWS?
  private var subscribedStreams: [String] = []
  private var pump: Task<Void, Never>?
  private var wanted = Set<String>()
  private var opens: [String: (time: Int64, price: Double)] = [:]
  private var queue = Set<String>()
  private var jobs: [String: Task<Void, Never>] = [:]
  private var failedAt: [String: Date] = [:]
  private var generation = 0
  private var boundary: Int64?
  private var visible = false
  private var foreground = true
  private var favorites: [String] = []
  private var chartSymbol: String?
  private var online = true
  private let network = MarketNetworkMonitor()
  private var session = QuoteSession()
  private var quoteQueue: [String] = []
  private var quoteJobs: [String: Task<Void, Never>] = [:]
  private var quoteAttempt: [String: Date] = [:]
  private var startedAt = Date()
  private var firstQuoteMs: Int?
  var diagnostics: String? {
    guard ProcessInfo.processInfo.environment["KANPAN_CHART_DIAGNOSTICS"] == "1" else { return nil }
    return "session=\(session.generation);firstQuoteMs=\(firstQuoteMs ?? -1);rows=\(raw.count);status=\(status.rawValue)"
  }
  private(set) var status: FeedStatus = .reconnecting
  var onReset: (() -> Void)?
  var onScopeChange: ((Set<String>) -> Void)?
  private var visibleRows = Set<String>()
  private var historyWanted = Set<String>()
  private var historyJobs: [String: Task<Void, Never>] = [:]
  private var historyRequested: [String: Date] = [:]
  var onHistory: ((String, [Bar]) -> Void)?
  var onUpdate: (([Ticker]) -> Void)?

  func configure(hosts: BinanceHosts, basis: ChangeBasis, source: MarketSource = .binance) {
    let changedHost = hosts != self.hosts
    let changedSource = source != self.source
    let changedBasis = basis != self.basis
    if changedHost || changedSource {
      self.hosts = hosts
      self.source = source
      rest = BinanceREST.upstream(source, hosts: hosts)
      opens.removeAll()
      for symbol in Array(quoteJobs.keys) where symbol != chartSymbol { quoteJobs.removeValue(forKey: symbol)?.cancel() }
      quoteQueue.removeAll { $0 != chartSymbol }
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll(); historyRequested.removeAll()
    }
    self.basis = basis
    if changedHost || changedSource || changedBasis { resetBaselineRequests() }
    if (changedHost || changedSource), needsConnection { restartStream() }
    tick()
    publish(Array(raw.values))
  }

  private var needsConnection: Bool {
    // The chart has its own MarketModel feed. QuoteBook only needs a socket
    // when it is serving the cross-page favorites/symbol list.
    foreground && QuoteSubscriptionPlan.needsConnection(foreground: foreground, favorites: favorites, visible: visible)
  }

  func setFavorites(_ symbols: [String]) {
    favorites = symbols
    for symbol in symbols { wanted.insert(symbol); watchBaseline(symbol) }
    reconcileConnection()
    updateStreams()
  }

  func setForeground(_ on: Bool) {
    guard on != foreground else { return }
    foreground = on
    reconcileConnection()
  }

  func setVisible(_ on: Bool) {
    guard on != visible else { return }
    visible = on
    reconcileConnection()
    updateStreams()
    if !on {
      for symbol in Array(quoteJobs.keys) where symbol != chartSymbol { quoteJobs.removeValue(forKey: symbol)?.cancel() }
      quoteQueue.removeAll { $0 != chartSymbol }
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
    }
  }

  private func reconcileConnection() {
    if needsConnection {
      guard pump == nil else { return } // 健康前台会话跨页面继续，价格无需重取。
      online = true
      network.start { [weak self] online in
        Task { @MainActor [weak self] in self?.networkChanged(online) }
      }
      restartStream()
    } else {
      network.stop(); stopStream(); cancelQuotes(); resetBaselineRequests()
      historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
      lastListUpdate = nil
      if !foreground { raw.removeAll(keepingCapacity: true); latestReceived.removeAll(keepingCapacity: true); onReset?() }
    }
  }

  private func streamNames() -> [String] {
    let symbols = QuoteSubscriptionPlan.symbols(favorites: [chartSymbol].compactMap { $0 } + favorites, visible: visible ? visibleRows : [])
    return (symbols.isEmpty ? ["BTCUSDT"] : symbols).map { BinanceHosts.tickerStream(symbol: $0) }
  }

  private func updateStreams() {
    let symbols = QuoteSubscriptionPlan.symbols(favorites: [chartSymbol].compactMap { $0 } + favorites, visible: visible ? visibleRows : [])
    wanted = Set(symbols + [chartSymbol].compactMap { $0 })
    if raw.keys.contains(where: { !wanted.contains($0) }) { raw = raw.filter { wanted.contains($0.key) } }
    latestReceived = latestReceived.filter { wanted.contains($0.key) }
    onScopeChange?(wanted)
    for symbol in Array(jobs.keys) where !wanted.contains(symbol) { jobs.removeValue(forKey: symbol)?.cancel() }
    queue.formIntersection(wanted)
    opens = opens.filter { wanted.contains($0.key) }
    guard let socket else { return }
    let names = streamNames()
    guard names != subscribedStreams else { return }
    subscribedStreams = names
    Task { await socket.replaceStreams(names) }
  }

  func ingest(_ batch: [Ticker]) {
    guard foreground else { return }
    var valid: [Ticker] = []
    for ticker in batch where wanted.contains(ticker.symbol) {
      var state = latestReceived[ticker.symbol] ?? QuoteState()
      guard state.receive(ticker), let ticker = state.value else { continue }
      latestReceived[ticker.symbol] = state
      session.receive(ticker.symbol)
      if let old = raw[ticker.symbol], LatestQuote.sameDisplay(ticker, old) { continue }
      raw[ticker.symbol] = ticker
      valid.append(ticker)
    }
    if needsConnection, !valid.isEmpty, firstQuoteMs == nil { firstQuoteMs = Int(-startedAt.timeIntervalSinceNow * 1000) }
    if !valid.isEmpty { publish(valid) }
    if visible { loadHistories() }
  }

  func ingestTrade(_ trade: TradeQuote) {
    guard foreground, wanted.contains(trade.symbol) else { return }
    var state = latestReceived[trade.symbol] ?? QuoteState()
    guard state.receive(trade), let ticker = state.value else { return }
    latestReceived[trade.symbol] = state
    session.receive(trade.symbol)
    if let old = raw[trade.symbol], LatestQuote.sameDisplay(ticker, old) { return }
    raw[trade.symbol] = ticker
    if firstQuoteMs == nil { firstQuoteMs = Int(-startedAt.timeIntervalSinceNow * 1000) }
    publish([ticker])
  }

  func presented(_ ticker: Ticker) -> Ticker {
    var value = ticker
    let start = basis.boundary(now: Int64(Date().timeIntervalSince1970 * 1000))
    let opening = opens[ticker.symbol]
    value.changePercent = basis.percent(last: ticker.last, rolling: ticker.changePercent,
      open: opening?.time == start ? opening?.price : nil)
    return value
  }

  func watchChart(_ symbol: String) {
    setChartSymbol(symbol)
    if needsConnection { watch(symbol) }
  }

  /// Keeps the chart symbol available to the shared quote book without
  /// opening a second socket for the chart page. If the list is already
  /// visible, preserve the old behavior and add the symbol to its stream.
  func setChartSymbol(_ symbol: String) {
    let next = symbol.uppercased()
    guard chartSymbol != next else { return }
    chartSymbol = next
    guard needsConnection else { return }
    watch(next)
    reconcileConnection()
    updateStreams()
  }

  func watch(_ symbol: String) {
    wanted.insert(symbol)
    requestQuote(symbol)
    watchBaseline(symbol)
  }

  private func watchBaseline(_ symbol: String) {
    guard let boundary, opens[symbol]?.time != boundary, jobs[symbol] == nil,
          Date().timeIntervalSince(failedAt[symbol] ?? .distantPast) > 30 else { return }
    queue.insert(symbol); drain()
  }

  func tick() {
    let next = basis.boundary(now: Int64(Date().timeIntervalSince1970 * 1000))
    if next != boundary {
      boundary = next; opens.removeAll(); resetBaselineRequests()
      publish(Array(raw.values))
    }
    for symbol in wanted { watchBaseline(symbol) }
    for symbol in visibleRows { requestQuote(symbol) }
    if let chartSymbol { requestQuote(chartSymbol) }
    loadHistories()
  }

  func watchRow(_ symbol: String, visible: Bool) {
    if visible { visibleRows.insert(symbol); requestQuote(symbol) }
    else {
      visibleRows.remove(symbol)
      if symbol != chartSymbol {
        quoteQueue.removeAll { $0 == symbol }; quoteJobs.removeValue(forKey: symbol)?.cancel()
      }
    }
    updateStreams()
  }

  func watchHistory(_ symbol: String, visible: Bool) {
    if visible { historyWanted.insert(symbol); requestQuote(symbol); loadHistories() }
    else {
      historyWanted.remove(symbol)
      historyJobs.removeValue(forKey: symbol)?.cancel()
    }
  }

  private func loadHistories() {
    guard foreground, visible, online else { return }
    for symbol in historyWanted where historyJobs.count < 2 && historyJobs[symbol] == nil && raw[symbol] != nil {
      guard Date().timeIntervalSince(historyRequested[symbol] ?? .distantPast) >= 60 else { continue }
      historyRequested[symbol] = Date()
      let rest = self.rest
      historyJobs[symbol] = Task { [weak self] in
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let bars = try? await rest.klines(symbol: symbol, interval: .m1, limit: 245,
          startTime: now - 4 * 3_600_000 - 60_000, endTime: now)
        guard let self, !Task.isCancelled else { return }
        self.historyJobs[symbol] = nil
        if bars == nil { self.historyRequested[symbol] = Date().addingTimeInterval(-30) }
        if let bars, !bars.isEmpty { self.onHistory?(symbol, bars) }
        self.loadHistories()
      }
    }
  }

  private func resetBaselineRequests() {
    generation += 1
    jobs.values.forEach { $0.cancel() }; jobs.removeAll(); queue.removeAll(); failedAt.removeAll()
  }

  private func drain() {
    guard foreground, online, let boundary else { return }
    while jobs.count < 4, let symbol = queue.first {
      queue.remove(symbol)
      let generation = self.generation, rest = self.rest
      jobs[symbol] = Task { [weak self] in
        let bars = try? await rest.klines(symbol: symbol, interval: .h1, limit: 1,
          startTime: boundary, endTime: boundary + 3_600_000 - 1)
        guard let self, !Task.isCancelled, generation == self.generation else { return }
        self.jobs[symbol] = nil
        if let bar = bars?.first, bar.openTime == boundary, bar.open.isFinite, bar.open > 0 {
          self.opens[symbol] = (boundary, bar.open)
        } else { self.failedAt[symbol] = Date() }
        if let value = self.raw[symbol] { self.publish([value]) }
        self.drain()
      }
    }
  }

  private func publish(_ batch: [Ticker]) { onUpdate?(batch.map(presented)) }

  private func startStream() {
    guard pump == nil else { return }
    // SourceSocketFactory owns the Binance/OKX fallback decision. Clear the
    // generic stream fallback list here so BinanceWS does not wrap it twice.
    var socketHosts = hosts
    socketHosts.streamFallbacks = []
    let socket = BinanceWS(hosts: socketHosts,
                           factory: SourceSocketFactory(source: source, hosts: hosts),
                           silenceMs: 15_000)
    let generation = session.generation
    self.socket = socket
    let names = streamNames()
    subscribedStreams = names
    pump = Task { [weak self] in
      let events = await socket.start(streams: names)
      for await event in events {
        guard let self, !Task.isCancelled, generation == self.session.generation else { break }
        switch event {
        case .payload(.tickerBatch(let batch)):
          guard !batch.isEmpty else { continue }
          self.noteLive(); self.ingest(batch)
        case .payload(.ticker(let ticker)):
          self.noteLive(); self.ingest([ticker])
        case .status(let status):
          // 握手成功还不等于行情到达。
          if status != .live {
            self.status = status; self.lastListUpdate = nil
            self.cancelQuotes(); self.raw.removeAll(keepingCapacity: true); self.latestReceived.removeAll(keepingCapacity: true); self.onReset?()
          }
        default: break
        }
      }
    }
  }

  private func noteLive() {
    let now = Date()
    if lastListUpdate == nil || now.timeIntervalSince(lastListUpdate!) >= 1 { lastListUpdate = now }
    if status != .live { status = .live }
  }

  private func networkChanged(_ online: Bool) {
    guard needsConnection else { return }
    self.online = online
    restartStream()
  }

  private func restartStream() {
    stopStream(); cancelQuotes(); resetBaselineRequests()
    historyJobs.values.forEach { $0.cancel() }; historyJobs.removeAll()
    session.reset(); raw.removeAll(keepingCapacity: true); latestReceived.removeAll(keepingCapacity: true); lastListUpdate = nil
    startedAt = Date(); firstQuoteMs = nil
    status = online ? .reconnecting : .offline
    onReset?()
    guard online else { return }
    startStream()
    for symbol in visibleRows { requestQuote(symbol) }
    if let chartSymbol { requestQuote(chartSymbol) }
  }

  private func cancelQuotes() {
    quoteJobs.values.forEach { $0.cancel() }; quoteJobs.removeAll()
    quoteQueue.removeAll(); quoteAttempt.removeAll()
  }

  /// 可见行先请求当前报价；已有 WS 值的行不再请求。REST 与 WS 并行，不依赖 REST 成功。
  private func requestQuote(_ symbol: String) {
    guard foreground, (visible || symbol == chartSymbol), online, raw[symbol] == nil, quoteJobs[symbol] == nil,
          !quoteQueue.contains(symbol), quoteQueue.count < 128,
          Date().timeIntervalSince(quoteAttempt[symbol] ?? .distantPast) >= 30 else { return }
    quoteQueue.append(symbol); drainQuotes()
  }

  private func drainQuotes() {
    guard foreground, online else { return }
    while quoteJobs.count < 4, !quoteQueue.isEmpty {
      let symbol = quoteQueue.removeFirst()
      guard raw[symbol] == nil else { continue }
      quoteAttempt[symbol] = Date()
      let request = session.request(symbol), rest = self.rest
      quoteJobs[symbol] = Task { [weak self] in
        let ticker = try? await rest.ticker24h(symbol: symbol, timeout: 5)
        guard let self, !Task.isCancelled, request.generation == self.session.generation else { return }
        self.quoteJobs[symbol] = nil
        if let ticker, self.session.accepts(request, symbol: symbol) { self.ingest([ticker]) }
        self.drainQuotes()
      }
    }
  }

  private func stopStream() {
    pump?.cancel(); pump = nil
    let old = socket; socket = nil; subscribedStreams = []
    Task { await old?.stop() }
  }
}
