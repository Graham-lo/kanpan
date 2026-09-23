import Foundation

/// 一帧。`ping` 单独列出来是因为验收要看到「服务器 ping → 我们回 pong」这件事
/// （A2.8）；真 `URLSession` 会自动回 pong，所以真实现永远不会吐 `.ping`，
/// 回放器会。
public enum WSFrame: Sendable, Equatable {
  case text(String)
  case ping
  case closed(String)
}

/// WebSocket 的最小面。抽出来才能拿录制的报文回放（§12.2 的 `wsreplay`）。
public protocol WSSocket: Sendable {
  func send(_ text: String) async throws
  func receive() async throws -> WSFrame
  func pong() async throws
  func cancel() async
  /// 传输层保活探针：主动发一个 WebSocket ping，在 `timeoutMs` 内收到 pong 就是 true。
  ///
  /// 「行情没更新」和「连接死了」是两件事（A-07）。夜里冷门品种十几分钟不成交，
  /// `@kline` 就真的一帧都不推，这是合法的静默；这时候唯一能分清的办法就是问一句
  /// 传输层还在不在。默认实现回 false——假 socket / 回放器不必都实现，调用方
  /// 看到 false 就退回原来那套「静默即重连」。
  func keepalive(timeoutMs: Double) async -> Bool
}

public extension WSSocket {
  func keepalive(timeoutMs: Double) async -> Bool { false }
}

public protocol WSSocketFactory: Sendable {
  func connect(to url: URL) async throws -> WSSocket
}

// ---------------------------------------------------------------- 真实现

final class URLSessionSocket: WSSocket, @unchecked Sendable {
  private let task: URLSessionWebSocketTask
  init(task: URLSessionWebSocketTask) {
    self.task = task
    task.resume()
  }

  func send(_ text: String) async throws {
    try await task.send(.string(text))
  }

  func receive() async throws -> WSFrame {
    let m = try await task.receive()
    #if DEBUG
      if SimulatedOutage.active {
        task.cancel(with: .goingAway, reason: nil)
        throw URLError(.networkConnectionLost)
      }
    #endif
    switch m {
    case .string(let s): return .text(s)
    case .data(let d): return .text(String(decoding: d, as: UTF8.self))
    @unknown default: return .text("")
    }
  }

  /// `URLSession` 自己回 pong，这儿不用做事；留着是为了回放器能对上。
  func pong() async throws {}

  /// 主动 ping 一次，等对端的 pong。
  ///
  /// `URLSession` 会自动替我们回**服务器**发来的 ping，所以我们永远看不到 `.ping` 帧，
  /// 也就永远不知道这条连接是不是还通着——想知道就只能自己 ping。
  /// 代理黑洞、NAT 超时那种「连接看着还在、其实什么都过不去」的局面，这一发探得出来。
  func keepalive(timeoutMs: Double) async -> Bool {
    guard task.state == .running else { return false }
    #if DEBUG
      if SimulatedOutage.active { return false }
    #endif
    let gate = PingGate()
    return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      gate.arm(cont)
      task.sendPing { error in gate.settle(error == nil) }
      // `sendPing` 的回调在对端不回 pong 时可以一直不来，自己定个上限。
      DispatchQueue.global().asyncAfter(deadline: .now() + max(0.001, timeoutMs / 1000)) {
        gate.settle(false)
      }
    }
  }

  func cancel() async {
    task.cancel(with: .goingAway, reason: nil)
  }
}

public struct URLSessionSocketFactory: WSSocketFactory {
  let session: URLSession
  let connectTimeout: TimeInterval
  public init(session: URLSession = .shared, connectTimeout: TimeInterval = 6) {
    self.session = session; self.connectTimeout = connectTimeout
  }
  public func connect(to url: URL) async throws -> WSSocket {
    #if DEBUG
      if SimulatedOutage.active { throw URLError(.notConnectedToInternet) }
    #endif
    var request = URLRequest(url: url)
    // URLSessionWebSocketTask returns before the TLS/HTTP upgrade completes;
    // put a bound on that handshake too, otherwise a black-holed mobile route
    // can outlive MarketSocketRouter's first-frame race.
    request.timeoutInterval = connectTimeout
    return URLSessionSocket(task: session.webSocketTask(with: request))
  }
}

/// 保活探针的单次放行闸：pong 回来和超时谁先到都只许恢复一次。
private final class PingGate: @unchecked Sendable {
  private let lock = NSLock()
  private var cont: CheckedContinuation<Bool, Never>?
  private var done = false

  func arm(_ cont: CheckedContinuation<Bool, Never>) {
    lock.lock(); self.cont = cont; lock.unlock()
  }

  func settle(_ value: Bool) {
    lock.lock()
    let waiting = done ? nil : cont
    done = true; cont = nil
    lock.unlock()
    waiting?.resume(returning: value)
  }
}
