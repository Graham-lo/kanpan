import Foundation
import KanpanCore

/// Coinbase 行情推送的一条连接。
///
/// 协议：连上之后按频道发 `{"type":"subscribe","channel":…,"product_ids":[…]}`，
/// 切品种只发 `unsubscribe` / `subscribe`，不重连。另订一个 `heartbeats` 频道：
/// Coinbase 对一段时间没有任何消息的订阅会主动断开，心跳每秒一帧，顺带就是
/// 「传输层还通着」的证据。
///
/// 看门狗和币安那一支同样分层（A-07）：
/// 1. 传输层：`transportSilenceMs` 内一帧都没有（心跳也没有）就判定断了、重连；
/// 2. 订阅生效：连上之后 `silenceMs` 内一帧行情都没有（订了东西的前提下）就重连；
/// 3. 第一帧行情到过之后，行情再怎么静默都合法，不拆连接。
///
/// 网关线路上连的是 `kanpan-api` 的 hub，它说的是和 Coinbase 一模一样的协议。
public actor CoinbaseWS: MarketStream {
  /// 订阅的最小单位：一个频道上的一个品种。
  struct Sub: Hashable, Comparable {
    var channel: String
    var product: String
    static func < (a: Sub, b: Sub) -> Bool { (a.channel, a.product) < (b.channel, b.product) }
  }

  /// 有原生 K 线推送的那一档（`candles` 频道固定 5 分钟）。
  static let candleInterval: Interval = .m5
  private static let decoder = JSONDecoder()

  private let urls: [URL]
  private let factory: any WSSocketFactory
  private let pacer: Pacer
  private let log: FeedLog
  private let silenceMs: Double
  private let transportSilenceMs: Double
  /// 两条控制帧之间至少隔多久（Coinbase 对入站消息有每秒条数上限）。
  private let controlGapMs: Double = 150

  private var socket: WSSocket?
  private var wanted: Set<Sub> = []
  private var sent: Set<Sub> = []
  private var syncTask: Task<Void, Never>?
  private var syncToken = 0
  private var runTask: Task<Void, Never>?
  private var runGeneration = 0
  private var continuation: AsyncStream<WSEvent>.Continuation?
  private var connectionID = 0
  private var stopped = false
  private var backoff = Backoff()
  private var gotMarket = false

  public init(urls: [URL], factory: any WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(), silenceMs: Double = 60_000,
              transportSilenceMs: Double = 30_000, log: FeedLog = .silent) {
    self.urls = urls; self.factory = factory; self.pacer = pacer
    self.silenceMs = silenceMs; self.transportSilenceMs = max(1, transportSilenceMs); self.log = log
  }

  public var firstFrameSilenceMs: Double { silenceMs }
  public var currentConnectionID: Int { connectionID }

  /// 订阅 → 频道。没有对应频道的（标记价、盘口……能力位里就没有）直接忽略。
  static func subs(_ topics: [StreamTopic]) -> Set<Sub> {
    var out = Set<Sub>()
    for topic in topics {
      let product = CoinbaseDTO.productID(topic.symbol)
      switch topic {
      case .kline(_, let iv) where iv == candleInterval: out.insert(Sub(channel: "candles", product: product))
      case .kline, .trade: out.insert(Sub(channel: "market_trades", product: product))
      case .ticker: out.insert(Sub(channel: "ticker", product: product))
      case .markPrice, .aggTrade, .depth, .bookTicker: break
      }
    }
    return out
  }

  // ------------------------------------------------------------------ 生命周期

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    wanted = Self.subs(topics)
    stopped = false
    retire()
    let (stream, sink) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = sink
    runGeneration += 1
    let generation = runGeneration
    runTask = Task { [weak self] in await self?.loop(generation: generation, sink: sink) }
    return stream
  }

  public func replace(topics: [StreamTopic]) async {
    wanted = Self.subs(topics)
    scheduleSync()
  }

  public func stop() async {
    stopped = true
    runGeneration += 1
    runTask?.cancel(); runTask = nil
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sent = []; continuation = nil
    sink?.yield(.status(.offline)); sink?.finish()
    await dying?.cancel()
  }

  private func retire() {
    runTask?.cancel(); runTask = nil
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sent = []; continuation = nil
    if let dying { Task { await dying.cancel() } }
    sink?.finish()
  }

  // ------------------------------------------------------------------ 订阅同步

  private func scheduleSync() {
    guard socket != nil, syncTask == nil, wanted != sent else { return }
    syncToken += 1
    let token = syncToken
    syncTask = Task { [weak self] in await self?.sync(token: token) }
  }

  private func sync(token: Int) async {
    defer {
      if token == syncToken {
        syncTask = nil
        if !stopped, socket != nil, wanted != sent { scheduleSync() }
      }
    }
    while !stopped, !Task.isCancelled, token == syncToken, let socket, wanted != sent {
      let connection = connectionID
      // 退订先于订阅；一帧只说一个频道。
      let drop = sent.subtracting(wanted), add = wanted.subtracting(sent)
      let (type, batch) = drop.isEmpty ? ("subscribe", add) : ("unsubscribe", drop)
      guard let channel = batch.min()?.channel else { return }
      let group = batch.filter { $0.channel == channel }
      do {
        try await send(socket, type: type, channel: channel, products: group.map(\.product).sorted())
      } catch {
        log("Coinbase 推送控制帧发送失败：\(error)")
        return
      }
      guard token == syncToken, connection == connectionID else { return }
      if type == "subscribe" { sent.formUnion(group) } else { sent.subtract(group) }
      do { try await pacer.sleep(ms: controlGapMs) } catch { return }
    }
  }

  private func send(_ socket: WSSocket, type: String, channel: String, products: [String]) async throws {
    var obj: [String: Any] = ["type": type, "channel": channel]
    if !products.isEmpty { obj["product_ids"] = products }
    let text = String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
    log("WS → \(text)")
    try await socket.send(text)
  }

  // ------------------------------------------------------------------ 主循环

  private func loop(generation: Int, sink: AsyncStream<WSEvent>.Continuation) async {
    var candidate = 0
    while !stopped, !Task.isCancelled, generation == runGeneration {
      do {
        guard !urls.isEmpty else { throw FeedError.badResponse("没有可用的推送地址") }
        let url = urls[candidate % urls.count]
        let s = try await factory.connect(to: url)
        guard generation == runGeneration, !Task.isCancelled else { await s.cancel(); return }
        socket = s; sent = []; gotMarket = false
        connectionID += 1
        let connection = connectionID
        log("Coinbase WS 连上 #\(connection) \(url.absoluteString)")
        try await send(s, type: "subscribe", channel: "heartbeats", products: [])
        sink.yield(.connected(id: connection))
        sink.yield(.status(.live))
        scheduleSync()
        try await pump(s, generation: generation, connection: connection, sink: sink)
      } catch {
        if stopped || Task.isCancelled { break }
        log("Coinbase WS 断了：\(error)")
      }
      guard generation == runGeneration else { return }
      let dying = socket
      socket = nil; sent = []
      syncTask?.cancel(); syncTask = nil; syncToken += 1
      await dying?.cancel()
      guard generation == runGeneration, !stopped, !Task.isCancelled else { break }
      // 没收到过行情就断的那条地址先换一个（网关主 → 备）。
      if !gotMarket { candidate += 1 }
      sink.yield(.status(.reconnecting))
      let wait = backoff.next()
      log("Coinbase WS 退避 \(Int(wait))ms 后重连（第 \(backoff.attempt) 次）")
      do { try await pacer.sleep(ms: wait) } catch { break }
    }
    if !stopped, generation == runGeneration { sink.yield(.status(.offline)) }
  }

  private func pump(_ s: WSSocket, generation: Int, connection: Int,
                    sink: AsyncStream<WSEvent>.Continuation) async throws {
    let connectedAt = await pacer.nowMs()
    var lastFrame = connectedAt
    while !stopped, !Task.isCancelled {
      let now = await pacer.nowMs()
      var window = transportSilenceMs - (now - lastFrame)
      // 订了东西却一帧行情都没来过：订阅没生效，按第②层的窗口重连。
      if !gotMarket, !wanted.isEmpty { window = min(window, silenceMs - (now - connectedAt)) }
      let frame = try await receive(s, withinMs: max(1, window))
      guard generation == runGeneration, connection == connectionID else { return }
      lastFrame = await pacer.nowMs()
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        guard let data = text.data(using: .utf8),
              let decoded = try? Self.decoder.decode(CoinbaseDTO.Frame.self, from: data) else { continue }
        if decoded.type == "error" {
          log("Coinbase WS 报错：\(decoded.message ?? text.prefix(200).description)")
          continue
        }
        let payloads = CoinbaseDTO.payloads(decoded, candleInterval: Self.candleInterval)
        if !payloads.isEmpty, !gotMarket { gotMarket = true; backoff.reset() }
        for p in payloads { sink.yield(.payload(p)) }
      }
    }
  }

  /// 等一帧，`withinMs` 内没有就掐掉连接再报错——`receive()` 不理会任务取消，
  /// 不掐的话挂着的收帧永远不回来（和币安那一支同一个坑）。
  private func receive(_ s: WSSocket, withinMs: Double) async throws -> WSFrame {
    let pacer = self.pacer
    return try await withThrowingTaskGroup(of: WSFrame.self) { group in
      group.addTask { try await s.receive() }
      group.addTask {
        try await pacer.sleep(ms: withinMs)
        await s.cancel()
        throw FeedError.badResponse("\(Int(withinMs / 1000)) 秒没有收到任何推送，主动重连")
      }
      let first = try await group.next()!
      group.cancelAll()
      return first
    }
  }
}
