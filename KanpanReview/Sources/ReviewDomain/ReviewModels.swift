import KanpanCore
import Foundation

// 下面这几个枚举都自己写了 `init(from:)`。原因是同一句话：**解不动一个字段，
// 不该让整条记录连同它的正文一起消失。** 服务端将来多一档方向、多一种判定口径，
// 合成出来的 `Decodable` 会直接抛，整页列表都读不出来；而这几处真正要守的是
// 「未知的东西不能被当成已经有结论」——所以未知方向落到「只记录」，未知结果落到
// 「待核实」，绝不会静默变成「判对」（审查 B.2）。
public enum ReviewDirection: String, Codable, Sendable, CaseIterable {
  case long, short, observe
  public var title: String { switch self { case .long: "看多"; case .short: "看空"; case .observe: "只记录" } }
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .observe
  }
}
public enum ReviewOrigin: String, Codable, Sendable, CaseIterable {
  case chartFirst = "chart_first", thoughtFirst = "thought_first", interwoven, unknown
  public var title: String { switch self { case .chartFirst: "图在先"; case .thoughtFirst: "想法在先"; case .interwoven: "两者交织"; case .unknown: "不确定" } }
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
  }
}
public enum ReviewConfirmation: String, Codable, Sendable, CaseIterable {
  case barClose = "bar_close", tradeTouch = "trade_touch"
  public var title: String { self == .barClose ? "收盘确认" : "触价确认" }
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .barClose
  }
}
public struct ReviewRange: Codable, Sendable, Equatable {
  public var venue = InstrumentID.defaultVenue
  public var market = InstrumentID.defaultMarket
  public var symbol: String
  public var interval: String
  public var start: Int64
  public var end: Int64
  public var bars: Int
  public init(venue: String = InstrumentID.defaultVenue, symbol: String, interval: String, start: Int64, end: Int64, bars: Int) {
    let id = symbol.contains("/") ? InstrumentID(symbol) : InstrumentID(venue: venue, market: venue == InstrumentID.defaultVenue ? InstrumentID.defaultMarket : "spot", symbol: symbol)
    self.venue = id.venue; self.market = id.market; self.symbol = symbol.contains("/") ? id.symbol : symbol; self.interval = interval; self.start = start; self.end = end; self.bars = bars
  }
  /// 属性写了初值**不等于**这个键可以缺：合成出来的 `Decodable` 照样要求它在。
  /// 老存档、老响应里没有 `venue` / `market` 的那几条，现在按默认值读回来。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    venue = try c.decodeIfPresent(String.self, forKey: .venue) ?? InstrumentID.defaultVenue
    market = try c.decodeIfPresent(String.self, forKey: .market) ?? InstrumentID.defaultMarket
    symbol = try c.decode(String.self, forKey: .symbol)
    // 存档里的 `symbol` 若已是完整品种 key，以它为准拆开；否则 `key` 会拼出两层前缀。
    if symbol.contains("/") {
      let id = InstrumentID(symbol)
      venue = id.venue; market = id.market; symbol = id.symbol
    }
    interval = try c.decode(String.self, forKey: .interval)
    start = try c.decode(Int64.self, forKey: .start)
    end = try c.decode(Int64.self, forKey: .end)
    bars = try c.decode(Int.self, forKey: .bars)
  }

  /// 复盘本里露脸的短名：`BTCUSDT` → `BTC`（§2G5）。
  ///
  /// 列表一行里，计价币那四个字母每条都一样，占着位置却不带信息量；真正要一眼认出来的
  /// 是前半截。和顶栏把品种拆成「BTC / USDT」是同一套切法（见 `TopBar.base`）。
  /// 美股代码没有计价后缀，原样返回。
  ///
  /// 后缀**按长度从长到短**试。原来 `USD` 排在 `BUSD` / `FDUSD` 前面，`BTCBUSD` 会被
  /// 切成 `BTCB`——那是另一个真实存在的币（审查 B.4）。
  public var key: String { InstrumentID(venue: venue, market: market, symbol: symbol).key }

  public var shortSymbol: String {
    SymbolInfo.placeholder(symbol: key).base
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
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(String.self, forKey: .version) ?? "criteria-v2"
    direction = try c.decodeIfPresent(ReviewDirection.self, forKey: .direction) ?? .observe
    confirmation = try c.decodeIfPresent(ReviewConfirmation.self, forKey: .confirmation) ?? .barClose
    reference = try c.decode(Double.self, forKey: .reference)
    target = try c.decode(Double.self, forKey: .target)
    invalidation = try c.decode(Double.self, forKey: .invalidation)
    expires = try c.decode(Int64.self, forKey: .expires)
    targetEdited = try c.decodeIfPresent(Bool.self, forKey: .targetEdited) ?? false
    invalidationEdited = try c.decodeIfPresent(Bool.self, forKey: .invalidationEdited) ?? false
    expiryEdited = try c.decodeIfPresent(Bool.self, forKey: .expiryEdited) ?? false
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
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    range = try c.decode(ReviewRange.self, forKey: .range)
    rule = try c.decode(ReviewRule.self, forKey: .rule)
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    confidence = try c.decodeIfPresent(Int.self, forKey: .confidence)
    origin = try c.decodeIfPresent(ReviewOrigin.self, forKey: .origin) ?? .unknown
    created = try c.decode(Int64.self, forKey: .created)
    chartSettings = try c.decodeIfPresent(Data.self, forKey: .chartSettings)
    drawingSnapshot = try c.decodeIfPresent(Data.self, forKey: .drawingSnapshot)
    originalClaimed = try c.decodeIfPresent(Int64.self, forKey: .originalClaimed)
  }
  /// 这条没提交的草稿，能不能在当前这张图上接着写。
  ///
  /// 三样全同才算同一个上下文：交易所、品种、周期。少比一样就会串——先在 BTC 上
  /// 圈了一段写了两句，切到 ETH 再点「记录」，接着写的还是 BTC 那条（审查 B.4 复核项）。
  public func reusable(venue: String, symbol: String, interval: String) -> Bool {
    range.venue == venue && range.key == (symbol.contains("/") ? InstrumentID(symbol) : InstrumentID(venue: venue, market: range.market, symbol: symbol)).key && range.interval == interval
  }

  /// 这一条能不能记。规则整份搬去了 `ReviewContract`——它是服务端
  /// `native_review.rs` 的镜像，本地过不了的东西，上去也一定被拒（审查 B-06）。
  public func validation(at now: Int64) -> String? { ReviewContract.failure(self, now: now) }
}
public enum ReviewOutcome: String, Codable, Sendable {
  case waiting, realized, unrealized, needsVerification = "needs_verification", observation, voided
  public var title: String { switch self { case .waiting: "等答案"; case .realized: "判对"; case .unrealized: "判错"; case .needsVerification: "待核实"; case .observation: "只记录"; case .voided: "已作废" } }
  /// 不认识的结果一律当「待核实」。**绝不能落到 `realized`**——那等于凭一个没见过的
  /// 字符串替服务器宣布判对（审查 B.2）。
  public init(from decoder: any Decoder) throws {
    self = Self(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .needsVerification
  }
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
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    nextTime = try c.decodeIfPresent(String.self, forKey: .nextTime) ?? ""
    publishedAt = try c.decodeIfPresent(Int64.self, forKey: .publishedAt)
    revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
  }
}

