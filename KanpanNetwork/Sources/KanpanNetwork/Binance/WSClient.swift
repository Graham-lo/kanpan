import Foundation
import KanpanCore

/// 一条组合流连接（§4.1 / §4.4）。
///
/// 只有一条连接：切品种、切周期都是 `SUBSCRIBE` / `UNSUBSCRIBE`，不重连。
/// 断线指数退避 1/2/4/…≤30s（每档再抖 ±20%）；服务器 ping 立刻回 pong。
///
/// 看门狗分三层，别把它们混成一件事（A-07）：
///
/// 1. **传输层还通不通**：任何一帧（行情、ping、订阅应答）都算证据；一帧都没有时
///    主动 ping 一次（`keepaliveProbeMs`，10 秒内要有 pong）。只有传输层连续
///    `transportSilenceMs`（30 秒）既没有帧也探不到 pong，才判定断了并重连。
/// 2. **订阅到底生效了没有**：连上之后 `silenceMs` 内一帧有效行情都没有，说明这条
///    连接虽然通、但我们要的流没推过来（`MarketSocketRouter` 选路时那 6 秒同理），
///    这时照旧重连换一条路。
/// 3. **行情有没有变**：第一帧有效行情到过之后，再长的行情静默都是合法的——夜里
///    冷门品种十几分钟不成交，`@kline` 就真的不推。这一层不许再拆连接；价格新不新
///    由展示层（`RoutedMarketFeed` / `QuoteBook` 的过期判定）自己说。
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
  /// 第②③层的窗口：这么久没有一帧**有效行情**就该问一句了。
  /// 第一帧行情之前它是重连门槛，之后它只是保活探针的节拍。
  private let silenceMs: Double
  /// 第①层：传输层连续这么久既没有帧、也探不到 pong，才判定断了。
  private let transportSilenceMs: Double
  /// 一发保活探针最多等多久 pong。
  private let keepaliveProbeMs: Double
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
  /// 当前连接最近一帧**有效行情**的时刻（`nowMs()` 口径），常驻看门狗读它（第②③层）。
  private var lastMarketMs = 0.0
  /// 当前连接最近一帧**任何**报文的时刻（行情、ping、订阅应答都算），第①层的证据。
  private var lastFrameMs = 0.0
  /// 当前连接的常驻看门狗。一条连接一个，不再每收一帧起一组任务。
  private var watchdogTask: Task<Void, Never>?
  /// 看门狗掐掉连接时记下的原因（收帧那边只会看到 socket 被掐的错误）。
  private var cutReason: String?
  /// 不在当前订阅集里、被丢掉的组合流报文数（旧流退订前的尾巴、服务器多推的）。
  public private(set) var droppedForeignFrames = 0

  public init(hosts: BinanceHosts = .default,
              factory: WSSocketFactory = URLSessionSocketFactory(),
              pacer: Pacer = SystemPacer(),
              silenceMs: Double = 60_000,
              transportSilenceMs: Double = 30_000,
              keepaliveProbeMs: Double = 10_000,
              baseBackoffMs: Double = 1000,
              capBackoffMs: Double = 30_000,
              log: FeedLog = .silent) {
    self.hosts = hosts
    self.factory = factory
    self.pacer = pacer
    self.systemClock = pacer is SystemPacer
    self.silenceMs = silenceMs
    self.transportSilenceMs = max(1, transportSilenceMs)
    self.keepaliveProbeMs = max(1, keepaliveProbeMs)
    self.baseBackoffMs = baseBackoffMs
    self.capBackoffMs = capBackoffMs
    self.log = log
    self.backoff = Backoff(baseMs: baseBackoffMs, capMs: capBackoffMs)
  }

  public var currentConnectionID: Int { connectionID }
  public var currentStreams: [String] { streams.sorted() }
  /// 退避当前在第几档（测试用）。
  var backoffAttempt: Int { backoff.attempt }
  /// 真正生效的第②层窗口（毫秒），就是传进来的 `silenceMs`。线路由用户定死、
  /// 一条连接不在几个域名之间竞速，所以不再有「有候选就夹到 15 秒」的钳子。
  public var firstFrameSilenceMs: Double { silenceMs }

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
    // 换一轮就是一次新的开始：上一轮攒下的退避档位不许带过来。否则上一轮断了几次，
    // 新品种的第一次断线就直接从 8 秒、16 秒起跳。
    backoff.reset()
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
    watchdogTask?.cancel(); watchdogTask = nil
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
    watchdogTask?.cancel(); watchdogTask = nil
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
      watchdogTask?.cancel(); watchdogTask = nil
      cutReason = nil
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

  /// 保活探针的状态。**一条连接一份**，不是一帧一份。
  ///
  /// 放在 `receiveFrame` 里当局部变量是错的：服务器每三分钟一个 ping 就让它重新进来
  /// 一次，状态跟着归零，于是整夜行情静默会把同一句「传输层保活正常」刷满日志。
  private actor KeepaliveState {
    enum Phase { case unknown, alive, lost }
    private var phase = Phase.unknown
    /// 状态真的变了才返回 true——日志只在变化时写。
    func enter(_ next: Phase) -> Bool {
      guard phase != next else { return false }
      phase = next
      return true
    }
  }

  /// 收帧，直到断开或被看门狗掐掉。
  ///
  /// 收帧这一路只 `await socket.receive()`：静默判定全交给这条连接的常驻看门狗
  /// （`startWatchdog`）。原来每收一帧都起一组 `withThrowingTaskGroup` 加一个计时任务，
  /// 热门品种一秒几十帧，就是一秒建销几十组任务。
  private func pump(_ s: WSSocket, generation: Int, connection: Int,
                    sink: AsyncStream<WSEvent>.Continuation) async throws {
    let started = await nowMs()
    lastMarketMs = started
    lastFrameMs = started
    cutReason = nil
    // 开 `KANPAN_LOG=1` 时每 5 秒报一次收帧量：连上了但界面不跳的时候，这一行
    // 能立刻分清是「帧根本没来」还是「帧来了但没画出去」。
    var frames = 0
    var reportMs = started
    startWatchdog(s, generation: generation, connection: connection)
    while !stopped, !Task.isCancelled {
      let frame: WSFrame
      do {
        frame = try await s.receive()
      } catch {
        // 看门狗掐的：带上它记下的原因，日志里分得清是「静默」还是「对端断了」。
        if connection == connectionID, let why = cutReason { throw FeedError.badResponse(why) }
        throw error
      }
      // 收帧是挂着等的，一等可能就是几十秒。醒来先确认自己还是当前这一轮、
      // 手上这条连接也还是当前那条：不是的话这条帧属于一条已经退场的连接，
      // 既不该投出去，也不该拿它去清退避。
      guard generation == runGeneration, connection == connectionID else { return }
      lastFrameMs = await nowMs()
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
        // 组合流报文自带流名：不在「现在想要的那套流」里的一律丢掉。退订那一帧在路上的
        // 那一会儿，旧品种、旧周期的报文还会进来，投出去就是新品种的图上跳出旧品种的价。
        // 裸报文（单流连接）没有流名，没法按名过滤，照旧放行。
        if let name = env.stream, !wants(stream: name) {
          droppedForeignFrames += 1
          continue
        }
        lastMarketMs = lastFrameMs
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

  /// 这个组合流名是不是当前订阅集里的。币安回的流名大小写与订阅时一致（`markPrice` 带大写），
  /// 这里仍按不分大小写比，免得网关或上游改了大小写就把整条流当成外来报文丢光。
  private func wants(stream name: String) -> Bool {
    if streams.contains(name) { return true }
    let lowered = name.lowercased()
    return streams.contains { $0.lowercased() == lowered }
  }

  /// 看门狗读的那几样：这条连接还在不在、有没有过有效行情、最近一帧行情 / 任何帧的时刻。
  private func watchState(generation: Int, connection: Int)
    -> (gotFrame: Bool, lastMarketMs: Double, lastFrameMs: Double)? {
    guard !stopped, generation == runGeneration, connection == connectionID, socket != nil else { return nil }
    return (gotFrame, lastMarketMs, lastFrameMs)
  }

  /// 看门狗判死：记下原因再掐 socket。`URLSessionWebSocketTask.receive()` 不理会任务取消，
  /// 只有掐掉它挂着的收帧才会带着错误回来。
  private func cut(_ s: WSSocket, generation: Int, connection: Int, reason: String) async {
    guard generation == runGeneration, connection == connectionID else { return }
    cutReason = reason
    await s.cancel()
  }

  /// 当前时刻，毫秒。真机上走 `MonoClock`，只有测试注了虚拟时钟时才去问 `pacer`。
  private func nowMs() async -> Double {
    systemClock ? MonoClock.nowMs() : await pacer.nowMs()
  }

  /// 常驻静默看门狗：每条连接一个任务，按三层窗口决定「接着睡」还是「判定断了」（A-07）。
  ///
  /// - 第一帧有效行情之前：`silenceMs` 内一帧行情都没有就掐（第②层，连保活都不探）。
  /// - 之后：行情静默合法（第③层）；只在「任何帧」静默满一拍（`min(silenceMs, 传输窗口/2)`）时
  ///   主动 ping 一次。探通了连接留着；探不通隔一拍（`min(拍, 传输窗口/4)`）再探，
  ///   连续 `transportSilenceMs` 既无帧也无 pong 才掐（第①层）。
  ///
  /// 判死那一路**必须先掐 socket**：`receive()` 只认 `cancel()`。反过来，保活探通了就绝不许掐
  /// ——那才是 A-07 说的那个 bug：把「行情没更新」当成「连接死了」。
  /// 探针状态跟着这条连接活（不是每帧一份），整夜静默「保活正常」那句只写一次。
  private func startWatchdog(_ s: WSSocket, generation: Int, connection: Int) {
    watchdogTask?.cancel()
    let pacer = self.pacer
    let log = self.log
    let probeMs = keepaliveProbeMs
    let deadMs = transportSilenceMs
    let firstFrameMs = max(1, silenceMs)
    // 行情静默期间的探针节拍。
    let gap = max(1, min(silenceMs, transportSilenceMs / 2))
    // 探针没答上之后隔多久再探。**不许空转**：和别的等待一样走注入的时钟。
    let probeGap = max(1, min(gap, transportSilenceMs / 4))
    let systemClock = self.systemClock
    let clock: @Sendable () async -> Double = { systemClock ? MonoClock.nowMs() : await pacer.nowMs() }
    let probe = KeepaliveState()
    watchdogTask = Task { [weak self] in
      // 最近一次探针探通的时刻。
      var probedAlive = -Double.greatestFiniteMagnitude
      var window = firstFrameMs
      while !Task.isCancelled {
        do { try await pacer.sleep(ms: max(1, window)) } catch { return }
        guard let self,
              let state = await self.watchState(generation: generation, connection: connection) else { return }
        let now = await clock()
        guard state.gotFrame else {
          // 第②层：订阅没生效。
          let quiet = now - state.lastMarketMs
          if quiet >= firstFrameMs {
            await self.cut(s, generation: generation, connection: connection,
                           reason: "\(Int(quiet / 1000)) 秒没有任何有效行情，主动重连")
            return
          }
          window = firstFrameMs - quiet
          continue
        }
        let sinceAlive = now - max(state.lastFrameMs, probedAlive)
        if sinceAlive < gap {
          // 这一拍里来过帧（或刚探通过）：睡到下一个该探的点。
          window = gap - sinceAlive
          continue
        }
        let quietFor = now - state.lastMarketMs
        if await s.keepalive(timeoutMs: probeMs) {
          // 传输层活着：行情静默是合法的，连接留着，下一拍再探。
          probedAlive = await clock()
          if await probe.enter(.alive) {
            log("WS 行情静默 \(Int(quietFor / 1000))s，传输层保活正常，连接保留")
          }
          window = gap
          continue
        }
        if await probe.enter(.lost) {
          log("WS 保活探针没答上，\(Int(deadMs / 1000)) 秒内再探不通就重连")
        }
        // 探针在路上的那一会儿可能来过帧：重新取一次。
        guard let latest = await self.watchState(generation: generation, connection: connection) else { return }
        let silent = await clock() - max(latest.lastFrameMs, probedAlive)
        guard silent < deadMs else {
          await self.cut(s, generation: generation, connection: connection,
                         reason: "传输层静默 \(Int(silent / 1000)) 秒（既无帧也无 pong），重连")
          return
        }
        // 还没到窗口：隔一拍再探，别急着拆，也别在这儿干转。
        window = min(probeGap, max(1, deadMs - silent))
      }
    }
  }
}
