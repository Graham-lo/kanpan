import Foundation
import KanpanNetwork

// 测试用的假件：网络、时钟、socket 全是注进去的，所以整条网络层和数据层都可以离线跑、
// 在虚拟时间里跑（§12.2）。做成一个库 target，`KanpanNetwork` 与 `KanpanData` 的测试共用。

// ---------------------------------------------------------------- 时钟

/// 完全确定的阶梯时钟：只有谁调了 `sleep` 才走针，不真的等。
/// 顺序执行的用例（限流、退避序列）用它，结果每次都一样。
public actor StepPacer: Pacer {
  private var now: Double
  public private(set) var slept: [Double] = []
  public init(start: Double = 1_000_000) { now = start }
  public func nowMs() async -> Double { now }
  public func sleep(ms: Double) async throws {
    guard ms > 0 else { return }
    slept.append(ms)
    now += ms
    await Task.yield()
  }
  public func advance(_ ms: Double) { now += ms }
  public func sleepLog() -> [Double] { slept }
}

/// 手拨的虚拟时钟：`sleep` 一直挂着，直到测试把针拨过它的醒点。
///
/// 和 `StepPacer` 的差别正是「后台 25 秒宽限」这类用例要的那一点：`StepPacer.sleep`
/// 自己就把针推到醒点再 `yield`，所以那记闹钟在它手上是**立刻**响的，根本摆不出
/// 「24.9 秒就回来了」和「25.1 秒才回来」这两种局面。这把钟只认 `advance`：
/// 没拨够就一直挂着，拨过了才醒，两条分支于是完全确定，一秒真实时间都不用等。
///
/// 取消是认的：挂着的那一笔被 `Task.cancel()` 掐掉会当场抛 `CancellationError`
/// 退场（`enterForeground` 掐后台闹钟走的就是这条路），不会把 continuation 悬在那儿。
public actor ManualPacer: Pacer {
  private struct Waiter {
    var deadline: Double
    var cont: CheckedContinuation<Void, Error>
  }
  private var now: Double
  private var waiters: [Int: Waiter] = [:]
  /// 还没来得及登记就被取消的那些号。
  private var cancelledEarly: Set<Int> = []
  private var nextID = 0
  public private(set) var slept: [Double] = []

  public init(start: Double = 1_000_000) { now = start }

  public func nowMs() async -> Double { now }

  /// 此刻有几个人挂在这把钟上。测试用它确认「那记闹钟真的排上了」再拨针，
  /// 免得拨了个空。
  public var sleeping: Int { waiters.count }
  public func sleepLog() -> [Double] { slept }

  public func sleep(ms: Double) async throws {
    guard ms > 0 else { return }
    slept.append(ms)
    let id = nextID
    nextID &+= 1
    let deadline = now + ms
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        if cancelledEarly.remove(id) != nil || Task.isCancelled {
          c.resume(throwing: CancellationError())
          return
        }
        waiters[id] = Waiter(deadline: deadline, cont: c)
      }
    } onCancel: {
      Task { await self.cancelSleep(id) }
    }
  }

  private func cancelSleep(_ id: Int) {
    if let w = waiters.removeValue(forKey: id) { w.cont.resume(throwing: CancellationError()) }
    else { cancelledEarly.insert(id) }
  }

  /// 把针往前拨。醒点被越过的全部放行，并让它们真的跑起来再返回——
  /// 返回之后测试看到的就是「这段时间过完了」的世界。
  public func advance(_ ms: Double) async {
    now += ms
    let due = waiters.filter { $0.value.deadline <= now }.sorted { $0.value.deadline < $1.value.deadline }
    for (id, w) in due {
      waiters[id] = nil
      w.cont.resume()
    }
    for _ in 0..<20 { await Task.yield() }
  }

  /// 收摊：还挂着的一律放掉。测试结束时必须叫一次——挂着的 `CheckedContinuation`
  /// 要是跟着 actor 一起释放，运行时会直接报 continuation 泄漏。
  public func drain() {
    let all = waiters
    waiters = [:]
    for (_, w) in all { w.cont.resume(throwing: CancellationError()) }
  }
}

