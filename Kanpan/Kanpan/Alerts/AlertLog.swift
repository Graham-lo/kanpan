import Foundation
import KanpanCore
import Observation
import KanpanAccount

/// 「提醒」sheet 的「日志」页：响过的提醒一条一条记下来（2026-10-05，照 TradingView 手机版的 Alerts › Log）。
///
/// 本机这边响过的提醒发完通知就从存档里删了（`AlertWatcher`，只响一次、响完就算完），
/// 所以「响过什么」只有服务端那份账有：价格 / 画线提醒由服务端盯价时判、条件提醒本来就在服务端判、
/// 复盘到点也由它推。日志按账号存在 `kanpan-api`：
///
/// - `GET v1/alerts/log?limit=200`（要登录）→ `{"records":[…]}`（裸的或包在 `{"data":…}` 里都认），
///   每条 `id / alertId / kind(price|line|condition|reviewDue) / symbol / title / condition /
///   firedAt(毫秒) / firedPrice`，按响的时间倒序；
/// - `DELETE v1/alerts/log` → 204，清空；
/// - **404 = 服务端还没有这条路**：当作「暂无记录」，不当成故障。
///
/// 进页就拉一趟、下拉再拉；拉到的按账号存一份在本机（`UserDefaults`，200 条不过几十 KB），
/// 断网 / 服务器宕机时照常摆上一次那份（云端只是同步通道，不是可用性依赖）。没登录就只有一句
/// 「登录后可查看」。不传 `since` 做增量：清空之后要整份对齐，200 条一趟拉完不值得再记游标。
struct AlertLogRecord: Codable, Equatable, Identifiable, Sendable {
  var id: String
  var alertId: String?
  /// `price` / `line` / `condition` / `reviewDue`。认不得的也照摆，只当价格类。
  var kind: String
  var symbol: String
  var title: String
  var condition: String?
  /// 响的那一刻，UTC 毫秒。
  var firedAt: Int64
  var firedPrice: Double?

  private enum CodingKeys: String, CodingKey {
    case id, alertId, kind, symbol, title, condition, firedAt, firedPrice
  }

  init(id: String, alertId: String? = nil, kind: String, symbol: String, title: String,
       condition: String? = nil, firedAt: Int64, firedPrice: Double? = nil) {
    self.id = id; self.alertId = alertId; self.kind = kind; self.symbol = symbol; self.title = title
    self.condition = condition; self.firedAt = firedAt; self.firedPrice = firedPrice
  }

  /// 宽进：服务端多给的字段不管，少给的可选字段当空；`firedAt` 是浮点也认。
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(String.self, forKey: .id)
    alertId = try c.decodeIfPresent(String.self, forKey: .alertId)
    kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "price"
    symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? ""
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    condition = try c.decodeIfPresent(String.self, forKey: .condition)
    if let whole = try? c.decode(Int64.self, forKey: .firedAt) {
      firedAt = whole
    } else {
      firedAt = Int64(try c.decode(Double.self, forKey: .firedAt))
    }
    firedPrice = try c.decodeIfPresent(Double.self, forKey: .firedPrice)
  }
}

/// 日志的拆包、分天、写时间。纯函数，单测直接调。
enum AlertLogText {
  private struct Records: Decodable { var records: [AlertLogRecord] }
  private struct Wrapped: Decodable { var data: Records }

  /// 拆包：`{"records":[…]}` 或 `{"data":{"records":[…]}}`；按响的时间倒序（同一刻按 id 定序，免得刷新时跳行）。
  static func decode(_ data: Data) throws -> [AlertLogRecord] {
    let decoder = JSONDecoder()
    let records: [AlertLogRecord]
    if let bare = try? decoder.decode(Records.self, from: data) {
      records = bare.records
    } else {
      records = try decoder.decode(Wrapped.self, from: data).data.records
    }
    return sorted(records)
  }

  static func sorted(_ records: [AlertLogRecord]) -> [AlertLogRecord] {
    records.sorted { $0.firedAt != $1.firedAt ? $0.firedAt > $1.firedAt : $0.id > $1.id }
  }

  /// 按天分的一组。
  struct Day: Equatable, Identifiable {
    /// 当地日历上的那一天（自 1970-01-01 起的天数），只作身份。
    var day: Int64
    /// 「今天」「昨天」「10月3日」「2025年10月3日」。
    var title: String
    var records: [AlertLogRecord]
    var id: Int64 { day }
  }

  private static let dayMs: Int64 = 86_400_000

  /// 当地（`zone`，默认上海）那一天。
  static func localDay(_ ms: Int64, zone: TZOffset) -> Int64 {
    let local = ms + Int64(zone.minutes(at: Double(ms))) * 60_000
    return local >= 0 ? local / dayMs : (local - dayMs + 1) / dayMs
  }

