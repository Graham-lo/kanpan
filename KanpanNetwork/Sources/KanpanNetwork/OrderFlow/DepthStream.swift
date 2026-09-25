import Foundation
import KanpanCore

/// 深度流上发生的事。`connected` 之后的消息都属于这条新连接，调用方要先让这条连接上的
/// 每本簿换连接号。
public enum DepthStreamEvent: Sendable {
  case connected(Int)
  case messages([VenueMessage])
  case disconnected(String)
}

/// 一条深度连接（上面可能有好几本簿）：拨号、收帧、解码，断了按退避重连；`silenceMs` 内一帧都没有
/// 就当断了；适配器要保活的，连上后按它给的间隔发。
/// 簿怎么维护不归它管（KanpanCore `OrderFlowModel`）；本地簿要求重来时调 `resubscribe(_:)`
/// （适配器能单本重订就只重订那几本，否则整条重拨）或 `reconnect()`。
///
/// 审查第 37 项：
/// - 静默看门狗是每条连接一个常驻任务（记最后收帧时刻，醒来看一眼），不再每收一帧起一个 task group
///   加一个 sleep——BTC 十三本簿每秒一两百帧，那样每秒要建销一两百组任务。
/// - 事件缓冲有上限（`bufferLimit` 条，满了丢最旧的）。真丢了帧，这条连接上的簿就有了断档：
///   主动整条重拨，调用方收到 `.connected` 按新连接重建每本簿，不靠内存兜着越积越多。
public actor DepthStream {
  /// 事件缓冲最多几条（一条是一帧解出来的消息）。按每秒两百帧算约 2.5 秒：调用方卡这么久就算跟不上了。
  public static let bufferLimit = 512
  public let adapter: any DepthFeedAdapter
  let pacer: any Pacer
  let silenceMs: Double
  let log: FeedLog
  private var backoff: Backoff
  private var socket: (any WSSocket)?
  private var task: Task<Void, Never>?
  private var keepAliveTask: Task<Void, Never>?
  private var connection = 0
  /// 主动要求重连：不退避、不算失败。
  private var skipBackoff = false
  /// 拨第几条候选。连上了却一条消息都没收到就断的，下次换下一条（网关主 → 备）。
  private var candidate = 0
  private var gotMessages = false
  /// 当前连接最后一次收到帧（任何帧）的时刻（`pacer.nowMs()` 口径），看门狗读它。
  private var lastFrameMs = 0.0
  private var watchdogTask: Task<Void, Never>?
  /// 看门狗或缓冲溢出掐掉连接时记下的原因（收帧那边只会看到 socket 被掐的错误）。
  private var cutReason: String?
  private let bufferLimit: Int
  /// 生命周期：`idle` → `start` → `running` → `stop` → `stopped`（终态）。
  /// stop 之后再 start 立刻交回一条已结束的流——调用方在 stop 与 start 之间有 actor 跳转，
  /// 晚到的 start 不许把一条没人管的连接重新拉起来。
  public enum RunState: Sendable, Equatable { case idle, running, stopped }
  public private(set) var state: RunState = .idle
  /// 当前这一轮的号：重复 start 或 stop 时加一，旧一轮的收尾（流被丢弃的回调）对不上号就不动新一轮。
  private var run = 0
  private var sink: AsyncStream<DepthStreamEvent>.Continuation?

  public init(adapter: any DepthFeedAdapter, pacer: any Pacer = SystemPacer(), silenceMs: Double = 30_000,
              backoff: Backoff = Backoff(baseMs: 1000, capMs: 30_000), bufferLimit: Int = DepthStream.bufferLimit,
              log: FeedLog = .silent) {
    self.adapter = adapter; self.pacer = pacer; self.silenceMs = silenceMs
    self.backoff = backoff; self.bufferLimit = max(1, bufferLimit); self.log = log
  }

  /// 开始推送；流被丢弃或 `stop()` 就断开。
  /// - `stop()` 之后再调：立刻交回一条已结束的流，不拨号。
  /// - 正在推送时再调：先结束旧的那条流（旧读者的 `for await` 正常退出）、掐掉旧连接，再开新的一轮。
  public func start() -> AsyncStream<DepthStreamEvent> {
    let (stream, sink) = AsyncStream.makeStream(of: DepthStreamEvent.self, bufferingPolicy: .bufferingNewest(bufferLimit))
    guard state != .stopped else { sink.finish(); return stream }
    if state == .running {
      run &+= 1   // 先换号：下面 finish 触发的旧回调对不上号，不会把新一轮 stop 掉
      self.sink?.finish()
      let old = teardown()
      Task { await old?.cancel() }
    }
    run &+= 1
    let id = run
    state = .running
    self.sink = sink
    task = Task { [weak self] in
      await self?.loop(sink)
      sink.finish()
    }
    sink.onTermination = { [weak self] _ in Task { await self?.terminated(run: id) } }
    return stream
  }

  public func stop() async {
    state = .stopped
    run &+= 1
    let old = sink
    sink = nil
    old?.finish()
    await teardown()?.cancel()
  }

  /// 读者把流丢了：只收它自己那一轮。
  private func terminated(run id: Int) async {
    guard id == run, state == .running else { return }
    await stop()
  }

  /// 停掉循环、保活与看门狗，交出当前连接（由调用方去 cancel）。
  private func teardown() -> (any WSSocket)? {
    task?.cancel(); task = nil
    keepAliveTask?.cancel(); keepAliveTask = nil
    watchdogTask?.cancel(); watchdogTask = nil
    let s = socket
    socket = nil
    return s
  }

  /// 掐掉当前连接立刻重拨（流内快照的那家整条连接一个序号，要重新拿 snapshot 只能这样）。
  public func reconnect() async {
    skipBackoff = true
    let s = socket
    socket = nil
    await s?.cancel()
  }

  /// 这几本簿要重新拿流内快照：适配器会单本重订（OKX 退订再订那一个 instId）就只重订它们，
  /// 同一条连接上的别的簿不受影响；不会（或发不出去）就整条重拨。返回 true 表示走的是单本重订。
  @discardableResult
  public func resubscribe(_ venueIDs: [String]) async -> Bool {
    guard let s = socket, !venueIDs.isEmpty else { return false }
    var messages: [String] = []
    for id in venueIDs {
      guard let m = adapter.resubscribeMessages(venueID: id) else { await reconnect(); return false }
      messages += m
    }
    do {
      for m in messages { try await s.send(m) }
      log("深度 \(adapter.name) 单本重订 \(venueIDs.joined(separator: ","))")
      return true
    } catch {
      await reconnect()
      return false
    }
  }

  private func loop(_ sink: AsyncStream<DepthStreamEvent>.Continuation) async {
    while !Task.isCancelled {
      var reason = "连接失败"
      do {
        gotMessages = false
        let s = try await adapter.connect(candidate: candidate)
        guard !Task.isCancelled else { await s.cancel(); return }
        socket = s
        connection += 1
        skipBackoff = false
        cutReason = nil
        log("深度 \(adapter.name) 连上 #\(connection)")
        sink.yield(.connected(connection))
        startKeepAlive(s)
        lastFrameMs = await pacer.nowMs()
        guard !Task.isCancelled else { throw CancellationError() }
        startWatchdog(s, connection: connection)
        try await pump(s, sink)
      } catch {
        reason = cutReason ?? "\(error)"
      }
      // 这一轮已经被 stop / 新的 start 收掉了：连接由它们掐，别再碰共享的状态（那已经是新一轮的）。
      guard !Task.isCancelled else { return }
      cutReason = nil
      keepAliveTask?.cancel(); keepAliveTask = nil
      watchdogTask?.cancel(); watchdogTask = nil
      let dying = socket
      socket = nil
      await dying?.cancel()
      guard !Task.isCancelled else { return }
      sink.yield(.disconnected(reason))
      if !gotMessages { candidate += 1 }
      if skipBackoff {
        skipBackoff = false
        log("深度 \(adapter.name) 断了（\(reason)），立刻重连")
        continue
      }
      let wait = backoff.next()
      log("深度 \(adapter.name) 断了（\(reason)），\(Int(wait))ms 后重连")
      do { try await pacer.sleep(ms: wait) } catch { return }
    }
  }

  /// OKX 这类 30 秒没有帧就断的，照它的要求定时发一句；发不出去就算了，收帧那边会发现连接断了。
  private func startKeepAlive(_ s: any WSSocket) {
    keepAliveTask?.cancel(); keepAliveTask = nil
    guard let keep = adapter.keepAlive, keep.everyMs > 0 else { return }
    let pacer = self.pacer
    keepAliveTask = Task {
      while !Task.isCancelled {
        do { try await pacer.sleep(ms: keep.everyMs) } catch { return }
        guard !Task.isCancelled else { return }
        do { try await s.send(keep.text) } catch { return }
      }
    }
  }

  private func pump(_ s: any WSSocket, _ sink: AsyncStream<DepthStreamEvent>.Continuation) async throws {
    while !Task.isCancelled {
      let frame = try await s.receive()
      lastFrameMs = await pacer.nowMs()
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        let messages = adapter.decode(text)
        guard !messages.isEmpty else { continue }
        backoff.reset()
        gotMessages = true
        if case .dropped = sink.yield(.messages(messages)) {
          // 调用方跟不上，最旧的一帧被挤掉了：这条连接上的簿有了断档，整条重拨、各本簿按新连接重建。
          skipBackoff = true
          throw FeedError.badResponse("处理不过来，缓冲满了丢了帧，整条重订")
        }
      }
    }
  }

  /// 静默看门狗：每条连接一个常驻任务，睡到「最后收帧 + silenceMs」醒来看一眼；这期间来过帧就接着睡到
  /// 新的截止点，没来过就掐掉 socket（`receive()` 不理会任务取消，只有掐掉它挂着的收帧才会带着错误回来）。
  private func startWatchdog(_ s: any WSSocket, connection id: Int) {
    watchdogTask?.cancel()
    let pacer = self.pacer, window = silenceMs
    watchdogTask = Task { [weak self] in
      var wait = window
      while !Task.isCancelled {
        do { try await pacer.sleep(ms: max(1, wait)) } catch { return }
        guard let self else { return }
        let quiet = await pacer.nowMs() - (await self.lastFrameMs)
        if quiet >= window {
          await self.cut(s, connection: id, reason: "\(Int(window / 1000)) 秒没有收到深度推送，主动重连")
          return
        }
        wait = window - quiet
      }
    }
  }

  private func cut(_ s: any WSSocket, connection id: Int, reason: String) async {
    guard id == connection, socket != nil else { return }
    cutReason = reason
    await s.cancel()
  }
}