/// 快进时钟：真的等，但按 `scale` 缩短（默认 1000×，1 秒 → 1 毫秒）。
/// 涉及多个任务抢跑的用例（WS 静默、重连）用它——真并发、真顺序，只是快。
public struct FastPacer: Pacer {
  public let scale: Double
  private let base: Double
  private let t0: Double
  public init(scale: Double = 0.001, start: Double = 1_000_000) {
    self.scale = scale
    self.base = start
    self.t0 = Double(DispatchTime.now().uptimeNanoseconds) / 1e6
  }
  public func nowMs() async -> Double {
    let real = Double(DispatchTime.now().uptimeNanoseconds) / 1e6 - t0
    return base + real / scale
  }
  public func sleep(ms: Double) async throws {
    guard ms > 0 else { return }
    try await Task.sleep(nanoseconds: UInt64(ms * scale * 1e6))
  }
}

// ---------------------------------------------------------------- HTTP

/// 一次请求的回答，按需要排队。
public actor FakeServer {
  public struct Hit: Sendable {
    public var url: URL
    public var atMs: Double
  }
  private var handler: @Sendable (URL) -> HTTPReply
  public private(set) var hits: [Hit] = []
  private let pacer: Pacer

  public init(pacer: Pacer = SystemPacer(), handler: @escaping @Sendable (URL) -> HTTPReply) {
    self.pacer = pacer
    self.handler = handler
  }

  public func serve(_ url: URL) async -> HTTPReply {
    hits.append(Hit(url: url, atMs: await pacer.nowMs()))
    return handler(url)
  }

  public func urls() -> [URL] { hits.map(\.url) }
  public func times() -> [Double] { hits.map(\.atMs) }
  public func setHandler(_ h: @escaping @Sendable (URL) -> HTTPReply) { handler = h }
}

public struct FakeTransport: HTTPTransport {
  public let server: FakeServer
  public init(_ server: FakeServer) { self.server = server }
  public func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    await server.serve(url)
  }
}

public func json(_ s: String, status: Int = 200, headers: [String: String] = [:]) -> HTTPReply {
  HTTPReply(status: status, headers: headers, body: Data(s.utf8))
}

// ---------------------------------------------------------------- WebSocket

/// 回放脚本的一步。
public enum ReplayStep: Sendable {
  case frame(WSFrame)
  /// 服务器把连接掐了，回放器吐 `.closed`，WS 层该退避重连。
  case drop(String)
  /// 一段什么都不发的静默（虚拟毫秒）。配 `FastPacer` 用。
  case silence(Double)
  /// 停在这儿等测试放行（`gate.open()`）。
  ///
  /// 和 `.silence` 的区别是它不靠时间：要的是「先把 REST 首屏等落地，再让报文进来」
  /// 这种确定的先后，拿一段 300ms 的静默去赌机器够快，正是用例会闪的原因。
  case hold(Gate)
  /// 脚本放完了，之后 `receive()` 一直挂着。
  case hang
}

/// 录制报文的回放器（§12.2 的 `wsreplay`）。
/// 一个 `ReplayDeck` 管着整条脚本，断线重连后从断点继续，这样才能验
/// 「断开 20 秒，期间的报文靠 REST 补回来」。
public actor ReplayDeck {
  private var steps: [ReplayStep]
  private var i = 0
  /// 已经放出去多少步。假 REST server 是同步闭包，拿不到 actor，只能靠这个盒子。
  public nonisolated let cursor = Counter()
  public private(set) var connects = 0
  public private(set) var pongs = 0
  public private(set) var sent: [String] = []
  public private(set) var urls: [URL] = []
  /// 掉线时跳过的报文数，验收日志用。
  public private(set) var skipped = 0

  public init(_ steps: [ReplayStep]) { self.steps = steps }

  func next() -> ReplayStep? {
    guard i < steps.count else { return nil }
    defer { i += 1; _ = cursor.bump() }
    return steps[i]
  }
  public func progress() -> Int { i }
  /// 断线期间「本该收到」的报文：直接吞掉，模拟真丢。
  func skip(while pred: @Sendable (ReplayStep) -> Bool) {
    while i < steps.count, pred(steps[i]) { i += 1; skipped += 1; _ = cursor.bump() }
  }
  func noteConnect(_ url: URL) { connects += 1; urls.append(url) }
  func notePong() { pongs += 1 }
  func noteSend(_ s: String) { sent.append(s) }
  public func stats() -> (connects: Int, pongs: Int, skipped: Int, sent: [String], urls: [URL]) {
    (connects, pongs, skipped, sent, urls)
  }
}

