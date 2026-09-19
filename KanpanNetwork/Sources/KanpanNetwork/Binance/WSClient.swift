import Foundation
import KanpanCore

public enum FeedStatus: String, Sendable, Equatable {
  case live, reconnecting, offline
}

public enum WSEvent: Sendable {
  case payload(StreamPayload)
  /// 每次真的建立了一条新连接。`id` 不变就说明没重连（A2.9）。
  case connected(id: Int)
  case status(FeedStatus)
}

/// 一条组合流连接（§4.1 / §4.4）。
///
/// 只有一条连接：切品种、切周期都是 `SUBSCRIBE` / `UNSUBSCRIBE`，不重连。
/// 断线指数退避 1/2/4/…≤30s；60 秒没帧主动重连；服务器 ping 立刻回 pong。
public actor BinanceWS {
  private let hosts: BinanceHosts
  private let factory: WSSocketFactory
  private let pacer: Pacer
  /// 注进来的是真机那把系统时钟吗？是的话读时刻就不必再 `await` 一次 `pacer`。
  private let systemClock: Bool
  /// 每帧都 `JSONDecoder()` 新建一个：热门品种一秒几十帧，建的全是同一套配置。
  /// 这个类型是线程安全的（只读配置），存成静态的复用。
  private static let decoder = JSONDecoder()
  private let log: FeedLog
  private let silenceMs: Double
  private let baseBackoffMs: Double
  private let capBackoffMs: Double

  private var socket: WSSocket?
  /// 想要订阅的那套流（切一次就改一次，立刻生效，用来过滤旧流的报文）。
  private var streams: Set<String> = []
  /// 服务器在这条连接上已经知道的那套流。和 `streams` 的差就是还欠发的控制帧。
  private var sentStreams: Set<String> = []
  private var syncTask: Task<Void, Never>?
  /// 当前这一发控制帧同步任务的号。控制帧要等一次真的网络往返，醒来时这一轮
  /// 可能早就退场了——号对不上的那一发只许安静收手，不许清句柄、不许改订阅账。
  private var syncToken = 0
  private var lastControlMs: Double = -.greatestFiniteMagnitude
  private var reqID = 0
  private var connectionID = 0
  private var runTask: Task<Void, Never>?
  private var runGeneration = 0
  private var continuation: AsyncStream<WSEvent>.Continuation?
  private var stopped = false
  private var backoff = Backoff()
  /// 这条连接上有没有真收到过帧。连上就清退避是不够的——一连上就被掐的
  /// 「假连上」会把退避永远按在 1 秒，反而是最凶的重连风暴。收到第一帧才算数。
  private var gotFrame = false
  /// 币安对每条连接的**入站**消息限速 10 条/秒，超了不是报错，是直接把你踢下线。
  /// 一次切换要发 UNSUBSCRIBE + SUBSCRIBE 两条，手指一路划过去很容易打满。
  /// 所以控制帧一条一条发、条条隔这么久（4 条/秒，离上限还有一半余量），
  /// 而且睡醒了只看「现在想要哪套流」——中间那些一闪而过的周期自然就被合并掉了。
  private let controlGapMs: Double = 250

  public init(hosts: BinanceHosts = .default,
              factory: WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(),
              silenceMs: Double = 60_000,
              baseBackoffMs: Double = 1000,
              capBackoffMs: Double = 30_000,
              log: FeedLog = .silent) {
    self.hosts = hosts
    self.factory = hosts.streamFallbacks.isEmpty ? factory
      : MarketSocketRouter(factory: factory, fallbacks: hosts.streamFallbacks, log: log)
    self.pacer = pacer
    self.systemClock = pacer is SystemPacer
    self.silenceMs = hosts.streamFallbacks.isEmpty ? silenceMs : min(silenceMs, 15_000)
    self.baseBackoffMs = baseBackoffMs
    self.capBackoffMs = capBackoffMs
    self.log = log
    self.backoff = Backoff(baseMs: baseBackoffMs, capMs: capBackoffMs)
  }

  public var currentConnectionID: Int { connectionID }
  public var currentStreams: [String] { streams.sorted() }

  // ------------------------------------------------------------------ 生命周期

  /// 起一轮。再叫一次就是**换一轮**：旧的那一轮必须在这儿当场收走。
  ///
  /// 原来这儿只是覆盖 `continuation` 和 `runTask` 两个字段，旧的那一轮什么都没动：
  /// 它还挂在 `receive()` 上，旧 socket 还连着服务器。等它醒过来，`continuation?.yield`
  /// 读到的是**新一轮**那份 continuation——旧连接的报文就这么投进了新订阅者的流里
  /// （切品种那一下，新品种的图上会跳出旧品种的价）。旧流也没人收口，订它的人
  /// 永远等不到结束。
  public func start(streams initial: [String]) -> AsyncStream<WSEvent> {
    streams = Set(initial)
    stopped = false
    retireRun()
    let (s, c) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = c
    runGeneration += 1
    let generation = runGeneration
    // 这一轮自带自己的出口：`sink` 是捕获进去的，不再去读那个会被下一轮改掉的字段。
    runTask = Task { [weak self] in await self?.loop(generation: generation, sink: c) }
    return s
  }

  /// 把当前这一轮收走：任务、控制帧、socket、出口各归各位。
  ///
  /// socket 的 `cancel()` 另派一条任务去做，不在这儿等：`start` 是首屏路径上的一步，
  /// 而关一条 WebSocket 要等一次真的往返，等在这儿就是首屏白白多等一个 RTT。
  private func retireRun() {
    runTask?.cancel(); runTask = nil
    syncTask?.cancel(); syncTask = nil
    syncToken += 1
    let dying = socket, sink = continuation
    socket = nil; sentStreams = []; continuation = nil
    if let dying { Task { await dying.cancel() } }
    sink?.finish()
  }

  public func stop() async {
    stopped = true
    runTask?.cancel()
    runTask = nil
    syncTask?.cancel()
    syncTask = nil
    syncToken += 1
    runGeneration += 1
    let oldSocket = socket, oldContinuation = continuation
    socket = nil; sentStreams = []; continuation = nil
    oldContinuation?.yield(.status(.offline)); oldContinuation?.finish()
    await oldSocket?.cancel()
  }

  /// 切品种 / 周期。同一条连接上换流，连接 id 不变。
  public func replaceStreams(_ next: [String]) async {
    streams = Set(next)
    scheduleSync()
  }

  /// 订阅状态是否已经追平（测试用：控制帧是异步发的）。
  public var streamsInSync: Bool { streams == sentStreams }

  private func scheduleSync() {
    guard socket != nil, syncTask == nil, streams != sentStreams else { return }
    syncToken += 1
    let token = syncToken
    syncTask = Task { [weak self, token] in await self?.syncStreams(token: token) }
  }

  private func syncStreams(token: Int) async {
    defer {
      // 只许清自己那份句柄。控制帧卡在网络上的那一会儿，`start` / `stop` 可能已经
      // 换了一轮并派了新的一发——把新那发的句柄清掉，新一轮从此再也排不进控制帧，
      // 订阅就永远追不平了。
      if token == syncToken {
        syncTask = nil
        // A socket send can fail while the connection itself is still present.
        // Leave the desired set intact and retry the diff instead of claiming
        // the server has a subscription it never received.
        if !stopped, socket != nil, streams != sentStreams { scheduleSync() }
      }
    }
    while !stopped, !Task.isCancelled, token == syncToken {
      guard let socket else { return }
      // 这一帧是发给哪条连接的。发完之后要拿它核对：账只能记在自己这条连接上。
      let connection = connectionID
      let want = streams
      guard want != sentStreams else { return }
      let wait = controlGapMs - (await nowMs() - lastControlMs)
      if wait > 0 {
        // 睡完重新取 want——这一觉里切过的那些中间周期就这么被合并掉了。
        do { try await pacer.sleep(ms: wait) } catch { return }
        continue
      }
      // 一觉一帧。退订先于订阅：先把旧流停掉，旧品种的报文就不会再挤进来。
      lastControlMs = await nowMs()
      let drop = sentStreams.subtracting(want)
      if !drop.isEmpty {
        do {
          try await send(socket, method: "UNSUBSCRIBE", params: drop.sorted())
          // 发完这一帧世界可能已经变了：换了一轮、或者重连上了另一条连接。这条退订
          // 属于一条已经退场的连接，拿它去减**当前**这条连接的订阅账，等于凭空宣布
          // 服务器不知道一条它其实知道的流——接着就会在新连接上补一条没人要的
          // SUBSCRIBE（币安对入站控制帧是 10 条/秒，白发的每一条都在挤真需要的那条）。
          guard token == syncToken, connection == connectionID else { return }
          sentStreams.subtract(drop)
        } catch {
          log("WS 控制帧发送失败，保留退订差异：\(error)")
          return
        }
      } else {
        let add = want.subtracting(sentStreams)
        do {
          try await send(socket, method: "SUBSCRIBE", params: add.sorted())
          guard token == syncToken, connection == connectionID else { return }
          sentStreams.formUnion(add)
        } catch {
          log("WS 控制帧发送失败，保留订阅差异：\(error)")
          return
        }
      }
    }
  }

  private func send(_ socket: WSSocket, method: String, params: [String]) async throws {
    reqID += 1
    let obj: [String: Any] = ["method": method, "params": params, "id": reqID]
    let data = try JSONSerialization.data(withJSONObject: obj)
    let text = String(decoding: data, as: UTF8.self)
    log("WS → \(text)")
    try await socket.send(text)
  }

  // ------------------------------------------------------------------ 主循环

  private func loop(generation: Int, sink: AsyncStream<WSEvent>.Continuation) async {
    while !stopped, !Task.isCancelled, generation == runGeneration {
      var connection = 0
      do {
        // 首连用 URL 带上流；重连也一样，省一次 SUBSCRIBE 往返。
        let connectingStreams = streams
        let url = hosts.combinedStream(connectingStreams.sorted())
        let s = try await factory.connect(to: url)
        guard generation == runGeneration, !Task.isCancelled else { await s.cancel(); return }
        socket = s
        // 连接 URL 自己带了流，这套就算服务器已经知道了。
        sentStreams = connectingStreams
        lastControlMs = await nowMs()
        connectionID += 1
        connection = connectionID
        gotFrame = false
        log("WS 连上 #\(connectionID) \(url.absoluteString)")
        sink.yield(.connected(id: connectionID))
        sink.yield(.status(.live))
        scheduleSync()   // 连上那一刻又切走了的话，这里补发
        try await pump(s, generation: generation, connection: connection, sink: sink)
      } catch {
        if stopped || Task.isCancelled { break }
        log("WS 断了：\(error)")
      }
      guard generation == runGeneration else { return }
      // 先把共享字段交出去再去 await。`cancel()` 要等一次真的往返，这中间完全可能
      // 又起了新的一轮（回前台重启 WS 就是这个时序）；放在 await 之后清的话，
      // 清掉的是**新一轮**的 socket 和订阅账——新连接从此发不出任何控制帧，
      // 因为 `scheduleSync` 的第一道门就是 `socket != nil`。
      let dying = socket
      socket = nil
      sentStreams = []
      await dying?.cancel()
      guard generation == runGeneration else { return }
      if stopped || Task.isCancelled { break }
      sink.yield(.status(.reconnecting))
      let wait = backoff.next()
      log("WS 退避 \(Int(wait))ms 后重连（第 \(backoff.attempt) 次）")
      do { try await pacer.sleep(ms: wait) } catch { break }
    }
    if !stopped, generation == runGeneration { sink.yield(.status(.offline)) }
  }

  /// 收帧，直到断开或静默超时。
  private func pump(_ s: WSSocket, generation: Int, connection: Int,
                    sink: AsyncStream<WSEvent>.Continuation) async throws {
    var lastMarketMs = await nowMs()
    // 开 `KANPAN_LOG=1` 时每 5 秒报一次收帧量：连上了但界面不跳的时候，这一行
    // 能立刻分清是「帧根本没来」还是「帧来了但没画出去」。
    var frames = 0
    var reportMs = lastMarketMs
    while !stopped, !Task.isCancelled {
      let remaining = max(1, silenceMs - (await nowMs() - lastMarketMs))
      let frame = try await withSilenceTimeout(s, timeout: remaining) { try await s.receive() }
      // 收帧是挂着等的，一等可能就是几十秒。醒来先确认自己还是当前这一轮、
      // 手上这条连接也还是当前那条：不是的话这条帧属于一条已经退场的连接，
      // 既不该投出去，也不该拿它去清退避。
      guard generation == runGeneration, connection == connectionID else { return }
      switch frame {
      case .ping:
        log("WS ← ping，回 pong")
        try await s.pong()
      case .closed(let why):
        throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        guard let data = text.data(using: .utf8) else { continue }
        guard let env = try? Self.decoder.decode(StreamEnvelope.self, from: data),
              let payload = env.payload else { continue }   // SUBSCRIBE 的应答没有 e 字段，忽略
        if case .other = payload { continue }
        lastMarketMs = await nowMs()
        if !gotFrame { gotFrame = true; backoff.reset() }
        sink.yield(.payload(payload))
        frames += 1
        if lastMarketMs - reportMs >= 5000 {
          log("WS 收帧 \(frames) 条/\(Int(lastMarketMs - reportMs))ms")
          frames = 0; reportMs = lastMarketMs
        }
      }
    }
  }

  /// 当前时刻，毫秒。真机上走 `MonoClock`，只有测试注了虚拟时钟时才去问 `pacer`。
  private func nowMs() async -> Double {
    systemClock ? MonoClock.nowMs() : await pacer.nowMs()
  }

  /// 静默 `silenceMs` 没有任何帧就当断了，主动重连（A2.8）。
  ///
  /// 超时那一路**必须先把 socket 掐掉再抛错**。`URLSessionWebSocketTask.receive()`
  /// 是用 `withCheckedContinuation` 包出来的，不理会任务取消：光让计时任务抛错，
  /// `withThrowingTaskGroup` 退出前还要等那条收帧任务，而它永远不回来——整个
  /// 看门狗就这么被自己挂死。线路被静默丢弃（代理黑洞、NAT 超时）时正是这种局面：
  /// 连接看着还「活着」，60 秒到了也没有任何反应。只有 `cancel()` 能让挂着的
  /// `receive()` 带着错误返回。
  private func withSilenceTimeout(_ socket: WSSocket, timeout: Double,
                                  _ body: @escaping @Sendable () async throws -> WSFrame)
    async throws -> WSFrame
  {
    let pacer = self.pacer
    return try await withThrowingTaskGroup(of: WSFrame.self) { g in
      g.addTask { try await body() }
      g.addTask {
        try await pacer.sleep(ms: timeout)
        await socket.cancel()
        throw FeedError.badResponse("\(Int(timeout / 1000)) 秒没有任何帧，主动重连")
      }
      let first = try await g.next()!
      g.cancelAll()
      return first
    }
  }
}