/// 一条**确定不可能靠重试成功**的上传，被单独拎出来放在这儿（审查 B-02）。
///
/// 队列是先进先出的，而且每条操作带着固定的幂等键与固定的 body——这是 HTTP 幂等
/// 重试的前提，不能为了绕过失败去改同一个键下的内容。所以遇到 409（别的设备先改了）
/// 或者 4xx 业务拒绝时，把这条操作从队列里摘下来存到这儿：
///
/// * 人写的那份内容**一个字都不丢**（`body` 原样留着）；
/// * 队列继续往下跑，后面那些无关的记录该传的照传；
/// * 交给人裁决：要么「用我这份」——按服务器最新版本重新基准、**换一个新幂等键**
///   发一条新操作；要么「保留云端那份」——把这条丢掉。
public struct ReviewConflict: Codable, Sendable, Equatable {
  /// 出事的是哪种操作：`create` / `reflection` / `void` / `group`。
  public var kind: String
  /// 服务端给的机器可读错误码（只收白名单形状的，不展示服务端原文）。
  public var code: String
  /// 给人看的一句话。
  public var reason: String
  /// 什么时候卡住的。
  public var at: Int64
  /// 本地那份内容（原操作的 body），等人裁决时重发用。
  public var body: Data
  /// 还值不值得再试一次：409 值得（重基准就行），400/422 这种参数被拒的不值得。
  public var retryable: Bool
  public init(kind: String, code: String, reason: String, at: Int64, body: Data, retryable: Bool) {
    self.kind = kind; self.code = code; self.reason = reason; self.at = at; self.body = body; self.retryable = retryable
  }
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
  /// 被隔离下来的那条上传（见 `ReviewConflict`）。
  public var conflict: ReviewConflict?
  public var groupPending: Bool?
  /// 服务端这条记录的**裁定版本**，和用户自己的 `revision` 是两回事：worker 每改一次
  /// 结论它才加一。详情响应的外层带着它（`assessmentRevision`），
  /// 以及「这份复盘是针对哪一版结论写的」（`reflectionAssessmentRevision`）。
  /// 两个对不上就说明结果在人写完复盘之后又变过，得让人再看一眼（审查 B.2）。
  public var assessmentRevision: Int?
  public var reflectionAssessmentRevision: Int?
  public var eligible = false
  public var voided = false
  public init(draft: ReviewDraft) { self.draft = draft }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    draft = try c.decode(ReviewDraft.self, forKey: .draft)
    serverId = try c.decodeIfPresent(UUID.self, forKey: .serverId)
    submitted = try c.decodeIfPresent(Int64.self, forKey: .submitted)
    revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 0
    assessment = try c.decodeIfPresent(ReviewAssessment.self, forKey: .assessment)
    reflection = try c.decodeIfPresent(ReviewReflection.self, forKey: .reflection) ?? ReviewReflection()
    reflectionHistory = try c.decodeIfPresent([ReviewReflection].self, forKey: .reflectionHistory) ?? []
    syncError = try c.decodeIfPresent(String.self, forKey: .syncError)
    conflict = try c.decodeIfPresent(ReviewConflict.self, forKey: .conflict)
    groupPending = try c.decodeIfPresent(Bool.self, forKey: .groupPending)
    assessmentRevision = try c.decodeIfPresent(Int.self, forKey: .assessmentRevision)
    reflectionAssessmentRevision = try c.decodeIfPresent(Int.self, forKey: .reflectionAssessmentRevision)
    eligible = try c.decodeIfPresent(Bool.self, forKey: .eligible) ?? false
    voided = try c.decodeIfPresent(Bool.self, forKey: .voided) ?? false
  }
  public var outcome: ReviewOutcome { voided ? .voided : assessment?.outcome ?? (draft.rule.direction == .observe ? .observation : .waiting) }
  /// 人写完复盘之后，服务器又改过结论。
  public var assessmentMoved: Bool {
    guard let current = assessmentRevision, let written = reflectionAssessmentRevision else { return false }
    return current != written
  }
  public var needsAction: Bool {
    !voided && (groupPending == true || syncError != nil || conflict != nil || assessmentMoved
      || outcome == .needsVerification
      || ([.realized, .unrealized].contains(outcome) && reflection.publishedAt == nil))
  }
  /// 复盘本「已判定」那一档：复盘写完了，也没有别的事等人处理。
  /// 和服务端 `?decided=true` 同一个口径（`review.rs` 的列表查询）。
  public var isDecided: Bool {
    !voided && reflection.publishedAt != nil && groupPending != true && !needsAction
      && outcome != .waiting && outcome != .needsVerification
  }

  /// 这一条该不该画在**当前这张图**上（§2F3）。
  ///
  /// 四个条件缺一不可：没作废、交易所一样、品种一样、周期一样。品种那条本来就有；
  /// 周期是后来补的——记录里的起止时间是绝对时刻，1 小时图上框的那 48 根，换到
  /// 1 分钟图上是同样两个时刻之间的 2880 根，框还在原地画，位置对得上、意思全错了。
  /// 交易所是这次补的：同名品种在两家交易所是两段不同的行情，`ReviewRange.venue`
  /// 本来就跟着捕获时的行情源走，落图时却没人看它（审查 B.4）。
  public func paints(venue: String, symbol: String, interval: String) -> Bool {
    !voided && draft.range.venue == venue && draft.range.key == (symbol.contains("/") ? InstrumentID(symbol) : InstrumentID(venue: venue, market: draft.range.market, symbol: symbol)).key && draft.range.interval == interval
  }
}
public struct ReviewReplayPosition: Codable, Sendable, Equatable {
  public var cursor: Int64
  public var speed: Int
  /// 最后一次真的看到这条进度是什么时候（毫秒）。
  ///
  /// 超过 500 条要淘汰时按它挑「最久没看的那条」。老存档里没有这个键，所以是
  /// 可选的——`Decodable` 不会因为属性写了初值就容忍缺键（审查 B-08）。
  public var usedAt: Int64?
  public init(cursor: Int64, speed: Int = 1, usedAt: Int64? = nil) {
    self.cursor = cursor; self.speed = speed; self.usedAt = usedAt
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    cursor = try c.decode(Int64.self, forKey: .cursor)
    speed = try c.decodeIfPresent(Int.self, forKey: .speed) ?? 1
    usedAt = try c.decodeIfPresent(Int64.self, forKey: .usedAt)
  }
}
public struct ReviewMatch: Codable, Sendable, Identifiable {
  public var id: String
  public var range: ReviewRange
  public var score: Double
  public var source: String
  public init(id: String, range: ReviewRange, score: Double, source: String) { self.id = id; self.range = range; self.score = score; self.source = source }
  /// 界面上那行「像 0.87」。
  ///
  /// 原来写的是 `87%`。这个数是两段行情的路径差经 `exp(-6·cost)` 映射出来的相似分，
  /// 和概率、胜率没有任何关系，可它和同一张页面上的胜率长得一模一样（审查 B.4）。
  /// 去掉百分号，改成 0…1 的固定分数，顺手夹住范围——服务端给的本来就在这个区间里。
  public var scoreText: String { String(format: "%.2f", min(1, max(0, score))) }
}
public struct ReviewStatsGroup: Codable, Sendable, Identifiable {
  public var id: String
  public var title: String
  public var total: Int
  public var correct: Int
  /// 这一组够不够格给结论：`insufficient`（样本不足）/ `verdict_due` / `observing`。
  /// 来自战绩响应里的 `proof.compatible_groups[id].verdict_status`，服务端一直在算，
  /// 只是客户端以前只接 `groups`，把它丢了（审查 B-07 / B.2）。
  public var verdict: String?
  /// 最近十笔明显比整体差，服务端要人回头看一眼。
  public var recheck: Bool?
  public var rate: Double? { total > 0 ? Double(correct) / Double(total) : nil }
  /// 样本够了才给百分比。不够就写「样本不足」——一笔一组的 0% / 100% 不是统计结论，
  /// 把它摆成百分比等于拿噪声冒充战绩。
  public var rateText: String {
    guard verdict != "insufficient" else { return "样本不足" }
    guard let rate else { return "—" }
    return String(format: "%.0f%%", rate * 100)
  }
  public init(id: String, title: String, total: Int, correct: Int, verdict: String? = nil, recheck: Bool? = nil) {
    self.id = id; self.title = title; self.total = total; self.correct = correct
    self.verdict = verdict; self.recheck = recheck
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    title = try c.decode(String.self, forKey: .title)
    total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
    correct = try c.decodeIfPresent(Int.self, forKey: .correct) ?? 0
    verdict = try c.decodeIfPresent(String.self, forKey: .verdict)
    recheck = try c.decodeIfPresent(Bool.self, forKey: .recheck)
    // 相对口径那份分组（`comparableGroups`）把同一件事写成 `verdictStatus`，
    // 老的 `groups` 写 `verdict`（其实只在 `proof` 里）。两个名字都认，省得同一个
    // 结论因为键名不同被读成「没结论」，于是又回到拿 0% 冒充战绩。
    if verdict == nil, let alternate = try? decoder.container(keyedBy: AlternateKeys.self) {
      verdict = try alternate.decodeIfPresent(String.self, forKey: .verdictStatus)
    }
  }
  private enum AlternateKeys: String, CodingKey { case verdictStatus }
}
public enum ReviewClock {
  public static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
