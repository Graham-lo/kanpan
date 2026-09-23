import Foundation

/// 一笔请求从「要发」到「拿到」的**总**时限。
///
/// `URLRequest.timeoutInterval` 不是总时限：它是「多久没收到一个字节」的空闲超时，
/// 连接一直在滴答回数据就永远不触发；`URLSession.shared` 的资源超时是七天。
/// 请求在出站之前还要在限流器里排队（`RateLimiter.acquire`），那段等待更是任何
/// 超时都管不到——全市场 24h 行情权重 40，出口 IP 的一分钟账一满就能在队里静静地
/// 等上将近一分钟，页面既没有数、也没有「点此重试」。
///
/// 这里把整段（排队 + 连接 + 收完）包进一个真正的截止时刻：到点就取消这笔、
/// 抛 `URLError(.timedOut)`，调用方按普通失败退避重试。
public enum Deadline {
  public static func run<T: Sendable>(seconds: TimeInterval,
                                      _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    guard seconds.isFinite, seconds > 0 else { return try await operation() }
    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: .seconds(seconds))
        throw URLError(.timedOut)
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw CancellationError() }
      return first
    }
  }
}
