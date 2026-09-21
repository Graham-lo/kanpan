import Combine
import Foundation
import KanpanCore

/// 提醒模块手上那份存档。
///
/// 一个功能收拢成一个模块：建、删、改条件、标记触发、跟着画线对账、落盘、
/// 交给账号桥同步，全在这儿；图表、宿主页、账号桥都只是叫它做事的人。
///
/// 和 `DrawingController` 同一套三段式接口（`commitSynced` 只落盘、`publishSynced`
/// 才动内存与界面），这样账号桥那边两摊东西能排在同一次提交里。
@MainActor
final class AlertStore: ObservableObject {
  @Published private(set) var archive: AlertArchive
  /// 存档变了就响一次；账号桥挂在这儿记账 + 同步。
  var onChange: ((AlertArchive) -> Void)?
  /// 正式文件（`alerts.json`）那次写什么时候真的发生。和画线那儿
  /// （`DrawingController.persistence`）逐字同义：默认就地同步写，登录之后由账号桥
  /// 换成「排在同步存档这一版落盘之后，在写盘队列上写」，让「存档先落」重新变成
  /// 队列顺序保证的事，而不是两次写之间的竞态。交给它的活儿不在 MainActor 上跑。
  var persistence: @MainActor (@escaping @Sendable () -> Void) -> Void = { $0() }
  /// 落盘出事时说一句。宿主接到主 toast 上。
  @Published var notice: String?

  private var store: AlertFileStore

  init(store: AlertFileStore = .applicationSupport()) {
    self.store = store
    #if DEBUG
    self.archive = Self.testSeed(into: store.load()) ?? store.load()
    #else
    self.archive = store.load()
    #endif
  }

  #if DEBUG
  /// UI 测试要一条「服务端已经判到价、同步换下来」的提醒。
  ///
  /// 那一段的上半截（服务端判定 → 写同步日志）在服务端，客户端一个字都没有，
  /// 所以用例只能量下半截：总表上看得见「已触发」、按得着「再次提醒」。开局那份存档
  /// 没法从外面塞进 app 的沙盒（跑用例的是另一个进程），于是按 `SymbolPrefs.testSeed`
  /// 同一套路，从启动环境里认一条：`KANPAN_TEST_ALERT_FIRED=<代号>`（要配
  /// `KANPAN_TEST_PROFILE=1`，且存档是空的时候才种）。整段关在 `#if DEBUG` 里，
  /// Release 包里不存在（审查 C.10-1）。
  static func testSeed(into archive: AlertArchive,
                       environment: [String: String] = ProcessInfo.processInfo.environment,
                       now: Double = Date().timeIntervalSince1970 * 1000) -> AlertArchive? {
    guard environment["KANPAN_TEST_PROFILE"] == "1",
          let symbol = environment["KANPAN_TEST_ALERT_FIRED"], !symbol.isEmpty,
          archive.alerts.isEmpty else { return nil }
    let price = 50_000.0
    let line = AlertLine(points: [DrawPoint(t: now - 3_600_000, p: price)],
                         extendLeft: true, extendRight: true)
    var seeded = archive
    seeded.alerts.append(Alert(symbol: symbol, drawingID: "seeded-line", lines: [line],
                               armedAt: now - 7_200_000, status: .fired,
                               firedAt: now - 60_000, firedPrice: price,
                               title: Alert.title(symbol: symbol, drawingKind: .hline),
                               created: now - 7_200_000))
    return seeded
  }
  #endif

  var all: [Alert] { archive.alerts }
  var sorted: [Alert] { archive.sorted }
  var activeCount: Int { archive.alerts.filter(\.isActive).count }
  func alerts(symbol: String) -> [Alert] { archive.alerts(symbol: symbol) }
  func alertedDrawingIDs(symbol: String) -> Set<String> { archive.alertedDrawingIDs(symbol: symbol) }
  func alert(id: String) -> Alert? { archive[id] }
  func alert(symbol: String, drawingID: String) -> Alert? {
    archive.alerts.first { $0.symbol == symbol && $0.drawingID == drawingID }
  }

