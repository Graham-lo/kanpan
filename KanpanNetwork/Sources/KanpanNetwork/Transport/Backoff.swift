import Foundation

/// 重连退避的抖动源。可注入，测试里钉死。
public struct BackoffJitter: Sendable {
  /// 取 [-1, 1] 里的一个数，再乘上 `Backoff.jitterFraction` 的幅度。
  public var sample: @Sendable () -> Double
  public init(_ sample: @escaping @Sendable () -> Double) { self.sample = sample }

  /// 线上用：±20% 的随机抖动。
  public static let random = BackoffJitter { Double.random(in: -1...1) }
  /// 不抖（文档、序列、需要确定值的测试）。
  public static let none = BackoffJitter { 0 }
  /// 钉死的抖动：`+1` 是 +20%，`-1` 是 −20%。
  public static func fixed(_ value: Double) -> BackoffJitter {
    BackoffJitter { max(-1, min(1, value)) }
  }
}

/// 重连退避：1s → 2s → 4s → … ≤ 30s，每档再抖 ±20%（§4.4 / A.2）。
///
/// 抖动不是装饰：断线往往是上游或网关整体抖了一下，所有客户端会在同一刻被踢下来。
/// 纯确定性的倍增会让它们在同一毫秒一起回来，把刚缓过来的上游再撞一次
/// （官方明确要求重连要错开）。±20% 足够把这一撮请求摊开，又不至于让用户觉得慢。
public struct Backoff: Sendable, Equatable {
  /// 抖动幅度：±20%。
  public static let jitterFraction = 0.2

  public var baseMs: Double
  public var capMs: Double
  public private(set) var attempt: Int = 0
  /// 抖动源。不参与相等判断（闭包没法比）。
  public var jitter: BackoffJitter

  public init(baseMs: Double = 1000, capMs: Double = 30_000, jitter: BackoffJitter = .random) {
    self.baseMs = baseMs
    self.capMs = capMs
    self.jitter = jitter
  }

  /// 下一次该等多久（含抖动），并把次数 +1。
  public mutating func next() -> Double {
    let d = peek()
    attempt += 1
    let shaken = d * (1 + Self.jitterFraction * jitter.sample())
    // 抖动只在档位内摊开，不越过上限，也不小于 1ms。
    return max(1, min(capMs, shaken))
  }

  /// 只看不动，也不抖：这是这一档的名义值。
  public func peek() -> Double { min(capMs, baseMs * pow(2, Double(attempt))) }

  /// 连上了就归零。
  public mutating func reset() { attempt = 0 }

  /// 一条连接要连着活满多久，断开时才算「稳住过」、把退避清零。
  /// 参照 reconnecting-websocket 的 `minUptime`（默认 5 秒）。
  public static let stableUptimeMs: Double = 5_000

  /// 一条连接收尾时记账：收到过有效数据、**并且**连着活满 `stableMs`，才算稳住过，退避清零；
  /// 否则档位接着往上涨。
  ///
  /// 只看「收到过帧」是不够的（2026-09-26 压测）：服务器或代理连上就推一两帧再踢——超了入站
  /// 限速被踢、中间盒子掐长连接——每条连接都「收到过帧」，每次都清零，退避永远停在第一档，
  /// 客户端 1 秒一次地重连下去。300 条这样的连接档位一直是 1，5 分钟正好 300 条，顶满币安单 IP
  /// 的连接额度。连上就清零更糟（「假连上」），所以两样都要：有数据，而且活得够久。
  public mutating func settle(deliveredData: Bool, uptimeMs: Double,
                              stableMs: Double = Backoff.stableUptimeMs) {
    if deliveredData, uptimeMs >= stableMs { reset() }
  }

  public static func == (lhs: Backoff, rhs: Backoff) -> Bool {
    lhs.baseMs == rhs.baseMs && lhs.capMs == rhs.capMs && lhs.attempt == rhs.attempt
  }

  /// 前 n 次的完整序列。默认不抖——这是文档里那串名义值，
  /// 线上真正发出去的每一档还会再 ±20%（见 `next()`）。
  public static func sequence(_ n: Int, baseMs: Double = 1000, capMs: Double = 30_000,
                              jitter: BackoffJitter = .none) -> [Double] {
    var b = Backoff(baseMs: baseMs, capMs: capMs, jitter: jitter)
    return (0..<n).map { _ in b.next() }
  }
}
