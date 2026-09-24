import KanpanCore
import Foundation

// ============================================================ 服务器支持集合的镜像
//
// 复盘的「能不能记」这件事，权威在服务端：
// `Backend/kanpan-api/vendor/scorebook-core/src/domain/native_review.rs` 的
// `validate_range` / `validate`。客户端原来只校验「至少 3 根、到期晚于现在、
// 多空价格关系」，比服务端宽得多——于是 BTCUSDC、1501 根、超长正文这些**本地过关、
// 服务端必拒**的请求照样入队，堵在队首（审查 B-06 + B-02）。
//
// 这一份是那份规则在客户端的镜像，**保存前就挡住**永远发不出去的记录。它只做
// 「拦截」，不做「放行」：服务端那一份一个字都不能少，它才是裁定证据完整性的地方。
//
// 两份写在两种语言里，就一定会有人只改一边。`ReviewContractReconciliationTests`
// 直接读那个 `.rs` 文件，逐条比对下面这些常量，对不上就红。

/// 复盘支持的 K 线周期。
///
/// 这是 `interval.rs` 那 15 个币安合约周期的镜像，**和 `KanpanCore.Interval` 不是
/// 一回事**：后者是图表自己的周期表，有服务端不认的 `1y`，也少了 `8h` / `3d`。
/// 复盘范围必须按这一份算，不能拿图表那份去猜。
public enum ReviewInterval: String, Sendable, Codable, CaseIterable {
  case m1 = "1m", m3 = "3m", m5 = "5m", m15 = "15m", m30 = "30m"
  case h1 = "1h", h2 = "2h", h4 = "4h", h6 = "6h", h8 = "8h", h12 = "12h"
  case d1 = "1d", d3 = "3d", w1 = "1w", mo1 = "1M"

  /// 一根有多少秒。月线长度随月份变，没有固定秒数（和 Rust 侧 `fixed_seconds` 一致）。
  public var fixedSeconds: Int64? {
    switch self {
    case .m1: 60; case .m3: 180; case .m5: 300; case .m15: 900; case .m30: 1800
    case .h1: 3600; case .h2: 7200; case .h4: 14400; case .h6: 21600; case .h8: 28800
    case .h12: 43200; case .d1: 86400; case .d3: 259_200; case .w1: 604_800
    case .mo1: nil
    }
  }

  /// `[start, end)` 里装得下多少根完整 K 线（毫秒时间戳）。
  ///
  /// 固定长度周期按秒数整除，和 Rust 的 `(end - start).num_seconds().div_euclid(step)`
  /// 逐位一致：毫秒先向零截断成秒，再向下取整除。月线只能按日历加减——2 月 28 天、
  /// 3 月 31 天，拿 30 天去除一定会算错根数，而服务端正是拿这个数和 `bars` 比对。
  public func barsBetween(start: Int64, end: Int64) -> Int64 {
    if let step = fixedSeconds {
      return Self.floorDiv((end - start) / 1000, step)
    }
    return UTCCalendar.wholeMonths(from: start, to: end)
  }

  private static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let quotient = a / b, remainder = a % b
    return remainder != 0 && ((remainder < 0) != (b < 0)) ? quotient - 1 : quotient
  }
}

/// 服务端 `native_review.rs` 里那些常量，逐条搬过来。
public enum ReviewContract {
  /// 服务端 `validate_range` 收的那几个市场（`ReviewContractReconciliationTests` 对着 `.rs` 比）。
  ///
  /// 「这个市场能不能复盘」全客户端只问这一处（`supports`）：捕获入口
  /// （`ReviewChartBridge.beginCapture` → `captureFailure`）和复盘到点提醒
  /// （`ReviewDueAlerts.Item.init(record:)` 的 `eligible`）以前各判一遍，后者只认币安，
  /// 于是现货（`coinbase/spot`）的记录能记、到点却不进提醒总表（审查 2026-09-24 §2）。
  ///
  /// 为什么是镜像而不是开机问服务端要能力表：服务端没有这样的端点，而捕获入口是离线也要
  /// 当场给答案的（圈之前就说「不支持」）；多一次往返换来的只是把同一张两项的表从编译期
  /// 挪到运行期。镜像的风险是两边漂移，那由上面那条对账测试兜住。
  public static let supportedMarkets = [InstrumentID.defaultMarketKey, "coinbase/spot"]
  public static let venue = InstrumentID.defaultVenue
  public static let market = InstrumentID.defaultMarket

