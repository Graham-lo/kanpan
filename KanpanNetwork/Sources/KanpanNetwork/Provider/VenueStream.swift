import Foundation
import KanpanCore

// 通用的行情推送：一条连接、多个订阅，切品种只发退订 / 订阅、不重连。**不认识任何一家**——
// 交易所之间的差异全在 `VenueWire` 里（订阅帧怎么拼、一帧怎么解、保活发什么）。
// 从 Coinbase 那一支抽出来（2026-10-08），之后接 OKX / Bybit / Hyperliquid 都实现一个 `<X>Wire`。

/// 控制帧的种类。
public enum VenueControl: String, Sendable {
  case subscribe, unsubscribe
}

/// 应用层保活：每隔 `everyMs` 发一句 `text`（OKX 的 `ping`、Bybit 的 `{"op":"ping"}`）。
/// 回来的 pong 由 `VenueWire.decode` 认成空帧——收到任何一帧都算传输层还通着。
public struct VenueKeepAlive: Sendable, Equatable {
  public var text: String
  public var everyMs: Double
  public init(text: String, everyMs: Double) { self.text = text; self.everyMs = everyMs }
}

/// 一帧推送解出来的东西。
public struct VenueWireFrame<Sub: Sendable>: Sendable {
  /// 统一报文（K 线、24h 行情、成交……），按到达顺序。
  public var payloads: [StreamPayload]
  /// 这一帧证明了哪些订阅已经生效（这个订阅的数据帧、订阅应答都算；心跳、pong 不算）。
  public var confirmed: [Sub]
  /// 上游明确报错（订阅被拒、参数不对……）。nil = 不是报错帧。
  public var error: String?
  /// 报错点名了哪些订阅。nil = 没点名，归到最近一发控制帧上（Coinbase 的 `error` 帧就不说是哪个品种）。
  public var rejected: [Sub]?

  public init(payloads: [StreamPayload] = [], confirmed: [Sub] = [], error: String? = nil, rejected: [Sub]? = nil) {
    self.payloads = payloads; self.confirmed = confirmed; self.error = error; self.rejected = rejected
  }

  /// 心跳、pong、认不出的帧：只说明连接活着。
  public static var ignored: VenueWireFrame { VenueWireFrame() }
}

/// 一家交易所推送协议的全部差异。实现放在那一家的目录（`<X>/<X>Wire.swift`），解码调那一家的 `<X>DTO`。
public protocol VenueWire: Sendable {
  /// 订阅的最小单位（通常是「频道 × 品种」）。排序只用来让控制帧的顺序稳定。
  associatedtype Sub: Hashable, Comparable, Sendable

  /// 日志里的名字（「Coinbase」）。
  var name: String { get }
  /// 两条控制帧之间至少隔多久（毫秒）：交易所对每条连接的入站消息有条数上限，超了直接踢。
  var controlGapMs: Double { get }
  /// 应用层保活。nil = 不发（靠订阅一个心跳频道，或者交易所自己推 ping）。
  var keepAlive: VenueKeepAlive? { get }

  /// 上层的订阅 → 这一家的订阅。没有对应频道的（能力位里本来就没有）直接丢掉。
  func subs(_ topics: [StreamTopic]) -> Set<Sub>
  /// 下一发控制帧带哪几个订阅：从 `pending`（非空）里挑一组能放进一帧的（同一频道、或者不超过 N 个），不能为空。
  func nextBatch(_ pending: Set<Sub>) -> [Sub]
  /// 一发控制帧的正文。
  func control(_ op: VenueControl, _ subs: [Sub]) throws -> String
  /// 连上之后、发任何订阅之前先发的几帧（Coinbase 订 `heartbeats`）。它们招来的报错归不到任何订阅头上。
  func openingFrames() throws -> [String]
  /// 解一帧文本。
  func decode(_ text: String) -> VenueWireFrame<Sub>
  /// 被拒订阅在 `VenueStream.topicErrors` 里的键（诊断与测试用，「ticker BTC-USD」）。
  func label(_ sub: Sub) -> String
}

public extension VenueWire {
  var keepAlive: VenueKeepAlive? { nil }
  func openingFrames() throws -> [String] { [] }
}