  // ---------------------------------------------------------------- 增删改

  /// 给图上那条线加一条提醒。种类不支持（摊不出线）就什么都不做，返回 nil。
  @discardableResult
  func add(drawing: Drawing, symbol: String, now: Double = Date().timeIntervalSince1970 * 1000) -> Alert? {
    guard let lines = AlertGeometry.lines(for: drawing) else { return nil }
    guard archive.hasRoom else { notice = "提醒最多 \(AlertArchive.limit) 条"; return nil }
    // 同一条线只留一条提醒：再点一次「加入提醒」是「还要」，不是「再来一条」。
    if let existing = alert(symbol: symbol, drawingID: drawing.id) {
      var next = existing
      next.lines = lines; next.armedAt = now; next.status = .active
      next.firedAt = nil; next.firedPrice = nil
      write { $0[existing.id] = next }
      return next
    }
    let alert = Alert(symbol: symbol, drawingID: drawing.id, lines: lines,
                      armedAt: now, title: Alert.title(symbol: symbol, drawingKind: drawing.kind),
                      created: now)
    write { $0.alerts.append(alert) }
    return alert
  }

  func remove(id: String) { write { $0[id] = nil } }

  func remove(symbol: String, drawingID: String) {
    write { $0.alerts.removeAll { $0.symbol == symbol && $0.drawingID == drawingID } }
  }

  func setCondition(_ condition: Alert.Condition, id: String) {
    guard var alert = archive[id], alert.condition != condition else { return }
    alert.condition = condition
    write { $0[id] = alert }
  }

  /// 「再次提醒」：重新上膛，从现在起算。
  func rearm(id: String, now: Double = Date().timeIntervalSince1970 * 1000) {
    guard var alert = archive[id] else { return }
    alert.status = .active; alert.armedAt = now; alert.firedAt = nil; alert.firedPrice = nil
    write { $0[id] = alert }
  }

  /// 响了。前台评估和服务端推下来的那条走同一个口，`once` 保证只记一次。
  @discardableResult
  func markFired(id: String, at time: Double, price: Double) -> Alert? {
    guard var alert = archive[id], alert.status == .active else { return nil }
    alert.status = .fired; alert.firedAt = time; alert.firedPrice = price
    write { $0[id] = alert }
    return alert
  }

  /// 跟着画线存档对一遍账。返回真表示真的动了东西。
  @discardableResult
  func reconcile(with drawings: DrawArchive, now: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
    var next = archive
    guard AlertArchive.reconcile(&next, with: drawings, now: now) else { return false }
    write { $0 = next }
    return true
  }

  // ---------------------------------------------------------------- 落盘

  private func write(_ change: (inout AlertArchive) -> Void) {
    var next = archive
    change(&next)
    guard next != archive else { return }
    archive = next
    // 顺序和画线那儿一样：先把「用户要什么」交给同步存档，再落自己的正式文件。
    // **这个顺序现在由队列保证**（`persistence` → `SyncStore.afterArchiveWritten`），
    // 不再靠记账那一侧在主线程上阻塞等存档写完。反过来的「新 alerts.json + 旧存档」
    // 是启动前向对账补不回来的那一侧：存档里既没有新值也没有待发操作，
    // 下一次拉取会拿云端那份旧的把用户刚设的提醒盖回去。
    onChange?(next)
    let store = self.store, value = next
    persistence { [weak self] in
      do { try store.save(value) }
      catch { Task { @MainActor in self?.notice = "提醒未能保存。请检查设备存储空间。" } }
    }
  }

  // ---------------------------------------------------------------- 账号

  func useStorage(_ store: AlertFileStore, archive: AlertArchive) {
    self.store = store
    self.archive = archive
  }

  /// 三段式的「落盘」：只写文件，可见状态一个都不动。
  func commitSynced(_ value: AlertArchive) throws {
    guard value != archive else { return }
    try store.save(value)
  }

  /// 三段式的「发布」：内存与界面换成刚落下去的那一版。
  func publishSynced(_ value: AlertArchive) {
    guard value != archive else { return }
    archive = value
  }
}
