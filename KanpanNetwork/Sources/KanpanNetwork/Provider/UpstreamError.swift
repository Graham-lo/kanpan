import Foundation

/// 上游（交易所或网关）的错误。各家 REST 出错时回的错误体都映射成这一个类型，
/// 例如 `{"code":-1120,"msg":"Invalid interval."}`。
///
/// 这个类型是「上游让我们停下」这件事在各层之间唯一的载体，所以它必须把下面这些
/// 一路带上去，谁都不许压扁（第四轮 A-03 / A-05 / A.10）：
///
/// - `retryAfter`：上游说的截止时间（秒）。HTTP `Retry-After` 可以是秒数，也可以是
///   HTTP-date，两种都解（`UpstreamError.retryAfterSeconds`）。
/// - `code`：交易所错误体里的 `code`（例如 `-1003` 是超频）。
/// - `reason`：这是 429 超频、418 IP 封禁、451 地域拒绝，还是本机限流器还在封禁期内
///   （`.blocked`，这一笔根本没有出站）。错误类别丢了，上层就只能把限流当成
///   「行情暂不可用」，然后接着往枪口上撞。
public struct UpstreamError: Error, Sendable, Equatable, CustomStringConvertible {
  /// 这个失败属于哪一类。状态码不够用：网关替上游转述的限流也是 429，
  /// 而本机限流器挡下来的那一笔根本没有 HTTP 响应。
  public enum Reason: String, Sendable, Equatable {
    /// 普通 HTTP 失败（4xx / 5xx）。
    case http
    /// 上游限流：币安 429，或者网关转述的 `upstream_rate_limited`（含 OKX 的 50011）。
    case rateLimited
    /// 418：IP 级封禁，官方给的范围是 2 分钟到 3 天。不是「这个方法各自再试四次」。
    case ipBanned
    /// 本机限流器还在封禁期内，这一笔**没有出站**。
    case blocked
    /// 451：地域拒绝。VPS 上会遇到，手机直连不会。
    case geoBlocked
  }

  public var status: Int
  public var code: Int?
  public var msg: String?
  public var url: String?
  /// 上游给的截止时间（秒）。`.blocked` 上它是「还要等多久」。
  public var retryAfter: TimeInterval?
  public var reason: Reason
  /// 这个信号是网关**替上游转述**的（`X-Kanpan-Upstream: <source>-limited`）。
  ///
  /// 被限的是那台网关的出口 IP，不是我们自己这台手机：本机限流器不该为它罚停
  /// （否则一台网关被限就把直连和另一台网关一起按住），该歇的是那台网关。
  /// 但错误类别仍然是「限流」，业务层照样不叠加重试（A-05）。
  public var proxied: Bool

  public init(status: Int, code: Int? = nil, msg: String? = nil, url: String? = nil,
              retryAfter: TimeInterval? = nil, reason: Reason? = nil, proxied: Bool = false) {
    self.status = status; self.code = code; self.msg = msg; self.url = url
    self.retryAfter = retryAfter
    self.reason = reason ?? Self.reason(for: status)
    self.proxied = proxied
  }

  /// 状态码推出来的默认类别。显式传 `reason` 的地方（网关转述、限流器）优先。
  public static func reason(for status: Int) -> Reason {
    switch status {
    case 418: return .ipBanned
    case 429: return .rateLimited
    case 451: return .geoBlocked
    default: return .http
    }
  }

  /// 本机限流器挡下来的一笔：上游的封禁还没到期，这一笔连出站都没有。
  ///
  /// 状态码记 429，这样既有的「限流不算单品种问题」那类判断（`RoutedMarketFeed.skippable`）
  /// 不用改也仍然成立。
  public static func blocked(seconds: TimeInterval, upstreamStatus: Int = 429,
                             url: String? = nil) -> UpstreamError {
    UpstreamError(status: 429, code: nil,
                 msg: "上游封禁未解除（\(upstreamStatus)），还要等 \(wholeSeconds(seconds)) 秒",
                 url: url, retryAfter: sanitizedRetryAfter(seconds) ?? 0, reason: .blocked)
  }

  public var description: String {
    var s = "HTTP \(status)"
    if reason != .http { s += " \(reason.rawValue)" }
    if let code { s += " code=\(code)" }
    if let retryAfter { s += " retryAfter=\(Self.wholeSeconds(retryAfter))s" }
    if let msg { s += " \(msg)" }
    if let url { s += " \(url)" }
    return s
  }

