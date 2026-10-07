import Foundation
import Observation
import SwiftUI
import KanpanCore
import ReviewDomain
import ReviewData

/// 复盘本里的一笔交易：本机拼的回合，配上服务端那份（结果、备注），没上传就只有回合。
public struct TradeItem: Identifiable, Hashable, Sendable {
  public var round: TradeRound
  public var record: TradeRecord?
  public var id: String { round.id }
}

/// 复盘本「交易」这一半（自动复盘 3c）。
///
/// 回合从哪儿来不归这里管：宿主（app 的 `ExchangeReviewBridge`）按节奏去交易所拉成交、
/// 拼好回合，再 `setLocalRounds` 灌进来。这里只管三件事：
/// 1. 把服务端还没有的那几版传上去（没登录就只在本机摆着，登录那一刻再传）；
/// 2. 把服务端那份（带结果与备注）拉回来和本机的合成一张列表；
/// 3. 周报、战绩这些数从合好的列表上现算（客户端算，服务端不存聚合）。
@MainActor @Observable public final class TradeReviewFeature {
  public enum Segment: String, Sendable { case views, trades }
  /// 复盘本顶上「观点 · 交易」那一刀。战绩页也跟着它。
  public var segment: Segment = .views

  /// 交易所账户接没接、上次什么时候拉的。宿主写，界面读。
  public struct Exchange: Equatable, Sendable {
    public var connected = false
    /// 「币安合约」。
    public var title = ""
    public var lastSync: Int64?
    public init(connected: Bool = false, title: String = "", lastSync: Int64? = nil) {
      self.connected = connected; self.title = title; self.lastSync = lastSync
    }
  }
  public var exchange = Exchange()
  /// 「接入交易所账户后自动生成」那一行点下去：宿主去开接入页。
  public var onConnect: () -> Void = {}
  /// 复盘本打开、切到交易段时：宿主去交易所拉一次（它自己节流）。
  public var onPull: () -> Void = {}
  /// 这一笔的复盘图（离屏画的 PNG）：宿主拿 K 线和成交画，这个包看不见图表。
  /// 参数：回合、服务端给的周期与窗口（没有就宿主自己按持仓时长算）、出图的点尺寸。
  @ObservationIgnored public var chartImage: (@MainActor (TradeRound, TradeChartSpec?, CGSize) async -> Data?)?
  /// 品种徽章（app 里那套），没接线就不画。
  @ObservationIgnored public var badge: ((String) -> AnyView)?
  /// 一句提示交给宿主那条全局提示。
  @ObservationIgnored var onNotice: (String) -> Void = { _ in }

  public private(set) var local: [TradeRound] = []
  public private(set) var records: [TradeRecord] = []
  /// 合好的列表：持仓中的在前（新开的在上），其余按平仓时间倒序。
  public private(set) var items: [TradeItem] = []
  public private(set) var syncing = false

  private var store: TradeReviewStore?
  private var client: ScorebookClient?
  private var epoch = UUID()
  private var again = false
  /// 本页里画好的图（缩略图、详情大图），按「回合 id + 版本 + 尺寸」记。
  @ObservationIgnored private var images: [String: Data] = [:]
  @ObservationIgnored private var imageOrder: [String] = []
  /// 正在画（或正在从盘上读）的那几张：同一张不许列表格子和预热各画一遍。
  @ObservationIgnored private var imagesInFlight: Set<String> = []
  public private(set) var imageVersion = 0
  /// 本页内存里最多记几张（缩略图一张几 KB）。
  static let imageMemoryLimit = 120
  /// 复盘本打开时先画好前面这么多张，往下滚不用一格一格等。
  static let prewarmCount = 24
  /// 缩略图盘上那份放在哪（宿主给 `Library/Caches/kanpan/trade-images`）。不给就只记在本页。
  @ObservationIgnored public var imageCacheRoot: URL? { didSet { reopenImageStore() } }
  /// 图的画法（深浅、涨跌色、时区…）摘成一句，进盘上那张的名字：换了皮肤不拿旧图冒充。
  @ObservationIgnored public var imageStyle: @MainActor () -> String = { "" }
  @ObservationIgnored private var imageStore: TradeImageStore?
  @ObservationIgnored private var profileDirectory: URL?

  public init() {}

  public var isConnected: Bool { client != nil }

