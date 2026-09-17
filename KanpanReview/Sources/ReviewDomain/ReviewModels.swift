import Foundation

public enum ReviewDirection: String, Codable, Sendable, CaseIterable {
  case long, short, observe
  public var title: String { switch self { case .long: "看多"; case .short: "看空"; case .observe: "只记录" } }
}
public enum ReviewOrigin: String, Codable, Sendable, CaseIterable {
  case chartFirst = "chart_first", thoughtFirst = "thought_first", interwoven, unknown
  public var title: String { switch self { case .chartFirst: "图在先"; case .thoughtFirst: "想法在先"; case .interwoven: "两者交织"; case .unknown: "不确定" } }
}
public enum ReviewConfirmation: String, Codable, Sendable, CaseIterable {
  case barClose = "bar_close", tradeTouch = "trade_touch"
  public var title: String { self == .barClose ? "收盘确认" : "触价确认" }
}
public struct ReviewBar: Codable, Sendable, Equatable {
  public var time: Int64
  public var end: Int64
  public var open: Double
  public var high: Double
  public var low: Double
  public var close: Double
  public var volume: Double
  public init(time: Int64, end: Int64, open: Double, high: Double, low: Double, close: Double, volume: Double) {
    self.time = time; self.end = end; self.open = open; self.high = high; self.low = low; self.close = close; self.volume = volume
  }
}
public struct ReviewRange: Codable, Sendable, Equatable {
  public var venue = "binance"
  public var market = "usd_m"
  public var symbol: String
  public var interval: String
  public var start: Int64
  public var end: Int64
  public var bars: Int
  public init(venue: String = "binance", symbol: String, interval: String, start: Int64, end: Int64, bars: Int) {
    self.venue = venue; self.symbol = symbol; self.interval = interval; self.start = start; self.end = end; self.bars = bars
  }

