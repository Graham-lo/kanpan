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
    self.silenceMs = hosts.streamFallbacks.isEmpty ? silenceMs : min(silenceMs, 15_000)
    self.baseBackoffMs = baseBackoffMs
    self.capBackoffMs = capBackoffMs
    self.log = log
    self.backoff = Backoff(baseMs: baseBackoffMs, capMs: capBackoffMs)
  }

  public var currentConnectionID: Int { connectionID }
  public var currentStreams: [String] { streams.sorted() }

  // ------------------------------------------------------------------ 生命周期

  public func start(streams initial: [String]) -> AsyncStream<WSEvent> {
    streams = Set(initial)
    stopped = false
    let (s, c) = AsyncStream<WSEvent>.makeStream(bufferingPolicy: .unbounded)
    continuation = c
    runGeneration += 1
    let generation = runGeneration
    runTask = Task { [weak self] in await self?.loop(generation: generation) }
    return s
  }

  public func stop() async {
    stopped = true
    runTask?.cancel()
    runTask = nil
    syncTask?.cancel()
    syncTask = nil
    runGeneration += 1
    let oldSocket = socket, oldContinuation = continuation
    socket = nil; continuation = nil
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
    syncTask = Task { [weak self] in await self?.syncStreams() }
  }

  private func syncStreams() async {
    defer { syncTask = nil }
    while !stopped, !Task.isCancelled {
      guard let socket else { return }
      let want = streams
      guard want != sentStreams else { return }
      let wait = controlGapMs - (await pacer.nowMs() - lastControlMs)
      if wait > 0 {
        // 睡完重新取 want——这一觉里切过的那些中间周期就这么被合并掉了。
        do { try await pacer.sleep(ms: wait) } catch { return }
        continue
      }
      // 一觉一帧。退订先于订阅：先把旧流停掉，旧品种的报文就不会再挤进来。
      lastControlMs = await pacer.nowMs()
      let drop = sentStreams.subtracting(want)
      if !drop.isEmpty {
        sentStreams.subtract(drop)
        try? await send(socket, method: "UNSUBSCRIBE", params: drop.sorted())
      } else {
        let add = want.subtracting(sentStreams)
        sentStreams.formUnion(add)
        try? await send(socket, method: "SUBSCRIBE", params: add.sorted())
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

  private func loop(generation: Int) async {
    while !stopped, !Task.isCancelled, generation == runGeneration {
      do {
        // 首连用 URL 带上流；重连也一样，省一次 SUBSCRIBE 往返。
        let connectingStreams = streams
        let url = hosts.combinedStream(connectingStreams.sorted())
        let s = try await factory.connect(to: url)
        guard generation == runGeneration, !Task.isCancelled else { await s.cancel(); return }
        socket = s
        // 连接 URL 自己带了流，这套就算服务器已经知道了。
        sentStreams = connectingStreams
        lastControlMs = await pacer.nowMs()
        connectionID += 1
        gotFrame = false
        log("WS 连上 #\(connectionID) \(url.absoluteString)")
        continuation?.yield(.connected(id: connectionID))
        continuation?.yield(.status(.live))
        scheduleSync()   // 连上那一刻又切走了的话，这里补发
        try await pump(s)
      } catch {
        if stopped || Task.isCancelled { break }
        log("WS 断了：\(error)")
      }
      guard generation == runGeneration else { return }
      await socket?.cancel()
      socket = nil
      sentStreams = []
      if stopped || Task.isCancelled { break }
      continuation?.yield(.status(.reconnecting))
      let wait = backoff.next()
      log("WS 退避 \(Int(wait))ms 后重连（第 \(backoff.attempt) 次）")
      do { try await pacer.sleep(ms: wait) } catch { break }
    }
    if !stopped, generation == runGeneration { continuation?.yield(.status(.offline)) }
  }

  /// 收帧，直到断开或静默超时。
  private func pump(_ s: WSSocket) async throws {
    var lastMarketMs = await pacer.nowMs()
    while !stopped, !Task.isCancelled {
      let remaining = max(1, silenceMs - (await pacer.nowMs() - lastMarketMs))
      let frame = try await withSilenceTimeout(s, timeout: remaining) { try await s.receive() }
      switch frame {
      case .ping:
        log("WS ← ping，回 pong")
        try await s.pong()
      case .closed(let why):
        throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        guard let data = text.data(using: .utf8) else { continue }
        guard let env = try? JSONDecoder().decode(StreamEnvelope.self, from: data),
              let payload = env.payload else { continue }   // SUBSCRIBE 的应答没有 e 字段，忽略
        if case .other = payload { continue }
        lastMarketMs = await pacer.nowMs()
        if !gotFrame { gotFrame = true; backoff.reset() }
        continuation?.yield(.payload(payload))
      }
    }
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