  /// 换进一份账号档案（冷启动、登录、退登）。登录了就把本机攒的回合补传上去。
  func activate(directory: URL?, client: ScorebookClient?) {
    epoch = UUID(); again = false; syncing = false
    store = directory.map { TradeReviewStore(directory: $0) }
    profileDirectory = directory
    reopenImageStore()
    self.client = client
    records = client == nil ? [] : (store?.archive.records ?? [])
    remerge()
    // 登录那一刻只补传本机攒着的；服务端那份（别的设备的、回写的结果）等交易那一面露脸再拉，
    // 不跟观点那条同步抢在同一拍（冷启动就多一趟请求）。
    if let store, client != nil,
       !TradeUploadPlan.pending(local, uploaded: store.archive.uploaded, rejected: store.archive.rejected).isEmpty { sync() }
  }

  /// 宿主灌进来的本机回合（整份）。有服务端没有的版本就去传。
  public func setLocalRounds(_ rounds: [TradeRound]) {
    guard rounds != local else { return }
    local = rounds
    remerge()
    guard let store, client != nil else { return }
    if !TradeUploadPlan.pending(rounds, uploaded: store.archive.uploaded, rejected: store.archive.rejected).isEmpty { sync() }
  }

  public func sync() { Task { await synchronize() } }

  /// 传、再拉。没登录什么都不做；断网静默停下，不自己重试（下一次前台 / 定时拉会再来）。
  public func synchronize() async {
    guard let store, let client else { return }
    if syncing { again = true; return }
    syncing = true
    let current = epoch
    _ = await TradeSync.upload(local, store: store, client: client)
    guard current == epoch else { return }
    _ = try? await TradeSync.refresh(store: store, client: client)
    guard current == epoch else { return }
    records = store.archive.records
    remerge()
    syncing = false
    if again { again = false; await synchronize() }
  }

  /// 详情页打开时拉这一条的最新样子（结果随时可能回写）。
  public func refreshDetail(_ id: String) async {
    guard let store, let client, records.contains(where: { $0.id == id }) else { return }
    let current = epoch
    guard let record = try? await TradeSync.detail(id, store: store, client: client), current == epoch else { return }
    replace(record)
  }

  /// 写「当时怎么想」。别的设备先改过（409）就重拉那一条、告诉人一声，返回 false。
  @discardableResult public func saveNote(_ id: String, text: String) async -> Bool {
    guard let store, let client, let record = records.first(where: { $0.id == id }) else {
      onNotice("登录后才能写"); return false
    }
    let current = epoch
    do {
      let saved = try await TradeSync.saveNote(text, for: record, store: store, client: client)
      guard current == epoch else { return false }
      replace(saved)
      return true
    } catch {
      guard current == epoch else { return false }
      switch ReviewFailure.verdict(for: error) {
      case .conflict:
        await refreshDetail(id)
        onNotice("这条在别的设备上改过了，已换成最新的")
      case .rejected:
        onNotice(ReviewFailure.message(ReviewFailure.code(for: error), status: (error as? any ReviewFailureStatus)?.reviewStatusCode))
      case .transient:
        onNotice("没有保存上，稍后再试")
      }
      return false
    }
  }

  public func item(_ id: String) -> TradeItem? { items.first { $0.id == id } }

  private func replace(_ record: TradeRecord) {
    if let at = records.firstIndex(where: { $0.id == record.id }) { records[at] = record } else { records.append(record) }
    remerge()
  }

  private func remerge() {
    var byID: [String: TradeItem] = [:]
    for record in records where !record.voided { byID[record.id] = TradeItem(round: record.round, record: record) }
    for round in local {
      if var item = byID[round.id] {
        if round.updatedAt >= item.round.updatedAt { item.round = round }
        byID[round.id] = item
      } else {
        byID[round.id] = TradeItem(round: round, record: nil)
      }
    }
    let next = byID.values.sorted { a, b in
      if a.round.isOpen != b.round.isOpen { return a.round.isOpen }
      if a.round.isOpen { return (a.round.openedAt, a.id) > (b.round.openedAt, b.id) }
      return (a.round.closedAt ?? 0, a.id) > (b.round.closedAt ?? 0, b.id)
    }
    if next != items { items = next }
  }

  // MARK: 现算的数

  public var rounds: [TradeRound] { items.map(\.round) }

  public func weekly(now: Int64, calendar: Calendar) -> WeeklyReport {
    WeeklyReport.lastWeek(rounds, now: now, calendar: calendar)
  }

  // MARK: 图

  public func image(_ round: TradeRound, size: CGSize) -> Data? {
    images[Self.imageKey(round, size)]
  }