/// 一家交易所的一条行情推送连接。
///
/// 看门狗分层（A-07），每条连接一个常驻任务（不再每收一帧起一组任务）：
/// 1. 传输层：`transportSilenceMs` 内一帧都没有（心跳、pong 也没有）就判定断了、重连；
/// 2. 订阅生效：连上之后 `silenceMs` 内一帧行情都没有（订了东西的前提下）就重连；
///    连接已经在推之后**新增**的订阅（切品种）也逐个看：发出 subscribe 之后 `silenceMs` 内
///    这一个订阅既没有数据也没有订阅应答，就重发一次 subscribe，再等一个窗口还没有才重连。
///    只按整条连接记「来过行情」的话，连接上别的品种在推，新品种那一条订阅没生效就永远发现不了。
/// 3. 第一帧行情到过之后，行情再怎么静默都合法，不拆连接。
///
/// 上游的报错帧按 `VenueWireFrame.rejected`（点了名的）或最近一发控制帧里的那几个订阅记进
/// `topicErrors`、写日志；被明确拒掉的订阅不再走「重发 → 重连」那一路，整条连接的首帧窗口也不再等它。
///
/// 网关线路上连的是 kanpan-api 的 hub 或中继，说的是和交易所一模一样的协议，差别只在 URL。
public actor VenueStream<Wire: VenueWire>: MarketStream {
  public typealias Sub = Wire.Sub

  private let wire: Wire
  private let urls: [URL]
  private let factory: any WSSocketFactory
  private let pacer: Pacer
  private let log: FeedLog
  private let silenceMs: Double
  private let transportSilenceMs: Double

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
  /// 这条连接上已经确认生效的订阅：收到过它的数据帧，或者订阅应答里列着它。
  private var confirmed: Set<Sub> = []
  /// 连接在推之后新发出去、还没确认的订阅：发出时刻与已经发了几次。
  private var pending: [Sub: (sentMs: Double, attempts: Int)] = [:]
  /// 最近一发控制帧说的是哪几个订阅（没点名的报错帧按它归属），以及它是在哪一轮、哪条连接上发的。
  ///
  /// 只认当前这一轮、当前这条连接上发的那一帧：新连接上第一发控制帧是开场帧（不记订阅），
  /// 在 `sync` 发出任何订阅之前到来的报错若算到上一条连接、甚至上一轮的那批订阅头上，
  /// 就会把它们错记成「被上游拒了」——于是不再等它们的首帧、不再重发。
  private var lastControl = Control(op: .subscribe, subs: [], generation: 0, connection: 0)
  private struct Control { var op: VenueControl; var subs: [Sub]; var generation: Int; var connection: Int }
  /// 被上游明确拒掉的订阅 → 原因。键是 `Wire.label`。测试与诊断用。
  public private(set) var topicErrors: [String: String] = [:]
  private var connectedAtMs = 0.0
  private var lastFrameMs = 0.0
  private var lastKeepAliveMs = 0.0
  private var watchdogTask: Task<Void, Never>?
  /// 看门狗或控制帧失败掐掉连接时记下的原因（收帧那边只会看到 socket 被掐的错误）。
  private var cutReason: String?

  public init(wire: Wire, urls: [URL], factory: any WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(), silenceMs: Double = 60_000,
              transportSilenceMs: Double = 30_000, log: FeedLog = .silent) {
    self.wire = wire; self.urls = urls; self.factory = factory; self.pacer = pacer
    self.silenceMs = silenceMs; self.transportSilenceMs = max(1, transportSilenceMs); self.log = log
  }

  public var firstFrameSilenceMs: Double { silenceMs }
  public var currentConnectionID: Int { connectionID }
  /// 退避当前在第几档（测试用）。
  var backoffAttempt: Int { backoff.attempt }

  // ------------------------------------------------------------------ 生命周期

  public func start(topics: [StreamTopic]) async -> AsyncStream<WSEvent> {
    wanted = wire.subs(topics)
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
    wanted = wire.subs(topics)
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
  /// 已经判死的连接上重排发送。
  private func reconnect(connection: Int, reason: String) async {
    guard connection == connectionID, let s = socket else { return }
    socket = nil; sent = []; pending = [:]
    syncTask?.cancel(); syncTask = nil; syncToken += 1
    cutReason = reason
    log("\(wire.name) WS \(reason)")
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
      // 退订先于订阅；一帧放多少由那一家定。
      let drop = sent.subtracting(wanted), add = wanted.subtracting(sent)
      let (op, batch) = drop.isEmpty ? (VenueControl.subscribe, add) : (.unsubscribe, drop)
      let group = wire.nextBatch(batch)
      guard !group.isEmpty else { return }
      lastControl = Control(op: op, subs: group, generation: runGeneration, connection: connection)
      do {
        let text = try wire.control(op, group)
        log("WS → \(text)")
        try await socket.send(text)
      } catch {
        // 发不出去就是这条连接坏了：直接重连（新连接会把整套订阅重新发一遍）。
        await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连")
        return
      }
      guard token == syncToken, connection == connectionID else { return }
      if op == .subscribe {
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
      do { try await pacer.sleep(ms: wire.controlGapMs) } catch { return }
    }
  }

  // ------------------------------------------------------------------ 主循环

  private func loop(generation: Int, sink: AsyncStream<WSEvent>.Continuation) async {
    var candidate = 0
    while !stopped, !Task.isCancelled, generation == runGeneration {
      // 每一趟重新算：这一趟没连上的话，「收到过行情」不能沿用上一条连接的——否则连不上的
      // 那条地址永远不会被换掉，退避也会被一条早就断了的好连接清零。
      gotMarket = false
      var connected = false
      do {
        guard !urls.isEmpty else { throw FeedError.badResponse("没有可用的推送地址") }
        let url = urls[candidate % urls.count]
        let s = try await factory.connect(to: url)
        guard generation == runGeneration, !Task.isCancelled else { await s.cancel(); return }
        socket = s; sent = []; gotMarket = false; confirmed = []; pending = [:]; cutReason = nil
        connected = true
        connectionID += 1
        let connection = connectionID
        log("\(wire.name) WS 连上 #\(connection) \(url.absoluteString)")
        // 这条连接的开场帧：不是任何一个订阅，它招来的报错归不到任何订阅头上。
        lastControl = Control(op: .subscribe, subs: [], generation: generation, connection: connection)
        for text in try wire.openingFrames() {
          log("WS → \(text)")
          try await s.send(text)
        }
        sink.yield(.connected(id: connection))
        sink.yield(.status(.live))
        scheduleSync()
        try await pump(s, generation: generation, connection: connection, sink: sink)
      } catch {
        if stopped || Task.isCancelled { break }
        log("\(wire.name) WS 断了：\(cutReason ?? "\(error)")")
      }
      // 先认自己还是不是当前这一轮，再动看门狗和掐线原因（整条 actor 共用）：旧一轮的收帧在换轮之后
      // 带着一帧醒来时 `pump` 是正常返回的，掐掉的不能是新一轮的看门狗。
      guard generation == runGeneration else { return }
      watchdogTask?.cancel(); watchdogTask = nil
      cutReason = nil
      let dying = socket
      socket = nil; sent = []; pending = [:]
      syncTask?.cancel(); syncTask = nil; syncToken += 1
      await dying?.cancel()
      guard generation == runGeneration, !stopped, !Task.isCancelled else { break }
      // 没收到过行情就断的那条地址先换一个（网关主 → 备）。
      if !gotMarket { candidate += 1 }
      sink.yield(.status(.reconnecting))
      // 收到过行情、又连着活满一段才算稳住过，退避清零（见 `Backoff.settle`）。
      if connected {
        backoff.settle(deliveredData: gotMarket, uptimeMs: await pacer.nowMs() - connectedAtMs)
      }
      let wait = backoff.next()
      log("\(wire.name) WS 退避 \(Int(wait))ms 后重连（第 \(backoff.attempt) 次）")
      do { try await pacer.sleep(ms: wait) } catch { break }
    }
    if !stopped, generation == runGeneration { sink.yield(.status(.offline)) }
  }

  private func pump(_ s: WSSocket, generation: Int, connection: Int,
                    sink: AsyncStream<WSEvent>.Continuation) async throws {
    connectedAtMs = await pacer.nowMs()
    lastFrameMs = connectedAtMs
    lastKeepAliveMs = connectedAtMs
    startWatchdog(s, generation: generation, connection: connection)
    while !stopped, !Task.isCancelled {
      let frame = try await s.receive()
      guard generation == runGeneration, connection == connectionID else { return }
      lastFrameMs = await pacer.nowMs()
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        let decoded = wire.decode(text)
        if let message = decoded.error {
          noteError(message, rejected: decoded.rejected, generation: generation, connection: connection)
        }
        // 这一帧证明了哪些订阅已经生效（数据帧、订阅应答都算）。
        for sub in decoded.confirmed {
          confirmed.insert(sub); pending[sub] = nil
        }
        if !decoded.payloads.isEmpty { gotMarket = true }
        for p in decoded.payloads { sink.yield(.payload(p)) }
      }
    }
  }

  /// 报错帧：点了名的就记那几个订阅；没点名的只能归到最近一发控制帧上。
  /// 被拒的订阅记进 `topicErrors`，并从待确认里拿掉（明确拒了，重发、重连都换不来结果）。
  private func noteError(_ message: String, rejected named: [Sub]?, generation: Int, connection: Int) {
    let subs: [Sub]
    if let named, !named.isEmpty {
      subs = named
    } else {
      guard !lastControl.subs.isEmpty, lastControl.generation == generation,
            lastControl.connection == connection else {
        log("\(wire.name) WS 报错：\(message)")
        return
      }
      subs = lastControl.subs
    }
    for sub in subs {
      topicErrors[wire.label(sub)] = message
      pending[sub] = nil
    }
    log("\(wire.name) WS 报错（\(lastControl.op.rawValue) \(subs.map(wire.label).joined(separator: ", "))）：\(message)")
  }

  /// 看门狗读的那几样。连接换了、停了就给 nil。
  private func watchState(generation: Int, connection: Int)
    -> (lastFrameMs: Double, connectedAtMs: Double, firstFrameDue: Bool, pending: [Sub: (sentMs: Double, attempts: Int)])? {
    guard !stopped, generation == runGeneration, connection == connectionID, socket != nil else { return nil }
    return (lastFrameMs, connectedAtMs, !gotMarket && wanted.contains { !rejected($0) }, pending)
  }

  /// 这个订阅被上游明确拒过（`topicErrors` 里有它）。
  ///
  /// 整条连接的首帧窗口只等还有指望的订阅：想要的全被拒了（品种下架、代号不认），
  /// 原来照样「60 秒没有行情 → 重连」，重连上再订、再被拒，每分钟一轮永不停，还每轮把网关主备换一次。
  private func rejected(_ sub: Sub) -> Bool { topicErrors[wire.label(sub)] != nil }

  /// 单个订阅第一次等超时：只重发这一个的 subscribe，发不出去就重连。
  private func resubscribe(_ sub: Sub, connection: Int) async {
    guard connection == connectionID, let s = socket, sent.contains(sub), wanted.contains(sub),
          let entry = pending[sub] else { return }
    pending[sub] = (await pacer.nowMs(), entry.attempts + 1)
    lastControl = Control(op: .subscribe, subs: [sub], generation: runGeneration, connection: connection)
    log("\(wire.name) WS \(wire.label(sub)) 订阅后一直没有推送，重发一次 subscribe")
    do {
      let text = try wire.control(.subscribe, [sub])
      log("WS → \(text)")
      try await s.send(text)
    } catch { await reconnect(connection: connection, reason: "控制帧发送失败（\(error)），重连") }
  }

  /// 应用层保活：到点了就发一句。发不出去就是连接坏了。
  private func keepAliveIfDue(connection: Int, now: Double) async {
    guard let keepAlive = wire.keepAlive, connection == connectionID, let s = socket,
          now - lastKeepAliveMs >= keepAlive.everyMs else { return }
    lastKeepAliveMs = now
    do { try await s.send(keepAlive.text) }
    catch { await reconnect(connection: connection, reason: "保活帧发送失败（\(error)），重连") }
  }

  /// 常驻看门狗：每条连接一个任务，按固定节拍醒来看一眼三件事——传输层静默、整条连接的首帧、
  /// 逐个新增订阅的首帧，顺带按点发保活帧。节拍取两个窗口里小的那个的四分之一（有保活时再不超过保活间隔的
  /// 四分之一），最多晚四分之一个窗口发现。
  private func startWatchdog(_ s: WSSocket, generation: Int, connection: Int) {
    watchdogTask?.cancel()
    let pacer = self.pacer, wire = self.wire, silence = silenceMs, transport = transportSilenceMs
    var tick = max(1, min(silence, transport) / 4)
    if let keepAlive = wire.keepAlive { tick = max(1, min(tick, keepAlive.everyMs / 4)) }
    watchdogTask = Task { [weak self, tick] in
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
                                 reason: "\(wire.label(sub)) 重发订阅后仍没有推送，重连")
            return
          }
          await self.resubscribe(sub, connection: connection)
        }
        await self.keepAliveIfDue(connection: connection, now: now)
      }
    }
  }

}
