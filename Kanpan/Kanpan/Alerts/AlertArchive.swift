import Foundation
import KanpanCore

/// 提醒的存档与落盘。
///
/// 和画线那一份（`DrawStore`）同一个姿态：一份 JSON 整存整取，落在账号目录里
/// （`Application Support/kanpan/accounts/<人>/alerts.json`），杀 app 重开还在，
/// 换账号跟着换。提醒总共也就几十条，不做增量。
///
/// 存档里**不按品种分桶**：提醒列表是一张跨品种的总表（方案 2.3），按品种分桶
/// 反而要为了列一页把所有桶拼起来。要按品种取的地方自己 `filter`。
struct AlertArchive: Sendable, Equatable, Codable {
  static let currentVersion = 1
  /// 一个人最多存多少条。提醒是要往服务端占评估名额的东西，不能无上限。
  static let limit = 200

  var version: Int
  var alerts: [Alert]

  init(version: Int = AlertArchive.currentVersion, alerts: [Alert] = []) {
    self.version = version; self.alerts = alerts
  }

  private enum CodingKeys: String, CodingKey { case version = "v", alerts = "a" }

  init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    alerts = try c.decodeIfPresent([Alert].self, forKey: .alerts) ?? []
  }

  subscript(id: String) -> Alert? {
    get { alerts.first { $0.id == id } }
    set {
      guard let newValue else { alerts.removeAll { $0.id == id }; return }
      if let i = alerts.firstIndex(where: { $0.id == id }) { alerts[i] = newValue } else { alerts.append(newValue) }
    }
  }

  func alerts(symbol: String) -> [Alert] { alerts.filter { $0.symbol == InstrumentID.canonical(symbol) } }

  /// 这个品种上「已经有提醒」的那些线。图上那枚小铃铛照它画。
  func alertedDrawingIDs(symbol: String) -> Set<String> {
    Set(alerts.filter { $0.symbol == InstrumentID.canonical(symbol) && $0.status != .fired }.compactMap(\.drawingID))
  }

  var hasRoom: Bool { alerts.count < Self.limit }

  /// 列表的排序：还在等的排前面，各自按建立时间倒序。
  var sorted: [Alert] {
    alerts.sorted { a, b in
      if a.isActive != b.isActive { return a.isActive }
      return a.created > b.created
    }
  }

  /// 画线提醒的线在本机存档里找不到时，列表上给这条提醒的那句话。
  static let drawingMissingNote = "画线已不存在"

  /// 这条画线提醒的线眼下找不到（对账时被暂停、等线回来或者等用户自己删）。
  ///
  /// `paused` 这个状态别处都不产出（没有「手动暂停」这个入口），所以画线提醒处在
  /// `paused` 就只有这一种来历；两端评估器都不判 `paused`（前台 `isActive`、服务端
  /// `alerts.rs` 的 `reported_fire`），线不在的时候它不会凭一条看不见的线响。
  static func isDrawingMissing(_ alert: Alert) -> Bool { alert.kind == .drawing && alert.status == .paused }

  /// 跟着画线存档对一遍账（方案第 10 节「画线前台提醒的三条规则」）。
  ///
  /// - 线被**本机删掉**了（`previous` 里还在、`drawings` 里没了）→ 提醒跟着删（显式级联）。
  /// - 线**找不到、但说不清是被删的**（没有 `previous`、或者 `previous` 里也没有）→ 提醒留着，
  ///   暂停并标成「画线已不存在」（`isDrawingMissing`）。常见来历：别的设备画的线和它的提醒
  ///   分两摊同步，提醒先到、线还在路上；老版本认不出新工具，解存档时把那条线丢了。
  ///   从前这两种都当「线被删了」把提醒删掉，删除还会同步上去，把别的设备上好好的提醒也带走。
  /// - 线回来了 → 暂停的那条恢复生效，`armedAt` 重置成现在（离线那段不补判）。
  /// - 线被挪了 → 几何重算，`armedAt` 重置成现在。不重置的话，刚挪过去的这条线
  ///   会被历史 K 线当场判成已触发——用户看到的是「我刚一松手它就响了」。
  /// - 别的（改颜色、上锁、隐藏）不动提醒：那些不改线在哪儿。
  ///
  /// 返回真表示存档变了，调用方要落盘 + 同步。
  static func reconcile(_ archive: inout AlertArchive, with drawings: DrawArchive,
                        previous: DrawArchive? = nil, now: Double) -> Bool {
    var changed = false
    var kept: [Alert] = []
    for var alert in archive.alerts {
      guard alert.kind == .drawing, let drawingID = alert.drawingID else { kept.append(alert); continue }
      guard let drawing = drawings[alert.symbol].first(where: { $0.id == drawingID }),
            let lines = AlertGeometry.lines(for: drawing) else {
        let deletedHere = previous.map { prior in
          prior[alert.symbol].contains { $0.id == drawingID }
            && !drawings[alert.symbol].contains { $0.id == drawingID }
        } ?? false
        if deletedHere { changed = true; continue }
        if alert.status == .active { alert.status = .paused; changed = true }
        kept.append(alert)
        continue
      }
      if alert.status == .paused {
        alert.status = .active
        alert.armedAt = now
        changed = true
      }
      if lines != alert.lines {
        alert.lines = lines
        alert.armedAt = now
        changed = true
      }
      kept.append(alert)
    }
    if changed { archive.alerts = kept }
    return changed
  }

  /// 显式级联：这几条线被删了，挂在上面的提醒一并删掉。返回删了几条。
  @discardableResult
  mutating func removeAlerts(symbol: String, drawingIDs: Set<String>) -> Int {
    let key = InstrumentID.canonical(symbol)
    let before = alerts.count
    alerts.removeAll { $0.kind == .drawing && $0.symbol == key && $0.drawingID.map(drawingIDs.contains) == true }
    return before - alerts.count
  }
}

