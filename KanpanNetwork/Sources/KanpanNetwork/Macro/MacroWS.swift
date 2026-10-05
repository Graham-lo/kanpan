import Foundation
import KanpanCore

/// 美元指数推送的一条连接（`kanpan-api` 的 `/v1/market/stream?source=macro`）。
///
/// 协议照币安组合流：连上之后发 `{"method":"SUBSCRIBE","params":["dxy@ticker","dxy@kline_15m"],"id":n}`，
/// 切周期只发 `UNSUBSCRIBE` / `SUBSCRIBE`，不重连；应答是 `{"result":null,"id":n}`，被拒是
/// `{"error":{…},"id":n}`。订上那一刻服务端先推一帧快照，之后**有变化才推**（5 秒采一次），
/// 另外每 15 秒一帧心跳（带 `marketState`）——心跳就是「传输层还通着」的证据。
///
/// 看门狗和另两家同样分层：
/// 1. 传输层：`transportSilenceMs` 内一帧都没有（心跳也没有）就判定断了、重连；
/// 2. 订阅生效：连上之后 `silenceMs` 内一帧行情都没有（订了东西的前提下）就重连；连接已经在推
///    之后新增的订阅逐个看，`silenceMs` 内既没有数据也没有应答就重发一次，再等一个窗口还没有才重连；
/// 3. 第一帧行情到过之后，行情再怎么静默都合法（休市时价格几个小时不动），不拆连接。
///
/// **休市**：行情帧里的 `marketState` 直接折进 `Ticker.marketClosed`；心跳报的开休市和最后
/// 那帧行情不一样时，把那帧行情改了开休市再发一次（时间戳往后挪 1 毫秒，让报价层收下它，
/// 又不挡住服务端下一帧真正的新价）。
public actor MacroWS: MarketStream {
  private let urls: [URL]
  private let factory: any WSSocketFactory
  private let pacer: Pacer
  private let log: FeedLog
  private let silenceMs: Double
  private let transportSilenceMs: Double
  /// 两条控制帧之间至少隔多久。
  private let controlGapMs: Double = 100
  /// 服务端一条连接最多 32 个流。
  static let maxStreams = 32

  private var socket: WSSocket?
  private var wanted: Set<String> = []
  private var sent: Set<String> = []
  private var syncTask: Task<Void, Never>?
  private var syncToken = 0
  private var runTask: Task<Void, Never>?
  private var runGeneration = 0
  private var continuation: AsyncStream<WSEvent>.Continuation?
  private var connectionID = 0
  private var stopped = false
  private var backoff = Backoff()
  private var gotMarket = false
  private var confirmed: Set<String> = []
  private var pending: [String: (sentMs: Double, attempts: Int)] = [:]
  /// 发出去还没应答的控制帧：id → (方法, 流, 连接号)。
  private var controls: [Int: (method: String, streams: [String], connection: Int)] = [:]
  private var nextControlID = 0
  /// 被服务端明确拒掉的流 → 原因。测试与诊断用。
  public private(set) var topicErrors: [String: String] = [:]
  /// 每只品种最后发出去的那帧行情（心跳改开休市时拿它重发）。
  private var lastTicker: [String: Ticker] = [:]
  private var connectedAtMs = 0.0
  private var lastFrameMs = 0.0
  private var watchdogTask: Task<Void, Never>?
  private var cutReason: String?

  public init(urls: [URL], factory: any WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(), silenceMs: Double = 60_000,
              transportSilenceMs: Double = 45_000, log: FeedLog = .silent) {
    self.urls = urls; self.factory = factory; self.pacer = pacer
    self.silenceMs = silenceMs; self.transportSilenceMs = max(1, transportSilenceMs); self.log = log
  }

  public var firstFrameSilenceMs: Double { silenceMs }
  public var currentConnectionID: Int { connectionID }
  var backoffAttempt: Int { backoff.attempt }

  static func streams(_ topics: [StreamTopic]) -> Set<String> {
    Set(topics.compactMap(MacroDTO.streamName).prefix(maxStreams))
  }

  // ------------------------------------------------------------------ 生命周期

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    wanted = Self.streams(topics)
    stopped = false
    retire()
    backoff.reset()
    topicErrors = [:]
    lastTicker = [:]
    let (stream, sink) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = sink
    runGeneration += 1
    let generation = runGeneration
    runTask = Task { [weak self] in await self?.loop(generation: generation, sink: sink) }
    return stream
  }

  public func replace(topics: [StreamTopic]) async {
    wanted = Self.streams(topics)
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
    socket = nil; sent = []; pending = [:]; controls = [:]; continuation = nil
    sink?.yield(.status(.offline)); sink?.finish()
    await dying?.cancel()
  }

  private func retire() {
    runTask?.cancel(); runTask = nil
    watchdogTask?.cancel(); watchdogTask = nil
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sent = []; pending = [:]; controls = [:]; continuation = nil
    if let dying { Task { await dying.cancel() } }
    sink?.finish()
  }

  /// 掐掉当前连接，让主循环按退避重连（先交出 `socket`，同步那一路就不会往死连接上重发）。
  private func reconnect(connection: Int, reason: String) async {
    guard connection == connectionID, let s = socket else { return }
    socket = nil; sent = []; pending = [:]; controls = [:]
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    cutReason = reason
    log("美元指数 WS \(reason)")
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
      // 退订先于订阅（一条连接有 32 个流的上限）。
      let drop = sent.subtracting(wanted), add = wanted.subtracting(sent)
      let (method, batch) = drop.isEmpty ? ("SUBSCRIBE", add.sorted()) : ("UNSUBSCRIBE", drop.sorted())
      do {
        try await send(socket, method: method, streams: batch, connection: connection)
      } catch {
        await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连")
        return
      }
      guard token == syncToken, connection == connectionID else { return }
      if method == "SUBSCRIBE" {
        sent.formUnion(batch)
        if gotMarket {
          let now = await pacer.nowMs()
          for s in batch where !confirmed.contains(s) { pending[s] = (now, 1) }
        }
      } else {
        sent.subtract(batch)
        for s in batch { confirmed.remove(s); pending[s] = nil }
      }
      do { try await pacer.sleep(ms: controlGapMs) } catch { return }
    }
  }

  private func send(_ socket: WSSocket, method: String, streams: [String], connection: Int) async throws {
    nextControlID += 1
    let id = nextControlID
    controls[id] = (method, streams, connection)
    let obj: [String: Any] = ["method": method, "params": streams, "id": id]
    let text = String(decoding: try JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]), as: UTF8.self)
    log("WS → \(text)")
    try await socket.send(text)
  }

  // ------------------------------------------------------------------ 主循环

  private func loop(generation: Int, sink: AsyncStream<WSEvent>.Continuation) async {
    var candidate = 0
    while !stopped, !Task.isCancelled, generation == runGeneration {
      gotMarket = false
      var connected = false
      do {
        guard !urls.isEmpty else { throw FeedError.badResponse("没有可用的推送地址") }
        let url = urls[candidate % urls.count]
        let s = try await factory.connect(to: url)
        guard generation == runGeneration, !Task.isCancelled else { await s.cancel(); return }
        socket = s; sent = []; gotMarket = false; confirmed = []; pending = [:]; controls = [:]; cutReason = nil
        connected = true
        connectionID += 1
        let connection = connectionID
        log("美元指数 WS 连上 #\(connection) \(url.absoluteString)")
        sink.yield(.connected(id: connection))
        sink.yield(.status(.live))
        scheduleSync()
        try await pump(s, generation: generation, connection: connection, sink: sink)
      } catch {
        if stopped || Task.isCancelled { break }
        log("美元指数 WS 断了：\(cutReason ?? "\(error)")")
      }
      guard generation == runGeneration else { return }
      watchdogTask?.cancel(); watchdogTask = nil
      cutReason = nil
      let dying = socket
      socket = nil; sent = []; pending = [:]; controls = [:]
      syncTask?.cancel(); syncTask = nil; syncToken += 1
      await dying?.cancel()
      guard generation == runGeneration, !stopped, !Task.isCancelled else { break }
      if !gotMarket { candidate += 1 }
      sink.yield(.status(.reconnecting))
      if connected {
        backoff.settle(deliveredData: gotMarket, uptimeMs: await pacer.nowMs() - connectedAtMs)
      }
      let wait = backoff.next()
      log("美元指数 WS 退避 \(Int(wait))ms 后重连（第 \(backoff.attempt) 次）")
      do { try await pacer.sleep(ms: wait) } catch { break }
    }
    if !stopped, generation == runGeneration { sink.yield(.status(.offline)) }
  }

  private func pump(_ s: WSSocket, generation: Int, connection: Int,
                    sink: AsyncStream<WSEvent>.Continuation) async throws {
    connectedAtMs = await pacer.nowMs()
    lastFrameMs = connectedAtMs
    startWatchdog(generation: generation, connection: connection)
    while !stopped, !Task.isCancelled {
      let frame = try await s.receive()
      guard generation == runGeneration, connection == connectionID else { return }
      lastFrameMs = await pacer.nowMs()
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        guard let data = text.data(using: .utf8) else { continue }
        handle(MacroDTO.frame(data), connection: connection, sink: sink)
      }
    }
  }

  private func handle(_ frame: MacroDTO.Frame, connection: Int, sink: AsyncStream<WSEvent>.Continuation) {
    switch frame {
    case .ack(let id):
      guard let c = controls.removeValue(forKey: id), c.connection == connection else { return }
      if c.method == "SUBSCRIBE" {
        for s in c.streams where sent.contains(s) { confirmed.insert(s); pending[s] = nil }
      }
    case .error(let id, let message):
      guard let id, let c = controls.removeValue(forKey: id), c.connection == connection else {
        // 归不了属的报错（连接数超限时 id 是 null，服务端随后断开，主循环按退避重连）。
        log("美元指数 WS 报错：\(message)")
        return
      }
      for s in c.streams { topicErrors[s] = message; pending[s] = nil }
      log("美元指数 WS 报错（\(c.method) \(c.streams.joined(separator: ", "))）：\(message)")
    case .heartbeat(_, let closed):
      // 心跳只是传输层的证据，不算行情；开休市变了才把最后那帧行情改了再发。
      for (key, last) in lastTicker where last.marketClosed != closed && wantsTicker(key) {
        var next = last
        next.marketClosed = closed
        next.timeMs = (last.timeMs ?? 0) + 1
        lastTicker[key] = next
        sink.yield(.payload(.ticker(next)))
      }
    case .ticker(var t, let stream):
      note(stream)
      // 服务端只为开休市变了而推的那帧，时间戳可能和上一帧一样；报价层同一时间戳只收一次，
      // 所以往后挪 1 毫秒。
      if let prev = lastTicker[t.symbol], let pt = prev.timeMs, (t.timeMs ?? 0) <= pt,
         prev.marketClosed != t.marketClosed {
        t.timeMs = pt + 1
      }
      if (t.timeMs ?? 0) >= (lastTicker[t.symbol]?.timeMs ?? .min) { lastTicker[t.symbol] = t }
      sink.yield(.payload(.ticker(t)))
    case .kline(let k, let stream):
      note(stream)
      sink.yield(.payload(.kline(k)))
    case .other:
      break
    }
  }

  private func wantsTicker(_ key: String) -> Bool {
    MacroDTO.streamName(.ticker(symbol: key)).map(wanted.contains) == true
  }

  /// 这一帧证明了这个流已经生效。
  private func note(_ stream: String) {
    gotMarket = true
    confirmed.insert(stream); pending[stream] = nil
  }

  private func watchState(generation: Int, connection: Int)
    -> (lastFrameMs: Double, connectedAtMs: Double, firstFrameDue: Bool, pending: [String: (sentMs: Double, attempts: Int)])? {
    guard !stopped, generation == runGeneration, connection == connectionID, socket != nil else { return nil }
    return (lastFrameMs, connectedAtMs, !gotMarket && wanted.contains { topicErrors[$0] == nil }, pending)
  }

  private func resubscribe(_ stream: String, connection: Int) async {
    guard connection == connectionID, let s = socket, sent.contains(stream), wanted.contains(stream),
          let entry = pending[stream] else { return }
    pending[stream] = (await pacer.nowMs(), entry.attempts + 1)
    log("美元指数 WS \(stream) 订阅后一直没有推送，重发一次 SUBSCRIBE")
    do { try await send(s, method: "SUBSCRIBE", streams: [stream], connection: connection) }
    catch { await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连") }
  }

  private func startWatchdog(generation: Int, connection: Int) {
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
                               reason: "\(Int(transport / 1000)) 秒没有收到任何推送（心跳也没有），主动重连")
          return
        }
        if state.firstFrameDue, now - state.connectedAtMs >= silence {
          await self.reconnect(connection: connection,
                               reason: "\(Int(silence / 1000)) 秒没有收到任何行情，主动重连")
          return
        }
        for (stream, entry) in state.pending.sorted(by: { $0.key < $1.key }) where now - entry.sentMs >= silence {
          if entry.attempts >= 2 {
            await self.reconnect(connection: connection, reason: "\(stream) 重发订阅后仍没有推送，重连")
            return
          }
          await self.resubscribe(stream, connection: connection)
        }
      }
    }
  }
}
