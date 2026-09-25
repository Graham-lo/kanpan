import Foundation
import KanpanCore

/// Coinbase 行情推送的一条连接。
///
/// 协议：连上之后按频道发 `{"type":"subscribe","channel":…,"product_ids":[…]}`，
/// 切品种只发 `unsubscribe` / `subscribe`，不重连。另订一个 `heartbeats` 频道：
/// Coinbase 对一段时间没有任何消息的订阅会主动断开，心跳每秒一帧，顺带就是
/// 「传输层还通着」的证据。
///
/// 看门狗和币安那一支同样分层（A-07），每条连接一个常驻任务（不再每收一帧起一组任务）：
/// 1. 传输层：`transportSilenceMs` 内一帧都没有（心跳也没有）就判定断了、重连；
/// 2. 订阅生效：连上之后 `silenceMs` 内一帧行情都没有（订了东西的前提下）就重连；
///    连接已经在推之后**新增**的订阅（切品种）也逐个看：发出 subscribe 之后 `silenceMs` 内
///    这一个频道 × 品种既没有数据也没有订阅应答，就重发一次 subscribe，再等一个窗口还没有才重连。
///    只按整条连接记「来过行情」的话，连接上别的品种在推，新品种那一条订阅没生效就永远发现不了。
/// 3. 第一帧行情到过之后，行情再怎么静默都合法，不拆连接。
///
/// Coinbase 的 `{"type":"error"}` 帧按最近一发控制帧里的那几个频道 × 品种记下来（`topicErrors`）、
/// 写日志；被明确拒掉的订阅不再走「重发 → 重连」那一路。
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
  /// 这条连接上来过任何一帧行情没有（第②层的整条连接那一半）。
  private var gotMarket = false
  /// 这条连接上已经确认生效的订阅：收到过这个频道 × 品种的数据帧，或者订阅应答里列着它。
  private var confirmed: Set<Sub> = []
  /// 连接在推之后新发出去、还没确认的订阅：发出时刻与已经发了几次。
  private var pending: [Sub: (sentMs: Double, attempts: Int)] = [:]
  /// 最近一发控制帧说的是哪几个订阅（`error` 帧按它归属）。
  private var lastControl: (type: String, subs: [Sub]) = ("", [])
  /// 被上游明确拒掉的订阅 → 原因。键是「频道 品种」。测试与诊断用。
  public private(set) var topicErrors: [String: String] = [:]
  private var connectedAtMs = 0.0
  private var lastFrameMs = 0.0
  private var watchdogTask: Task<Void, Never>?
  /// 看门狗或控制帧失败掐掉连接时记下的原因（收帧那边只会看到 socket 被掐的错误）。
  private var cutReason: String?

  public init(urls: [URL], factory: any WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(), silenceMs: Double = 60_000,
              transportSilenceMs: Double = 30_000, log: FeedLog = .silent) {
    self.urls = urls; self.factory = factory; self.pacer = pacer
    self.silenceMs = silenceMs; self.transportSilenceMs = max(1, transportSilenceMs); self.log = log
  }

  public var firstFrameSilenceMs: Double { silenceMs }
  public var currentConnectionID: Int { connectionID }
  /// 退避当前在第几档（测试用）。
  var backoffAttempt: Int { backoff.attempt }

  /// 订阅 → 频道。没有对应频道的（标记价、盘口……能力位里就没有）直接忽略。
  static func subs(_ topics: [StreamTopic]) -> Set<Sub> {
    var out = Set<Sub>()
    for topic in topics {
      let product = CoinbaseDTO.productID(topic.symbol)
      switch topic {
      case .kline(_, let iv) where iv == candleInterval: out.insert(Sub(channel: "candles", product: product))
      case .kline, .trade: out.insert(Sub(channel: "market_trades", product: product))
      case .ticker: out.insert(Sub(channel: "ticker", product: product))
      case .markPrice, .aggTrade, .depth: break
      }
    }
    return out
  }

  // ------------------------------------------------------------------ 生命周期

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    wanted = Self.subs(topics)
    stopped = false
    retire()
    // 换一轮就是一次新的开始：上一轮攒下的退避档位不许带过来。
    backoff.reset()
    topicErrors = [:]
    let (stream, sink) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = sink
    runGeneration += 1
    let generation = runGeneration
    runTask = Task { [weak self] in await self?.loop(generation: generation, sink: sink) }
    return stream
  }

  public func replace(topics: [StreamTopic]) async {
    wanted = Self.subs(topics)
    pending = pending.filter { wanted.contains($0.key) }
    scheduleSync()
  }

  public func stop() async {
    stopped = true
    runGeneration += 1
    runTask?.cancel(); runTask = nil
    watchdogTask?.cancel(); watchdogTask = nil
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sent = []; pending = [:]; continuation = nil
    sink?.yield(.status(.offline)); sink?.finish()
    await dying?.cancel()
  }

  private func retire() {
    runTask?.cancel(); runTask = nil
    watchdogTask?.cancel(); watchdogTask = nil
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sent = []; pending = [:]; continuation = nil
    if let dying { Task { await dying.cancel() } }
    sink?.finish()
  }

  /// 掐掉当前连接，让主循环按退避重连。
  ///
  /// 先把 `socket` 交出去再掐：控制帧同步那一路看到 `socket == nil` 就不会再往这条
  /// 已经判死的连接上重排发送（原来发送失败只是 `return`，由 `defer` 立刻重排，
  /// 对着一条坏掉的连接反复重发，连接却一直不重连）。
  private func reconnect(connection: Int, reason: String) async {
    guard connection == connectionID, let s = socket else { return }
    socket = nil; sent = []; pending = [:]
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    cutReason = reason
    log("Coinbase WS \(reason)")
    await s.cancel()
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
      let group = batch.filter { $0.channel == channel }.sorted()
      lastControl = (type, group)
      do {
        try await send(socket, type: type, channel: channel, products: group.map(\.product))
      } catch {
        // 发不出去就是这条连接坏了：直接重连（新连接会把整套订阅重新发一遍）。
        await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连")
        return
      }
      guard token == syncToken, connection == connectionID else { return }
      if type == "subscribe" {
        sent.formUnion(group)
        // 连接已经在推之后新增的订阅，逐个等它的第一帧（连接刚连上的那一批由整条连接的窗口管）。
        if gotMarket {
          let now = await pacer.nowMs()
          for sub in group where !confirmed.contains(sub) { pending[sub] = (now, 1) }
        }
      } else {
        sent.subtract(group)
        for sub in group { confirmed.remove(sub); pending[sub] = nil }
      }
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
        socket = s; sent = []; gotMarket = false; confirmed = []; pending = [:]; cutReason = nil
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
        log("Coinbase WS 断了：\(cutReason ?? "\(error)")")
      }
      watchdogTask?.cancel(); watchdogTask = nil
      cutReason = nil
      guard generation == runGeneration else { return }
      let dying = socket
      socket = nil; sent = []; pending = [:]
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
    connectedAtMs = await pacer.nowMs()
    lastFrameMs = connectedAtMs
    startWatchdog(s, generation: generation, connection: connection)
    while !stopped, !Task.isCancelled {
      let frame = try await s.receive()
      guard generation == runGeneration, connection == connectionID else { return }
      lastFrameMs = await pacer.nowMs()
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        guard let data = text.data(using: .utf8),
              let decoded = try? Self.decoder.decode(CoinbaseDTO.Frame.self, from: data) else { continue }
        if decoded.type == "error" {
          noteError(decoded.message ?? String(text.prefix(200)))
          continue
        }
        // 这一帧证明了哪些订阅已经生效（数据帧、订阅应答都算；成交快照虽然不折进 K 线，也算）。
        for sub in CoinbaseDTO.confirmedSubs(decoded) {
          let key = Sub(channel: sub.channel, product: sub.product)
          confirmed.insert(key); pending[key] = nil
        }
        let payloads = CoinbaseDTO.payloads(decoded, candleInterval: Self.candleInterval)
        if !payloads.isEmpty, !gotMarket { gotMarket = true; backoff.reset() }
        for p in payloads { sink.yield(.payload(p)) }
      }
    }
  }

  /// `{"type":"error","message":…}`：Coinbase 不说是哪个品种，只能归到最近一发控制帧上。
  /// 被拒的订阅记进 `topicErrors`，并从待确认里拿掉（明确拒了，重发、重连都换不来结果）。
  private func noteError(_ message: String) {
    let subs = lastControl.subs
    guard !subs.isEmpty else {
      log("Coinbase WS 报错：\(message)")
      return
    }
    for sub in subs {
      topicErrors["\(sub.channel) \(sub.product)"] = message
      pending[sub] = nil
    }
    log("Coinbase WS 报错（\(lastControl.type) \(subs.map { "\($0.channel) \($0.product)" }.joined(separator: ", "))）：\(message)")
  }

  /// 看门狗读的那几样。连接换了、停了就给 nil。
  private func watchState(generation: Int, connection: Int)
    -> (lastFrameMs: Double, connectedAtMs: Double, firstFrameDue: Bool, pending: [Sub: (sentMs: Double, attempts: Int)])? {
    guard !stopped, generation == runGeneration, connection == connectionID, socket != nil else { return nil }
    return (lastFrameMs, connectedAtMs, !gotMarket && !wanted.isEmpty, pending)
  }

  /// 单个订阅第一次等超时：只重发这一个的 subscribe，发不出去就重连。
  private func resubscribe(_ sub: Sub, connection: Int) async {
    guard connection == connectionID, let s = socket, sent.contains(sub), wanted.contains(sub),
          let entry = pending[sub] else { return }
    pending[sub] = (await pacer.nowMs(), entry.attempts + 1)
    lastControl = ("subscribe", [sub])
    log("Coinbase WS \(sub.channel) \(sub.product) 订阅后一直没有推送，重发一次 subscribe")
    do { try await send(s, type: "subscribe", channel: sub.channel, products: [sub.product]) }
    catch { await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连") }
  }

  /// 常驻看门狗：每条连接一个任务，按固定节拍醒来看一眼三件事——传输层静默、整条连接的首帧、
  /// 逐个新增订阅的首帧。节拍取两个窗口里小的那个的四分之一，最多晚四分之一个窗口发现。
  private func startWatchdog(_ s: WSSocket, generation: Int, connection: Int) {
    watchdogTask?.cancel()
    let pacer = self.pacer, silence = silenceMs, transport = transportSilenceMs
    let tick = max(1, min(silence, transport) / 4)
    watchdogTask = Task { [weak self] in
      while !Task.isCancelled {
        do { try await pacer.sleep(ms: tick) } catch { return }
        guard let self, let state = await self.watchState(generation: generation, connection: connection) else { return }
        let now = await pacer.nowMs()
        if now - state.lastFrameMs >= transport {
          await self.reconnect(connection: connection,
                               reason: "\(Int(transport / 1000)) 秒没有收到任何推送，主动重连")
          return
        }
        if state.firstFrameDue, now - state.connectedAtMs >= silence {
          await self.reconnect(connection: connection,
                               reason: "\(Int(silence / 1000)) 秒没有收到任何行情，主动重连")
          return
        }
        for (sub, entry) in state.pending.sorted(by: { $0.key < $1.key }) where now - entry.sentMs >= silence {
          if entry.attempts >= 2 {
            await self.reconnect(connection: connection,
                                 reason: "\(sub.channel) \(sub.product) 重发订阅后仍没有推送，重连")
            return
          }
          await self.resubscribe(sub, connection: connection)
        }
      }
    }
  }
}
