import Foundation
import KanpanCore

/// 深度流上发生的事。`connected` 之后的消息都属于这条新连接，调用方要先让本地簿换连接号。
public enum DepthStreamEvent: Sendable {
  case connected(Int)
  case messages([DepthMessage])
  case disconnected(String)
}

/// 一只品种的一条深度连接：拨号、收帧、解码，断了按退避重连；`silenceMs` 内一帧都没有就当断了。
/// 簿怎么维护不归它管（KanpanCore `OrderFlowModel`）；本地簿要求重来时调 `reconnect()`。
public actor DepthStream {
  public let adapter: any DepthFeedAdapter
  let pacer: any Pacer
  let silenceMs: Double
  let log: FeedLog
  private var backoff: Backoff
  private var socket: (any WSSocket)?
  private var task: Task<Void, Never>?
  private var connection = 0
  /// 主动要求重连：不退避、不算失败。
  private var skipBackoff = false
  /// 拨第几条候选。连上了却一条消息都没收到就断的，下次换下一条（网关主 → 备）。
  private var candidate = 0
  private var gotMessages = false

  public init(adapter: any DepthFeedAdapter, pacer: any Pacer = SystemPacer(), silenceMs: Double = 30_000,
              backoff: Backoff = Backoff(baseMs: 1000, capMs: 30_000), log: FeedLog = .silent) {
    self.adapter = adapter; self.pacer = pacer; self.silenceMs = silenceMs
    self.backoff = backoff; self.log = log
  }

  /// 开始推送。只能调一次；流被丢弃或 `stop()` 就断开。
  public func start() -> AsyncStream<DepthStreamEvent> {
    let (stream, sink) = AsyncStream.makeStream(of: DepthStreamEvent.self, bufferingPolicy: .unbounded)
    task?.cancel()
    task = Task { [weak self] in
      await self?.loop(sink)
      sink.finish()
    }
    sink.onTermination = { [weak self] _ in Task { await self?.stop() } }
    return stream
  }

  public func stop() async {
    task?.cancel(); task = nil
    let s = socket
    socket = nil
    await s?.cancel()
  }

  /// 掐掉当前连接立刻重拨（流内快照的那两家要重新拿 snapshot 只能这样）。
  public func reconnect() async {
    skipBackoff = true
    let s = socket
    socket = nil
    await s?.cancel()
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
        log("深度 \(adapter.upstream) \(adapter.symbol) 连上 #\(connection)")
        sink.yield(.connected(connection))
        try await pump(s, sink)
      } catch {
        reason = "\(error)"
      }
      let dying = socket
      socket = nil
      await dying?.cancel()
      guard !Task.isCancelled else { return }
      sink.yield(.disconnected(reason))
      if !gotMessages { candidate += 1 }
      if skipBackoff {
        skipBackoff = false
        continue
      }
      let wait = backoff.next()
      log("深度 \(adapter.upstream) \(adapter.symbol) 断了（\(reason)），\(Int(wait))ms 后重连")
      do { try await pacer.sleep(ms: wait) } catch { return }
    }
  }

  private func pump(_ s: any WSSocket, _ sink: AsyncStream<DepthStreamEvent>.Continuation) async throws {
    while !Task.isCancelled {
      let frame = try await receive(s)
      switch frame {
      case .ping: try await s.pong()
      case .closed(let why): throw FeedError.badResponse("连接关闭：\(why)")
      case .text(let text):
        let messages = adapter.decode(text)
        guard !messages.isEmpty else { continue }
        backoff.reset()
        gotMessages = true
        sink.yield(.messages(messages))
      }
    }
  }

  /// `receive()` 不理会任务取消：超时要先掐 socket 再报错，挂着的收帧才会回来。
  private func receive(_ s: any WSSocket) async throws -> WSFrame {
    let pacer = self.pacer, window = silenceMs
    return try await withThrowingTaskGroup(of: WSFrame.self) { group in
      group.addTask { try await s.receive() }
      group.addTask {
        try await pacer.sleep(ms: window)
        await s.cancel()
        throw FeedError.badResponse("\(Int(window / 1000)) 秒没有收到深度推送，主动重连")
      }
      let first = try await group.next()!
      group.cancelAll()
      return first
    }
  }
}