  /// 画一张（本页记住，最多一百来张）；已经有就直接回。画完就不会再变的缩略图先翻盘上那份，
  /// 没有再请宿主画，画好顺手存盘（`TradeImagePolicy`）。
  public func loadImage(_ round: TradeRound, spec: TradeChartSpec?, size: CGSize) async {
    let key = Self.imageKey(round, size)
    guard images[key] == nil, !imagesInFlight.contains(key) else { return }
    imagesInFlight.insert(key)
    defer { imagesInFlight.remove(key) }
    let disk = TradeImagePolicy.persists(round, spec: spec, size: size, now: ReviewClock.now)
      ? imageStore.map { ($0, TradeImagePolicy.diskKey(round, spec: spec, size: size, style: imageStyle())) } : nil
    if let disk, let data = await disk.0.read(disk.1) {
      remember(key, data); imageVersion &+= 1
      return
    }
    guard let chartImage, let data = await chartImage(round, spec, size) else { return }
    remember(key, data); imageVersion &+= 1
    if let disk { await disk.0.write(disk.1, data: data) }
  }

  /// 复盘本打开时：先把手上这些单子已经存在盘上的缩略图一次翻出来（界面只刷一次），
  /// 再把前面那几张还没有的依次画好——往下滚时格子里已经是图，不再一格一格冒出来。
  public func prewarmThumbnails(size: CGSize) async {
    let now = ReviewClock.now
    if let store = imageStore {
      let style = imageStyle()
      var names: [String: String] = [:]
      for item in items {
        let spec = item.record?.result?.chart
        let key = Self.imageKey(item.round, size)
        guard images[key] == nil, TradeImagePolicy.persists(item.round, spec: spec, size: size, now: now) else { continue }
        names[TradeImagePolicy.diskKey(item.round, spec: spec, size: size, style: style)] = key
      }
      if !names.isEmpty {
        let found = await store.read(Array(names.keys))
        for (name, data) in found { if let key = names[name], images[key] == nil { remember(key, data) } }
        if !found.isEmpty { imageVersion &+= 1 }
      }
    }
    for item in items.prefix(Self.prewarmCount) {
      if Task.isCancelled { return }
      await loadImage(item.round, spec: item.record?.result?.chart, size: size)
    }
  }

  private func remember(_ key: String, _ data: Data) {
    if images[key] == nil { imageOrder.append(key) }
    images[key] = data
    while imageOrder.count > Self.imageMemoryLimit { images[imageOrder.removeFirst()] = nil }
  }

  private func reopenImageStore() {
    guard let root = imageCacheRoot, let profileDirectory else { imageStore = nil; return }
    if let current = imageStore, current.root == root,
       current.directory == TradeImageStore(root: root, profile: profileDirectory.path).directory { return }
    imageStore = TradeImageStore(root: root, profile: profileDirectory.path)
  }

  private static func imageKey(_ round: TradeRound, _ size: CGSize) -> String {
    "\(round.id)@\(round.updatedAt)@\(Int(size.width))x\(Int(size.height))"
  }
}

// MARK: - 观点 ↔ 交易

extension ReviewFeature {
  /// 这一笔对应的观点：同品种、时间段有交叠。
  public func views(for round: TradeRound) -> [ReviewRecord] {
    TradeViewMatch.views(for: round, in: records, now: ReviewClock.now)
  }
  /// 这条观点对应的交易。
  public func trades(for record: ReviewRecord) -> [TradeItem] {
    let hits = Set(TradeViewMatch.rounds(for: record, in: trades.rounds, now: ReviewClock.now).map(\.id))
    return trades.items.filter { hits.contains($0.id) }
  }
  /// 按图表那一档时区的日历（日分组、周报、时段 / 周几分组都认它，和列表上写的时刻一致）。
  public var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.firstWeekday = 2
    switch tzOffset.basis {
    case .fixed(let minutes): value.timeZone = TimeZone(secondsFromGMT: minutes * 60) ?? .current
    case .zone(let zone): value.timeZone = zone
    }
    return value
  }
}

// MARK: - 文案