/// 一份 JSON 文件，整存整取。写法照抄 `DrawStore`：先写临时文件再原子替换。
struct AlertFileStore: Sendable {
  var url: URL
  init(url: URL) { self.url = url }

  static func applicationSupport() -> AlertFileStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    #if DEBUG
    if let sandbox = testSandbox(under: base) {
      return AlertFileStore(url: sandbox.appendingPathComponent("alerts.json"))
    }
    #endif
    let folder = base.appendingPathComponent("kanpan", isDirectory: true)
    return AlertFileStore(url: folder.appendingPathComponent("alerts.json"))
  }

  #if DEBUG
  /// UI 测试要一份互不打架的提醒档案：一个测试进程一个 UUID 目录，开关和
  /// `PrefsStore.deviceStorage()` 是同一套。
  ///
  /// 整段关在 `#if DEBUG` 里：Release 包里没有「测试档案」这回事，提醒只存一个地方
  /// （审查 C.10-1，由 `ReleaseHookScanTests` 机械盯着）。
  private static func testSandbox(under base: URL) -> URL? {
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" else { return nil }
    let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"]
      .flatMap { UUID(uuidString: $0)?.uuidString } ?? "default"
    return base.appendingPathComponent("kanpan-alert-tests", isDirectory: true)
      .appendingPathComponent(profile, isDirectory: true)
  }
  #endif

  func read() throws -> AlertArchive {
    guard FileManager.default.fileExists(atPath: url.path) else { return AlertArchive() }
    let data = try Data(contentsOf: url)
    var archive = try JSONDecoder().decode(AlertArchive.self, from: data)
    archive.version = AlertArchive.currentVersion
    return archive
  }

  /// 读不动一律当空档，**不抛**：提醒丢了是可惜，因为它开不了图是不可接受的。
  func load() -> AlertArchive { (try? read()) ?? AlertArchive() }

  func save(_ archive: AlertArchive) throws {
    var value = archive
    value.version = AlertArchive.currentVersion
    let data = try JSONEncoder().encode(value)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
