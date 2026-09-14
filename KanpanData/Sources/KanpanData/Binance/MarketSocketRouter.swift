import Foundation

/// Select using the first valid market event, never DNS/ping/HTTP upgrade alone.
/// A healthy connection remains selected for its lifetime. Reconnects re-evaluate paths.
public struct MarketSocketRouter: WSSocketFactory {
  private let factory: any WSSocketFactory
  private let fallbacks: [String]
  private let timeoutMs: Double
  private let log: FeedLog

  public init(factory: any WSSocketFactory = URLSessionSocketFactory(), fallbacks: [String],
              timeoutMs: Double = 6000, log: FeedLog = .silent) {
    self.factory = factory; self.fallbacks = fallbacks; self.timeoutMs = timeoutMs; self.log = log
  }

  public func connect(to url: URL) async throws -> any WSSocket {
    var candidates: [URL] = [url]
    for host in fallbacks {
      guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { continue }
      guard let endpoint = URLComponents(string: "wss://\(host)"),
            let name = endpoint.host, endpoint.user == nil, endpoint.password == nil,
            endpoint.path.isEmpty, endpoint.query == nil, endpoint.fragment == nil else { continue }
      parts.host = name
      parts.port = endpoint.port
      if let next = parts.url, !candidates.contains(next) { candidates.append(next) }
    }
    let winner = await withTaskGroup(of: (any WSSocket)?.self) { group in
      for candidate in candidates {
        group.addTask {
          do { return try await probe(candidate) }
          catch { return nil }
        }
      }
      var selected: (any WSSocket)?
      while let result = await group.next() {
        if let result {
          if selected == nil { selected = result; group.cancelAll() }
          else { await result.cancel() }
        }
      }
      return selected
    }
    if Task.isCancelled { await winner?.cancel(); throw CancellationError() }
    guard let winner else { throw FeedError.badResponse("所有行情线路均未收到有效数据") }
    return winner
  }

  private func probe(_ url: URL) async throws -> any WSSocket {
    let start = Date()
    let socket = try await factory.connect(to: url)
    do {
      let frame = try await withTaskCancellationHandler {
        try await withThrowingTaskGroup(of: WSFrame.self) { group in
          group.addTask {
            while true {
              try Task.checkCancellation()
              let frame = try await socket.receive()
              switch frame {
              case .closed: throw FeedError.badResponse("行情线路已关闭")
              case .ping: try await socket.pong()
              case .text(let text):
                guard let payload = try? JSONDecoder().decode(StreamEnvelope.self, from: Data(text.utf8)).payload else { continue }
                switch payload {
                case .kline, .ticker, .tickerBatch, .markPrice, .trade, .bookTicker: return frame
                case .other: continue
                }
              }
            }
          }
          group.addTask {
            try await Task.sleep(for: .milliseconds(timeoutMs))
            await socket.cancel()
            throw FeedError.badResponse("行情线路首帧超时")
          }
          defer { group.cancelAll() }
          return try await group.next()!
        }
      } onCancel: {
        Task { await socket.cancel() }
      }
      try Task.checkCancellation()
      log("WS有效首帧 \(url.host ?? "") \(Int(-start.timeIntervalSinceNow * 1000))ms")
      return PrefetchedMarketSocket(socket: socket, first: frame)
    } catch {
      await socket.cancel()
      throw error
    }
  }
}

/// The winning probe's first event still reaches the feed and cannot be lost at selection.
private actor PrefetchedMarketSocket: WSSocket {
  let socket: any WSSocket
  var first: WSFrame?
  init(socket: any WSSocket, first: WSFrame) { self.socket = socket; self.first = first }
  func receive() async throws -> WSFrame {
    if let frame = first { first = nil; return frame }
    return try await socket.receive()
  }
  func send(_ text: String) async throws { try await socket.send(text) }
  func pong() async throws { try await socket.pong() }
  func cancel() async { await socket.cancel() }
}
