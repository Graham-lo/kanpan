import Foundation

/// 一次可见会话内的报价顺序。只保存在内存，旧会话与迟到的 REST 不能覆盖 WS。
struct QuoteSession {
  struct Request: Equatable {
    let generation: Int
    let revision: Int
    let started: Date
  }
  private(set) var generation = 0
  private var revisions: [String: Int] = [:]

  mutating func reset() { generation += 1; revisions.removeAll(keepingCapacity: true) }
  mutating func receive(_ symbol: String) { revisions[symbol, default: 0] += 1 }
  func request(_ symbol: String, now: Date = .now) -> Request {
    Request(generation: generation, revision: revisions[symbol, default: 0], started: now)
  }
  func accepts(_ request: Request, symbol: String, now: Date = .now) -> Bool {
    request.generation == generation && request.revision == revisions[symbol, default: 0]
      && now.timeIntervalSince(request.started) >= 0 && now.timeIntervalSince(request.started) <= 8
  }
}