  /// 这个市场的品种能不能记复盘。
  public static func supports(_ id: InstrumentID) -> Bool { supportedMarkets.contains(id.marketKey) }
  public static let quoteSuffix = "USDT"
  public static let symbolMaxLength = 40
  public static let minBars = 3
  public static let maxBars = 1500
  public static let ruleVersion = "criteria-v2"
  public static let directions = ["long", "short", "observe"]
  public static let confirmations = ["bar_close", "trade_touch"]
  public static let origins = ["chart_first", "thought_first", "interwoven", "unknown"]
  public static let confidences = [50, 60, 70, 80, 90]
  /// 本机时钟最多可以比服务器快多少（服务端：`draft.created > now + 60_000` 就拒）。
  public static let createdAheadMillis: Int64 = 60_000
  /// 正文按 **UTF-8 字节**算，不是字符数——服务端量的是 `String::len()`。
  public static let textMaxBytes = 64_000
  /// 图表设置 / 画线快照在线上是 Base64 字符串，服务端量的是那串字符的长度。
  public static let chartSettingsMaxBytes = 128_000
  public static let drawingSnapshotMaxBytes = 256_000
  /// 到期最远 366 天。
  public static let horizonMaxMillis: Int64 = 366 * 86_400_000
  /// 支持的周期字符串，按时长升序。
  public static var intervals: [String] { ReviewInterval.allCases.map(\.rawValue) }

  /// Base64 编码之后有多少字符。
  public static func base64Length(_ data: Data) -> Int { (data.count + 2) / 3 * 4 }

  /// **还没圈之前**就能判死的那三样：交易所、品种、周期。
  ///
  /// 圈完 48 根、写完两百字，按保存才被告知「这个品种不支持」，那两百字是白写的。
  /// 捕获入口先问这一句，不支持就当场说，连捕获模式都不进（审查 B-06）。
  public static func captureFailure(venue: String, market: String = market, symbol: String, interval: String) -> String? {
    guard ReviewInterval(rawValue: interval) != nil else { return "这个周期暂不支持复盘，请切换周期" }
    let id = symbol.contains("/") ? InstrumentID(symbol) : InstrumentID(venue: venue, market: market, symbol: symbol)
    guard supports(id), id.isValid else { return "这个市场暂不支持复盘" }
    let info = SymbolInfo.placeholder(symbol: id.key)
    guard (symbol.contains("/") || symbol == id.symbol), id.symbol.count <= symbolMaxLength,
          (id.isDefaultMarket && info.quote == quoteSuffix && !id.symbol.contains("-")) || (id.market == "spot" && info.quote == "USD" && id.symbol.contains("-")) else { return "这个品种暂不支持复盘" }
    return nil
  }

  /// 框选的这一段能不能记（对应服务端 `validate_range`）。返回给人看的一句话，`nil` 是通过。
  public static func rangeFailure(_ range: ReviewRange, cutoff: Int64) -> String? {
    if let reason = captureFailure(venue: range.venue, market: range.market, symbol: range.symbol, interval: range.interval) { return reason }
    guard let interval = ReviewInterval(rawValue: range.interval) else { return "这个周期暂不支持复盘，请切换周期" }
    guard range.start < range.end, range.end <= cutoff, range.bars >= minBars else { return "至少框选 \(minBars) 根已收盘 K 线" }
    guard range.bars <= maxBars else { return "一次最多框选 \(maxBars) 根 K 线" }
    guard interval.barsBetween(start: range.start, end: range.end) == Int64(range.bars) else { return "框选的区间和根数对不上，请重新框选" }
    return nil
  }

  /// 这一条能不能记（对应服务端 `validate`）。`now` 是**保存那一刻**，不是圈选那一刻。
  public static func failure(_ draft: ReviewDraft, now: Int64) -> String? {
    if let reason = rangeFailure(draft.range, cutoff: now) { return reason }
    let rule = draft.rule
    guard rule.version == ruleVersion else { return "复盘规则已更新，请升级后再记" }
    guard directions.contains(rule.direction.rawValue), confirmations.contains(rule.confirmation.rawValue),
          origins.contains(draft.origin.rawValue) else { return "复盘规则已更新，请升级后再记" }
    if let confidence = draft.confidence, !confidences.contains(confidence) { return "请选择有效把握" }
    guard draft.created >= 0, draft.created <= now + createdAheadMillis else { return "本机时间和实际时间差得太远，请先校准" }
    guard draft.text.utf8.count <= textMaxBytes else { return "这段话太长了，精简一下再记" }
    if let settings = draft.chartSettings, base64Length(settings) > chartSettingsMaxBytes { return "图表设置太大，暂时记不下" }
    if let drawings = draft.drawingSnapshot, base64Length(drawings) > drawingSnapshotMaxBytes { return "这一屏的画线太多了，精简后再记" }
    // observe 也要三口价都是正的有限数——服务端这一条对三个方向一视同仁，
    // 客户端原来在 observe 上提前 return，于是「只记录」能造出服务端必拒的记录。
    guard [rule.reference, rule.target, rule.invalidation].allSatisfy({ $0.isFinite && $0 > 0 }) else { return "请输入有效价格" }
    guard rule.direction != .observe else { return nil }
    guard rule.expires > draft.created else { return "到期时间需要晚于记录时间" }
    guard rule.expires <= draft.created + horizonMaxMillis else { return "到期最远只能设到一年后" }
    if rule.direction == .long && !(rule.target > rule.reference && rule.invalidation < rule.reference) {
      return "看多：目标需高于参考价，失效需低于参考价"
    }
    if rule.direction == .short && !(rule.target < rule.reference && rule.invalidation > rule.reference) {
      return "看空：目标需低于参考价，失效需高于参考价"
    }
    return nil
  }
}
