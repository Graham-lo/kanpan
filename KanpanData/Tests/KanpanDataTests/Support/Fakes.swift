import Foundation
import Testing
@testable import KanpanData
import KanpanCore

// 测试用的假件：网络、时钟、socket 全是注进去的，所以整套数据层可以离线跑、
// 在虚拟时间里跑（§12.2）。

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
  public let cursor = Counter()
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

/// 一次性的叫醒闸。`wait()` 里那个 `withCheckedContinuation` 不可取消，正是要点。
actor Gate {
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private(set) var killed = false

  func wait() async {
    if killed { return }
    await withCheckedContinuation { waiters.append($0) }
  }
  func wake() {
    let w = waiters
    waiters = []
    for c in w { c.resume() }
  }
  func kill() {
    killed = true
    wake()
  }
}

// ---------------------------------------------------------------- 取 fixture

public enum Fixture {
  public static func url(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/" + (name as NSString).deletingPathExtension,
                      withExtension: (name as NSString).pathExtension)!
  }
  public static func data(_ name: String) -> Data { try! Data(contentsOf: url(name)) }
  public static func text(_ name: String) -> String { String(decoding: data(name), as: UTF8.self) }
  public static func lines(_ name: String) -> [String] {
    text(name).split(separator: "\n").map(String.init)
  }
}

// ---------------------------------------------------------------- 造数据

public func makeBars(t0: Int64, step: Int64, count: Int, base: Double = 100) -> [Bar] {
  (0..<count).map { i in
    let x = base + Double(i)
    return Bar(openTime: t0 + Int64(i) * step, open: x, high: x + 1, low: x - 1,
               close: x + 0.5, volume: Double(10 + i))
  }
}

public func makeSeries(_ symbol: String, _ iv: Interval, count: Int, t0: Int64 = 1_700_000_000_000) -> BarSeries {
  BarSeries(symbol: symbol, interval: iv, bars: makeBars(t0: t0, step: iv.stepMs, count: count))
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
