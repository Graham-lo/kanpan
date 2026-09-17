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
    switch m {
    case .string(let s): return .text(s)
    case .data(let d): return .text(String(decoding: d, as: UTF8.self))
    @unknown default: return .text("")
    }
  }

  /// `URLSession` 自己回 pong，这儿不用做事；留着是为了回放器能对上。
  func pong() async throws {}

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
    var request = URLRequest(url: url)
    // URLSessionWebSocketTask returns before the TLS/HTTP upgrade completes;
    // put a bound on that handshake too, otherwise a black-holed mobile route
    // can outlive MarketSocketRouter's first-frame race.
    request.timeoutInterval = connectTimeout
    return URLSessionSocket(task: session.webSocketTask(with: request))
  }
}
