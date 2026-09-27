import Foundation

/// 「按我的习惯自动调整」的行为日志：一条一件事，只留在这台机器上，不上传。
///
/// 结论（`LearnedDefaults`）是从它推出来的，随账号同步的是结论不是日志。
/// 形状只有四样——时刻、种类、键、值——外加一个权重（停留秒数；别的种类恒为 1）。
/// 30 天前的丢掉，总条数有上限，整份几十 KB。
struct HabitEvent: Codable, Equatable, Sendable {
  enum Kind: String, Codable, Sendable {
    /// 在某只品种上以某个周期看了多久。键 = 品种规范键，值 = 周期（`Interval.rawValue`），`w` = 秒。
    case interval
    /// 在某一类品种上以某种价格轴看了多久。键 = 类别，值 = `linear` / `log`，`w` = 秒。
    case axisDwell
    /// 在图表设置里亲手切了价格轴。键 = 类别，值 = `linear` / `log`。
    case axisPick
    /// 板块页选了「今日 / 5 日」。键 = 市场（`SectorMarket.rawValue`），值 = `SectorWindow.rawValue`。
    case sectorWindow
    /// 自选波动提醒响了。键 = 品种规范键。
    case moveFired
    /// 响过之后点开了那只。键 = 品种规范键。
    case moveOpened
  }

  /// Unix 秒。
  var t: Double
  var kind: Kind
  var key: String
  var value: String
  var w: Double

  init(t: Double, kind: Kind, key: String, value: String = "", w: Double = 1) {
    self.t = t; self.kind = kind; self.key = key; self.value = value; self.w = w
  }

  private enum CodingKeys: String, CodingKey { case t, kind, key, value, w }

  // 空值与权重 1 不写出去：日志里多数是这种，省一截。
  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    t = try c.decode(Double.self, forKey: .t)
    kind = try c.decode(Kind.self, forKey: .kind)
    key = try c.decode(String.self, forKey: .key)
    value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
    w = try c.decodeIfPresent(Double.self, forKey: .w) ?? 1
  }

  func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(t, forKey: .t)
    try c.encode(kind, forKey: .kind)
    try c.encode(key, forKey: .key)
    if !value.isEmpty { try c.encode(value, forKey: .value) }
    if w != 1 { try c.encode(w, forKey: .w) }
  }
}

/// 日志本身：一串按时间排好的事件，外加修剪规则。纯值类型，单测直接造。
struct HabitLog: Codable, Equatable, Sendable {
  /// 只看最近 30 天。
  static let retention: Double = 30 * 86_400
  /// 总条数上限。一条编码后七八十字节；停留类同一小时内并成一条（`append`），
  /// 天天看也就几百条，这个上限只是兜底，整份几十 KB 量级。
  static let capacity = 2_000
  /// 停留类事件同一只、同一值在这么近的时间里再来一段，就并进上一条（加秒数、挪时刻）。
  static let coalesceWindow: Double = 3_600

  private(set) var events: [HabitEvent] = []

  init(events: [HabitEvent] = []) { self.events = events.sorted { $0.t < $1.t } }

  var isEmpty: Bool { events.isEmpty }

  mutating func append(_ event: HabitEvent, now: Double) {
    if event.kind == .interval || event.kind == .axisDwell,
       let i = events.lastIndex(where: { $0.kind == event.kind && $0.key == event.key }),
       events[i].value == event.value, event.t >= (events.last?.t ?? 0), event.t - events[i].t < Self.coalesceWindow,
       i >= events.count - 8 {
      events[i].w += event.w
      events[i].t = event.t
      let merged = events.remove(at: i)
      events.append(merged)
      prune(now: now)
      return
    }
    // 时钟被往回拨过：插到该在的位置，保持有序（推断按时间先后走）。
    if let last = events.last, event.t < last.t {
      let at = events.firstIndex { $0.t > event.t } ?? events.endIndex
      events.insert(event, at: at)
    } else {
      events.append(event)
    }
    prune(now: now)
  }

  /// 丢掉 30 天以前的；超出上限从最旧的丢。
  mutating func prune(now: Double) {
    let cutoff = now - Self.retention
    if let first = events.firstIndex(where: { $0.t >= cutoff }) {
      if first > 0 { events.removeFirst(first) }
    } else {
      events.removeAll()
    }
    if events.count > Self.capacity { events.removeFirst(events.count - Self.capacity) }
  }

  mutating func removeAll() { events.removeAll() }
}

/// 日志落在哪。和 `PrefsStore.deviceStorage()` 同一个柜子（UI 用例里是内存 / 测试套件），
/// 一个档案（账号 id / 访客）一份，换人不串。
@MainActor
struct HabitLogStore {
  var storage: any PrefsStorage

  static func key(owner: String) -> String {
    "kanpan.habits.log.v1." + (owner.isEmpty ? "guest" : owner)
  }

  func load(owner: String) -> HabitLog {
    guard let data = storage.prefsData(forKey: Self.key(owner: owner)),
          let log = try? JSONDecoder().decode(HabitLog.self, from: data) else { return HabitLog() }
    return log
  }

  func save(_ log: HabitLog, owner: String) {
    storage.setPrefsData(log.isEmpty ? nil : try? JSONEncoder().encode(log), forKey: Self.key(owner: owner))
  }
}
