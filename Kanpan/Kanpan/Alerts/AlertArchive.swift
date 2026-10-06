import Foundation
import KanpanChart
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
  /// 一个人在**本机新建**时最多建到多少条。提醒是要往服务端占评估名额的东西，不能无上限。
  ///
  /// 只卡本机新建那三个口（`AlertStore.add(drawing:)` / `addPrice` / `addCondition`）。
  /// 同步换下来的（别的设备建的）、派生出来的（复盘到点）一律收下、不受这个数限制——
  /// 2026-10-06 用户：「提醒只要没失效也要留存」。失效只有两种：触发了（触发即删）、
  /// 复盘到点过了一天。
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

  /// 本机还能不能再新建一条（只给新建那几个口用，见 `limit`）。
  var hasRoom: Bool { alerts.count < Self.limit }

  /// 这个品种上的提醒线：生效中的画线提醒，按它自己存的那份几何（见 `AlertStore.signals`）。
  func signals(symbol: String) -> [ChartAlertSignal] {
    let key = InstrumentID.canonical(symbol)
    return alerts.compactMap { alert in
      guard alert.kind == .drawing, alert.status == .active, alert.symbol == key, !alert.lines.isEmpty else { return nil }
      return ChartAlertSignal(id: alert.id, drawingID: alert.drawingID, lines: alert.lines)
    }
  }

  /// 列表的排序：还在等的排前面，各自按建立时间倒序。
  var sorted: [Alert] {
    alerts.sorted { a, b in
      if a.isActive != b.isActive { return a.isActive }
      return a.created > b.created
    }
  }

  /// 跟着画线存档对一遍账。
  ///
  /// **2026-10-06 起画线与提醒互相独立**（用户：「画线和警报是不冲突的，我删除画线也不应该
  /// 删除警报才对」「即使画线删除也应该保留预警信号」）：
  ///
  /// - 线**不在了**（本机删掉、别的设备删掉、还在路上、老版本解不出来，一概不分）→ 提醒原样
  ///   留着、照常生效，按它自己存下来的 `lines` 继续判；图上由提醒线（虚线 + 铃铛）接着指出来。
  ///   不暂停、不删、不问。从前本机删线会显式级联删提醒、说不清来历的缺线会暂停并标
  ///   「画线已不存在」，这两条都撤了。
  /// - 线**被挪了 / 回来了且几何变了** → 几何重算，`armedAt` 重置成现在。不重置的话，刚挪过去的
  ///   这条线会被历史 K 线当场判成已触发——用户看到的是「我刚一松手它就响了」。
  /// - 别的（改颜色、上锁、隐藏）不动提醒：那些不改线在哪儿。
  /// - 旧版本留下的暂停态画线提醒（上面那条「缺线暂停」的产物）一律复活：状态改回生效中、
  ///   `armedAt` 重置成现在（暂停那段不补判）。`paused` 别处都不产出，所以画线提醒处在
  ///   `paused` 只有这一种来历。
  ///
  /// 提醒只剩两种删法：用户自己删（提醒列表、选中栏的提醒胶囊），以及触发即删。
  ///
  /// 返回真表示存档变了，调用方要落盘 + 同步。
  static func reconcile(_ archive: inout AlertArchive, with drawings: DrawArchive, now: Double) -> Bool {
    var changed = revivePaused(&archive, now: now)
    for i in archive.alerts.indices {
      let alert = archive.alerts[i]
      guard alert.kind == .drawing, alert.status == .active, let drawingID = alert.drawingID,
            let drawing = drawings[alert.symbol].first(where: { $0.id == drawingID }),
            let lines = AlertGeometry.lines(for: drawing), lines != alert.lines else { continue }
      archive.alerts[i].lines = lines
      archive.alerts[i].armedAt = now
      changed = true
    }
    return changed
  }

  /// 旧版本「缺线暂停」留下的画线提醒，复活成生效中（`armedAt` = 现在）。返回真表示动了东西。
  ///
  /// 载入存档（启动、登录 / 换号、云端推下来）之后由 `AlertStore.reviveLegacyPaused` 调一次，
  /// 对账（`reconcile`）每次也顺手过一遍。
  static func revivePaused(_ archive: inout AlertArchive, now: Double) -> Bool {
    var changed = false
    for i in archive.alerts.indices where archive.alerts[i].kind == .drawing && archive.alerts[i].status == .paused {
      archive.alerts[i].status = .active
      archive.alerts[i].armedAt = now
      changed = true
    }
    return changed
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