public struct ReplayFactory: WSSocketFactory {
  public let deck: ReplayDeck
  public let pacer: Pacer
  public init(deck: ReplayDeck, pacer: Pacer) { self.deck = deck; self.pacer = pacer }
  public func connect(to url: URL) async throws -> WSSocket {
    await deck.noteConnect(url)
    return ReplaySocket(deck: deck, pacer: pacer)
  }
}

final class ReplaySocket: WSSocket {
  let deck: ReplayDeck
  let pacer: Pacer
  /// 挂起的 `receive()` 靠它叫醒。见 `deafSleep`。
  private let gate = Gate()
  init(deck: ReplayDeck, pacer: Pacer) { self.deck = deck; self.pacer = pacer }

  func send(_ text: String) async throws { await deck.noteSend(text) }
  func pong() async throws { await deck.notePong() }
  func cancel() async { await gate.kill() }

  func receive() async throws -> WSFrame {
    while true {
      guard let step = await deck.next() else {
        // 脚本放完，挂着等测试收工。
        try await deafSleep(ms: 600_000)
        continue
      }
      switch step {
      case .frame(let f): return f
      case .drop(let why): return .closed(why)
      case .silence(let ms): try await deafSleep(ms: ms)
      case .hold(let g): await g.wait()
      case .hang: try await deafSleep(ms: 600_000)
      }
    }
  }

  /// 睡一段，**不理会任务取消**——只有 `cancel()` 叫得醒，叫醒了抛错。
  ///
  /// 真 `URLSessionWebSocketTask.receive()` 就是这个脾气：它是
  /// `withCheckedContinuation` 包出来的，取消所在任务没有任何作用，只有把 socket
  /// 掐了挂着的那一下才会带错误返回。回放器必须照着来——用 `Task.sleep` 的话，
  /// 「静默 60 秒主动重连」（A2.8）在测试里一路绿灯，真机上却是看门狗把自己挂死：
  /// 计时任务抛了错，任务组退出前还得等这条收帧任务，而它永远不回来。
  private func deafSleep(ms: Double) async throws {
    let pacer = self.pacer
    let gate = self.gate
    // 分离任务不继承取消，计时不会被上层的 `cancelAll()` 掐掉。
    let timer = Task.detached { try? await pacer.sleep(ms: ms); await gate.wake() }
    defer { timer.cancel() }
    await gate.wait()
    if await gate.killed { throw FeedError.badResponse("连接已取消") }
  }
}

/// 叫醒闸。`wait()` 里那个 `withCheckedContinuation` 不可取消，正是要点——
/// 真 `URLSessionWebSocketTask.receive()`、真网络请求的回包都是这个脾气：
/// 上层把任务取消了，它照样挂在那儿，回包该来还是会来。并发用例要复现
/// 「旧任务醒来时世界已经变了」，靠的就是这种不理会取消的挂起。
///
/// 三种叫醒方式，语义不同，别混：
/// - `wake()`：把此刻挂着的放行一次，**不落闩**，之后再 `wait()` 还会挂住（回放器的定时唤醒）。
/// - `open()`：落闩放行，之后所有 `wait()` 直接过（「放行这一笔网络请求，后面的也照常走」）。
/// - `kill()`：落闩并标记已取消（socket 被掐）。
public actor Gate {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  public private(set) var killed = false
  private var opened = false
  /// 到过闸门前的次数。测试用来确认「那笔活儿真的被挡住了」再往下走，
  /// 不然就成了靠 sleep 猜时序。
  public private(set) var arrived = 0

  public init() {}

  public func wait() async {
    arrived += 1
    if killed || opened { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  public func wake() {
    let w = waiters
    waiters = []
    for c in w { c.resume() }
  }
  /// 落闩放行：挂着的全部过，之后来的也不再挡。
  public func open() {
    opened = true
    wake()
  }
  public func kill() {
    killed = true
    wake()
  }
  /// 现在有几个挂在闸门上。
  public var waiting: Int { waiters.count }
}

// ---------------------------------------------------------------- 小工具

/// 假 server 的闭包得是 `@Sendable`，计数只好包一层。
public final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  public init() {}
  @discardableResult
  public func bump() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
  public func setTo(_ v: Int) { lock.lock(); n = v; lock.unlock() }
  public var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

/// 等某个条件成立，最多等 `timeout` 秒。actor 里的状态没法同步观察，只能轮询。
public func waitUntil(_ timeout: Double = 5,
                      _ cond: @Sendable () async -> Bool) async -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  while Date() < deadline {
    if await cond() { return true }
    try? await Task.sleep(nanoseconds: 2_000_000)
  }
  return await cond()
}