/// 交易复盘里的数怎么写。金额一律 K / M / B / T，不带币种（全是 U 本位）。
public enum TradeLabels {
  /// 正负号看**摆出来的那个数**：取整后是 0（-0.004 U 写成「0.00」）就不带号。
  /// 原来看的是取整前的原值，于是出现「-0.00」「+0.0%」这种自相矛盾的写法（审查 E 线自查）。
  public static func money(_ value: Decimal, signed: Bool = true) -> String {
    let number = NSDecimalNumber(decimal: value).doubleValue
    let body = fmtVol(abs(number))
    let sign = shownSign(number, body)
    guard signed else { return sign < 0 ? "-" + body : body }
    if sign > 0 { return "+" + body }
    if sign < 0 { return "-" + body }
    return body
  }
  /// 比值 → 百分比，一位小数。
  public static func percent(_ ratio: Decimal?, signed: Bool = false) -> String {
    guard let ratio else { return "—" }
    let value = NSDecimalNumber(decimal: ratio).doubleValue * 100
    let text = toFixed(abs(value), 1) + "%"
    let sign = shownSign(value, text)
    if !signed { return sign < 0 ? "-" + text : text }
    return (sign > 0 ? "+" : sign < 0 ? "-" : "") + text
  }
  /// 一笔金额该上涨色（1）、跌色（-1）还是中性（0）：和 `money` 摆出来的正负号同一个说法。
  public static func moneyTone(_ value: Decimal) -> Int {
    let number = NSDecimalNumber(decimal: value).doubleValue
    return shownSign(number, fmtVol(abs(number)))
  }
  /// 一个比值（`percent` 摆成一位小数的百分比）该上哪种色，和 `percent` 的正负号同一个说法。
  /// 不能拿 `moneyTone` 代：0.004 按金额写是「0.00」（中性），按百分比写却是「+0.4%」。
  public static func percentTone(_ ratio: Decimal) -> Int {
    let value = NSDecimalNumber(decimal: ratio).doubleValue * 100
    return shownSign(value, toFixed(abs(value), 1))
  }
  /// `text` 里一个非零数字都没有就是 0，否则跟原值的正负。
  private static func shownSign(_ value: Double, _ text: String) -> Int {
    guard text.contains(where: { ("1"..."9").contains($0) }) else { return 0 }
    return value > 0 ? 1 : value < 0 ? -1 : 0
  }
  public static func ratio(_ value: Decimal?) -> String {
    guard let value else { return "—" }
    return toFixed(NSDecimalNumber(decimal: value).doubleValue, 2)
  }
  /// 持仓时长：`45 分` `3 小时 12 分` `2 天 5 小时`。
  public static func holding(_ ms: Int64?) -> String {
    guard let ms else { return "—" }
    let minutes = max(0, ms / 60_000)
    if minutes < 1 { return "不到 1 分" }
    if minutes < 60 { return "\(minutes) 分" }
    let hours = minutes / 60
    if hours < 24 { return minutes % 60 == 0 ? "\(hours) 小时" : "\(hours) 小时 \(minutes % 60) 分" }
    return hours % 24 == 0 ? "\(hours / 24) 天" : "\(hours / 24) 天 \(hours % 24) 小时"
  }
  /// 一笔的短名：USDT 计价的只写币（`BTC`），别的计价带上计价币（`BTC/USDC`、Coinbase 的 `BTC/USD`）。
  /// 以前一律只取币名，BTCUSDT 与 BTCUSDC 在列表、周报卡、战绩「按品种」里写成同一个「BTC」，
  /// 战绩那一组还拿它当行 id，两行撞 id（审查 R8）。认整串代号或 `venue/market/symbol` 键都行。
  public static func shortSymbol(_ symbol: String) -> String {
    let (base, quote) = QuoteAssets.split(symbol)
    guard let quote, quote != "USDT" else { return base }
    return base + "/" + quote
  }
  public static func direction(_ value: TradeDirection) -> String { value == .long ? "多" : "空" }
  public static func role(_ value: FillRole) -> String {
    switch value { case .open: "开仓"; case .add: "加仓"; case .reduce: "减仓"; case .close: "平仓" }
  }
  public static func qty(_ value: Decimal) -> String { TradeDecimal.format(value) }
  public static func price(_ value: Decimal) -> String {
    let number = NSDecimalNumber(decimal: value).doubleValue
    return ReviewLabels.price(number, decimals: nil)
  }
  /// 「x 分钟前」这类：接入页与「我的」那一行用。
  public static func ago(_ ms: Int64?, now: Int64) -> String {
    guard let ms else { return "还没同步" }
    let minutes = max(0, (now - ms) / 60_000)
    if minutes < 1 { return "刚刚" }
    if minutes < 60 { return "\(minutes) 分钟前" }
    if minutes < 1440 { return "\(minutes / 60) 小时前" }
    return "\(minutes / 1440) 天前"
  }
}