  /// 复盘本里露脸的短名：`BTCUSDT` → `BTC`（§2G5）。
  ///
  /// 列表一行里，计价币那四个字母每条都一样，占着位置却不带信息量；真正要一眼认出来的
  /// 是前半截。和顶栏把品种拆成「BTC / USDT」是同一套切法（见 `TopBar.base`）。
  /// 美股代码没有计价后缀，原样返回。
  public var shortSymbol: String {
    for quote in ["USDT", "USDC", "USD", "BUSD", "FDUSD"]
    where symbol.hasSuffix(quote) && symbol.count > quote.count {
      return String(symbol.dropLast(quote.count))
    }
    return symbol
  }
}
public struct ReviewRule: Codable, Sendable, Equatable {
  public var version = "criteria-v2"
  public var direction: ReviewDirection = .observe
  public var confirmation: ReviewConfirmation = .barClose
  public var reference: Double
  public var target: Double
  public var invalidation: Double
  public var expires: Int64
  public var targetEdited = false
  public var invalidationEdited = false
  public var expiryEdited = false
  public init(reference: Double, target: Double, invalidation: Double, expires: Int64) {
    self.reference = reference; self.target = target; self.invalidation = invalidation; self.expires = expires
  }
  public func validation(at now: Int64) -> String? {
    guard reference.isFinite, reference > 0 else { return "等待有效行情" }
    if direction == .observe { return nil }
    guard target.isFinite, invalidation.isFinite, target > 0, invalidation > 0 else { return "请输入有效价格" }
    guard expires > now else { return "到期时间需要晚于现在" }
    if direction == .long && !(target > reference && invalidation < reference) { return "看多：目标需高于参考价，失效需低于参考价" }
    if direction == .short && !(target < reference && invalidation > reference) { return "看空：目标需低于参考价，失效需高于参考价" }
    return nil
  }
}
public struct ReviewDraft: Codable, Sendable, Equatable, Identifiable {
  public var id = UUID()
  public var range: ReviewRange
  public var rule: ReviewRule
  public var text = ""
  public var confidence: Int?
  public var origin: ReviewOrigin = .chartFirst
  public var created: Int64
  public var chartSettings: Data?
  public var drawingSnapshot: Data?
  public var originalClaimed: Int64?
  public init(range: ReviewRange, reference: Double, high: Double, low: Double, now: Int64) {
    self.range = range; self.created = now
    self.rule = ReviewRule(reference: reference, target: high, invalidation: low, expires: now + 86_400_000)
  }
  public func validation(at now: Int64) -> String? {
    guard range.bars >= 3, range.start < range.end, range.end <= now else { return "至少框选 3 根已收盘 K 线" }
    if let confidence, ![50, 60, 70, 80, 90].contains(confidence) { return "请选择有效把握" }
    return rule.validation(at: now)
  }
}
public enum ReviewOutcome: String, Codable, Sendable {
  case waiting, realized, unrealized, needsVerification = "needs_verification", observation, voided
  public var title: String { switch self { case .waiting: "等答案"; case .realized: "判对"; case .unrealized: "判错"; case .needsVerification: "待核实"; case .observation: "只记录"; case .voided: "已作废" } }
}
public struct ReviewAssessment: Codable, Sendable, Equatable {
  public var outcome: ReviewOutcome
  public var reason: String
  public var eventAt: Int64?
  public var assessedAt: Int64
  public init(outcome: ReviewOutcome, reason: String, eventAt: Int64? = nil, assessedAt: Int64) {
    self.outcome = outcome; self.reason = reason; self.eventAt = eventAt; self.assessedAt = assessedAt
  }
}
public struct ReviewReflection: Codable, Sendable, Equatable {
  public var note = ""
  public var nextTime = ""
  public var publishedAt: Int64?
  public var revision = 0
  public init() {}
}
public struct ReviewRecord: Codable, Sendable, Equatable, Identifiable {
  public var id: UUID { draft.id }
  public var draft: ReviewDraft
  public var serverId: UUID?
  public var submitted: Int64?
  public var revision = 0
  public var assessment: ReviewAssessment?
  public var reflection = ReviewReflection()
  public var reflectionHistory: [ReviewReflection] = []
  public var syncError: String?
  public var groupPending: Bool?
  public var eligible = false
  public var voided = false
  public init(draft: ReviewDraft) { self.draft = draft }
  public var outcome: ReviewOutcome { voided ? .voided : assessment?.outcome ?? (draft.rule.direction == .observe ? .observation : .waiting) }
  public var needsAction: Bool { !voided && (groupPending == true || syncError != nil || outcome == .needsVerification || ([.realized, .unrealized].contains(outcome) && reflection.publishedAt == nil)) }

  /// 这一条该不该画在**当前这张图**上（§2F3）。
  ///
  /// 三个条件缺一不可：没作废、品种一样、周期一样。品种那条本来就有；周期是这次补的——
  /// 记录里的起止时间是绝对时刻，1 小时图上框的那 48 根，换到 1 分钟图上是同样两个时刻
  /// 之间的 2880 根，框还在原地画，位置对得上、意思全错了。一个品种在十几个周期上各记
  /// 一笔，切周期时满屏都是别的周期留下的框。
  public func paints(symbol: String, interval: String) -> Bool {
    !voided && draft.range.symbol == symbol && draft.range.interval == interval
  }
}
public struct ReviewReplayPosition: Codable, Sendable {
  public var cursor: Int64
  public var speed: Int
  public init(cursor: Int64, speed: Int = 1) { self.cursor = cursor; self.speed = speed }
}
public struct ReviewMatch: Codable, Sendable, Identifiable {
  public var id: String
  public var range: ReviewRange
  public var score: Double
  public var source: String
  public init(id: String, range: ReviewRange, score: Double, source: String) { self.id = id; self.range = range; self.score = score; self.source = source }
}
public struct ReviewStatsGroup: Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var total: Int
  public var correct: Int
  public var rate: Double? { total > 0 ? Double(correct) / Double(total) : nil }
  public init(id: String, title: String, total: Int, correct: Int) { self.id = id; self.title = title; self.total = total; self.correct = correct }
}
public enum ReviewClock {
  public static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