  /// 按当地的天分组，组内与组间都是倒序（输入已排好就保持原序）。
  static func days(_ records: [AlertLogRecord], zone: TZOffset,
                   now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> [Day] {
    let today = localDay(now, zone: zone)
    var out: [Day] = []
    for record in sorted(records) {
      let day = localDay(record.firedAt, zone: zone)
      if out.last?.day == day {
        out[out.count - 1].records.append(record)
      } else {
        out.append(Day(day: day, title: dayTitle(day, today: today), records: [record]))
      }
    }
    return out
  }

  static func dayTitle(_ day: Int64, today: Int64) -> String {
    if day == today { return "今天" }
    if day == today - 1 { return "昨天" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let date = Date(timeIntervalSince1970: TimeInterval(day * 86_400))
    let todayDate = Date(timeIntervalSince1970: TimeInterval(today * 86_400))
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    let md = "\(c.month ?? 1)月\(c.day ?? 1)日"
    return calendar.component(.year, from: todayDate) == c.year ? md : "\(c.year ?? 1970)年" + md
  }

  /// 行尾那个时刻：`14:03`（当地 24 小时制）。
  static func clock(_ ms: Int64, zone: TZOffset) -> String {
    let local = ms + Int64(zone.minutes(at: Double(ms))) * 60_000
    let inDay = ((local % dayMs) + dayMs) % dayMs
    let minutes = inDay / 60_000
    return String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  /// 行上第二行：条件（服务端写好的「价格达到 85,000」之类；没有就用标题）· 响时的价。都没有就空。
  static func detail(_ record: AlertLogRecord, decimals: Int?) -> String {
    var parts: [String] = []
    let condition = record.condition?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !condition.isEmpty {
      parts.append(condition)
    } else if !title.isEmpty {
      parts.append(title)
    }
    if let price = record.firedPrice, price.isFinite, price > 0 {
      parts.append("触发价 " + AlertMessage.groupedPrice(price, decimals: decimals))
    }
    return parts.joined(separator: " · ")
  }

  /// 行上第一行：品种名（「BTC/USDT」）。服务端没给品种时用标题，再没有就叫「提醒」。
  static func name(_ record: AlertLogRecord) -> String {
    if !record.symbol.isEmpty { return AlertRecordText.pairName(record.symbol) }
    let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? "提醒" : title
  }
}

/// 日志页的状态：本机那份缓存 + 一趟拉取 / 清空。按账号分开存，换号不串。
@Observable @MainActor
final class AlertLogModel {
  enum Phase: Equatable {
    /// 还没拉过（摆的是缓存）。
    case idle
    case loading
    case loaded
    /// 拉不到（断网、服务端 5xx）：照摆缓存。
    case failed
  }

  /// 发一趟请求：路径（不带开头的斜杠）、方法 → 回包。非 2xx 抛 `AccountError.http`。
  typealias Fetch = @Sendable (_ path: String, _ method: String) async throws -> Data

  private(set) var records: [AlertLogRecord] = []
  private(set) var phase: Phase = .idle
  private(set) var owner: UUID?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var task: Task<Void, Never>?

  static let path = "v1/alerts/log"
  static let limit = 200

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  static func cacheKey(_ owner: UUID) -> String { "alertLog.cache." + owner.uuidString.lowercased() }

  /// 换到这个人（nil = 没登录）：摆上他那份缓存。
  func select(owner: UUID?) {
    guard owner != self.owner else { return }
    task?.cancel(); task = nil
    self.owner = owner
    phase = .idle
    records = owner.map(readCache) ?? []
  }

  /// 拉一趟。404（服务端还没这条路）当空；别的失败照摆缓存。
  func refresh(owner: UUID?, fetch: Fetch?) async {
    select(owner: owner)
    guard let owner, let fetch else { return }
    phase = .loading
    do {
      let data = try await fetch(Self.path + "?limit=\(Self.limit)", "GET")
      guard self.owner == owner else { return }
      apply(try AlertLogText.decode(data), owner: owner)
    } catch AccountError.http(404, _) {
      guard self.owner == owner else { return }
      apply([], owner: owner)
    } catch {
      guard self.owner == owner else { return }
      phase = .failed
    }
  }

  /// 清空。成功（204，或服务端没这条路的 404）后本机那份一起清；失败返回 false，列表不动。
  @discardableResult
  func clear(fetch: Fetch?) async -> Bool {
    guard let owner, let fetch else { return false }
    do {
      _ = try await fetch(Self.path, "DELETE")
    } catch AccountError.http(404, _) {
    } catch {
      return false
    }
    guard self.owner == owner else { return false }
    apply([], owner: owner)
    return true
  }

  private func apply(_ records: [AlertLogRecord], owner: UUID) {
    self.records = records
    phase = .loaded
    if let data = try? JSONEncoder().encode(records) { defaults.set(data, forKey: Self.cacheKey(owner)) }
  }

  private func readCache(_ owner: UUID) -> [AlertLogRecord] {
    guard let data = defaults.data(forKey: Self.cacheKey(owner)),
          let records = try? JSONDecoder().decode([AlertLogRecord].self, from: data) else { return [] }
    return AlertLogText.sorted(records)
  }
}