  /// 归档站对「这天没有数据」的回答就是 404，不是错误，调用方要能分辨。
  public var isNotFound: Bool { status == 404 }
  /// 418 是被 ban，429 是超频。两者都读 `Retry-After`（§4.1）。
  /// 本机限流器挡下来的那一笔也算——它的成因就是这两个。
  public var isRateLimited: Bool {
    reason == .rateLimited || reason == .ipBanned || reason == .blocked || status == 429 || status == 418
  }
  /// 418：IP 级封禁，停的是整个出口，不是某一个方法。
  public var isIPBan: Bool { reason == .ipBanned }
  /// 这一笔是被本机限流器挡下来的，没有出站。
  public var isBlocked: Bool { reason == .blocked }
  /// 地区封锁。VPS 上会遇到，手机直连不会。
  public var isGeoBlocked: Bool { reason == .geoBlocked || status == 451 }

  /// 「短时间内不可能取得结果」。
  ///
  /// 业务层（`MarketFeed.fillOnce` 的退避重试、`RoutedMarketFeed` 的预热）遇到它
  /// 必须**结束本轮**：各家 REST 客户端的 `fetch` 那一层已经按上游给的截止时间处理过了，
  /// 再在外面叠一圈只是把同一个封禁撞成 3×4＝12 次（A.3.4）。
  ///
  /// 451 地域拒绝也在里面：它比限流更没救——这条线路的出口被按地区拒了，退避几秒
  /// 再打一遍（而且每一遍还要把两台网关都竞速一次）结果一模一样。该做的是把
  /// 「点此重试」交回用户，让他换线路。
  public var stopsRetrying: Bool {
    reason == .ipBanned || reason == .blocked || reason == .rateLimited || reason == .geoBlocked
  }

  // ---------------------------------------------------------------- Retry-After

  /// `Retry-After` → 秒。官方允许两种写法：`120` 和 `Wed, 21 Oct 2026 07:28:00 GMT`。
  /// 只读秒数的话，发 HTTP-date 的那一边就等于没给（A-03）。
  public static func retryAfterSeconds(_ raw: String?, now: Date = Date()) -> TimeInterval? {
    guard let text = raw?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
    if let seconds = Double(text) { return sanitizedRetryAfter(seconds) }
    for formatter in httpDateFormatters {
      if let date = formatter.date(from: text) {
        return sanitizedRetryAfter(date.timeIntervalSince(now))
      }
    }
    return nil
  }

  /// 上游说的「歇多久」最多听多久：币安文档里 IP 封禁最长 3 天。
  ///
  /// 原来 `Retry-After` 解出来是多少就用多少：`inf`、`1e400`、`1e30`、年份 9999 的
  /// HTTP-date 都原样往下传，第一个 `Int(x.rounded(.up))`（日志、错误文案）或
  /// `UInt64(ms * 1e6)`（`SystemPacer.sleep`）当场让整个 app 闪退；有限但巨大的值
  /// 则把进程共用的限流器封到几十年后，只有杀进程才解。代理、强制门户、
  /// 配错的网关都可能吐出这种头，所以在入口把它收成「有限、正、至多 3 天」。
  public static let maxRetryAfterSeconds: TimeInterval = 3 * 86_400

  /// 非有限、非正 → nil（等于没给）；过大 → 封顶。
  public static func sanitizedRetryAfter(_ seconds: Double?) -> TimeInterval? {
    guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
    return min(seconds, maxRetryAfterSeconds)
  }

  /// 秒数 → 给人看的整数秒。任何 Double 进来都不会崩（`Int(inf)` 会）。
  static func wholeSeconds(_ seconds: Double) -> Int {
    guard seconds.isFinite else { return seconds > 0 ? Int(maxRetryAfterSeconds) : 0 }
    return Int(min(max(seconds, -maxRetryAfterSeconds), maxRetryAfterSeconds).rounded(.up))
  }

  /// HTTP-date 的三种写法（RFC 9110 §5.6.7）。`DateFormatter` 不便宜，建一次存着。
  private static let httpDateFormatters: [DateFormatter] = {
    ["EEE, dd MMM yyyy HH:mm:ss zzz",      // IMF-fixdate
     "EEEE, dd-MMM-yy HH:mm:ss zzz",       // RFC 850
     "EEE MMM d HH:mm:ss yyyy"]            // asctime
      .map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        f.dateFormat = format
        return f
      }
  }()
}

public enum FeedError: Error, Sendable, Equatable {
  case badResponse(String)
  case cancelled
  case notConnected
  /// 这家交易所没有这项能力（现货没有资金费率、持仓量……）。上层按能力位本来就不会来问，
  /// 真撞上了就是调用方漏看了能力位。
  case unsupported(String)
  /// 断档超过 `contiguousTail` 的翻页能力（`ProviderCapabilities.maxTailBars`）：接不上了，
  /// 上层应整段重拉一屏换掉，而不是一遍遍重试补缺。
  case gapTooLong
}
