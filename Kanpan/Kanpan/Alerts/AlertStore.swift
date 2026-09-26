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
  @Published private(set) var archive: AlertArchive {
    // 存档一变，总表那份排好的分段与行跟着作废；下次有人读再排一趟（压测收尾第 5 项）。
    didSet { cachedRows = nil }
  }
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
  /// 所以用例只能量下半截：2026-09-25 v3 起是「触发即删」——这条开局就躺着的已触发提醒
  /// 在总表和创建页都看不见，并且被 `AlertWatcher` 从存档里清掉。开局那份存档
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

  /// 总表（「全部预警」）摆的那一列：分段、按品种分组、排好序、摊平成行。
  ///
  /// 原来总表 body 每跑一趟都 `AlertRecordText.sections(store.all)` 现排一遍（过滤、
  /// 两次排序、按品种分组），而 body 会被任何一次写、`notice`、宿主换一口价叫醒。
  /// 现在只在存档变了之后第一次读的时候排一趟，读多少遍都不再排。
  var listRows: [AlertListItem] {
    if let cachedRows { return cachedRows }
    let rows = AlertListItem.rows(AlertRecordText.sections(archive.alerts))
    cachedRows = rows
    listRowBuilds += 1
    return rows
  }
  private var cachedRows: [AlertListItem]?
  /// 总表那一列排过几趟。只给单测数次数用。
  private(set) var listRowBuilds = 0
  /// 界面上看得见的那些：已触发只是「通知 / Webhook 发出去之前」的一瞬间，不展示
  /// （复盘到点例外，它的「已到点」就是给人看的，一天后由 `ReviewDueAlerts` 清）。
  var visible: [Alert] { archive.alerts.filter(AlertRecordText.isVisible) }
  var sorted: [Alert] { archive.sorted }
  var activeCount: Int { archive.alerts.filter(\.isActive).count }
  func alerts(symbol: String) -> [Alert] { archive.alerts(symbol: symbol) }
  func alertedDrawingIDs(symbol: String) -> Set<String> { archive.alertedDrawingIDs(symbol: symbol) }
  func alert(id: String) -> Alert? { archive[id] }
  func alert(symbol: String, drawingID: String) -> Alert? {
    archive.alerts.first { $0.symbol == InstrumentID.canonical(symbol) && $0.drawingID == drawingID }
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

  /// 裸价格提醒：图上十字线那颗「创建提醒」弹出的新建页走这一个口（`AlertStore.commit`）。
  /// 方向按现价自动定（`Alert.price`）。同一只品种同一个价已经有一条活动的就不再建第二条——
  /// 把这一次填的条件、Webhook、备注落到那一条上，返回它。
  @discardableResult
  func addPrice(symbol: String, target: Double, current: Double?, label: String,
                condition: Alert.Condition = .touch,
                webhook: String? = nil, webhookText: String? = nil, note: String? = nil,
                now: Double = Date().timeIntervalSince1970 * 1000) -> Alert? {
    let symbol = InstrumentID.canonical(symbol)
    guard target.isFinite, target > 0, !symbol.isEmpty else { return nil }
    if let same = archive.alerts.first(where: {
      $0.kind == .price && $0.isActive && $0.symbol == symbol && $0.targetPrice == target
    }) {
      return update(id: same.id, target: target, current: current, label: label, condition: condition,
                    webhook: webhook, webhookText: webhookText, note: note, now: now) ?? same
    }
    guard archive.hasRoom else { notice = "提醒最多 \(AlertArchive.limit) 条"; return nil }
    let alert = Alert.price(symbol: symbol, target: target, current: current, label: label, now: now,
                            condition: condition, webhook: Self.clean(webhook: webhook),
                            webhookText: Self.clean(template: webhookText), note: Alert.blankIsNil(note))
    write { $0.alerts.append(alert) }
    return alert
  }

  /// 编辑一条裸价格提醒（表单的「保存」）。条件、Webhook、备注照填的改；
  /// **价变了**就重挂那条水平线、按现价重写标题，并且从现在起重新布防
  /// （`armedAt` = 现在、`status` = 生效中、清掉上一次的触发记录）——否则挪过去的
  /// 那一刻就被当前这一分钟判成已触发。价没变只改设置，布防状态不动。
  @discardableResult
  func update(id: String, target: Double, current: Double?, label: String,
              condition: Alert.Condition,
              webhook: String?, webhookText: String?, note: String?,
              now: Double = Date().timeIntervalSince1970 * 1000) -> Alert? {
    guard var alert = archive[id], alert.kind == .price, target.isFinite, target > 0 else { return nil }
    if alert.targetPrice != target {
      let fresh = Alert.price(symbol: alert.symbol, target: target, current: current, label: label, now: now)
      alert.lines = fresh.lines; alert.title = fresh.title
      alert.armedAt = now; alert.status = .active; alert.firedAt = nil; alert.firedPrice = nil
    }
    alert.condition = condition
    alert.webhook = Self.clean(webhook: webhook)
    alert.webhookText = Self.clean(template: webhookText)
    alert.note = Alert.blankIsNil(note.map(Alert.clip(note:)))
    write { $0[id] = alert }
    return alert
  }

  /// Webhook 地址：去掉首尾空白，不合法就当没填（表单那边已经拦了，这里兜底）。
  static func clean(webhook: String?) -> String? {
    guard let url = webhook?.trimmingCharacters(in: .whitespacesAndNewlines), Alert.isValidWebhook(url) else { return nil }
    return url
  }

  /// 推送内容：和出厂模板一字不差就不存（nil 就是出厂模板），省得以后改了出厂模板老提醒还是旧话。
  static func clean(template: String?) -> String? {
    guard let text = Alert.blankIsNil(template), text != AlertMessage.defaultTemplate else { return nil }
    return text
  }

  /// 复盘待办到点：跟着复盘记录对一遍账（`ReviewDueAlerts.plan` 算，这儿只落账）。
  func settleReviewDue(_ plan: ReviewDueAlerts.Plan) {
    guard !plan.isEmpty else { return }
    write { archive in
      for id in plan.remove { archive[id] = nil }
      for alert in plan.upsert {
        if archive[alert.id] != nil { archive[alert.id] = alert }
        else if archive.hasRoom { archive.alerts.append(alert) }
      }
    }
  }

  func remove(id: String) { write { $0[id] = nil } }

  func remove(symbol: String, drawingID: String) {
    write { $0.alerts.removeAll { $0.symbol == InstrumentID.canonical(symbol) && $0.drawingID == drawingID } }
  }

  func setCondition(_ condition: Alert.Condition, id: String) {
    guard var alert = archive[id], alert.condition != condition else { return }
    alert.condition = condition
    write { $0[id] = alert }
  }

  /// 触发即删（2026-09-25 v3，用户：「默认就是触发一次就删除啊」）。
  ///
  /// `AlertWatcher` 把通知 / Webhook 发出去之后调这一口，把那几条已触发的从存档里删掉。
  /// 走 `write`，所以账号桥照常记账：同步推上去的是这几条的**删除**，服务端那份也跟着没了。
  /// 只删「此刻仍是已触发」的：中途被人重新布防（编辑改了价）就不动它。复盘到点不删——
  /// 它的「已到点」是给人看的，跟着复盘记录走（`ReviewDueAlerts` 到点一天后清）。
  func purgeFired(ids: Set<String>) {
    guard !ids.isEmpty else { return }
    write { archive in
      archive.alerts.removeAll { ids.contains($0.id) && $0.status == .fired && $0.kind != .reviewDue }
    }
    for id in ids where archive[id] == nil { localFires[id] = nil }
  }

  /// 响了。前台评估和服务端推下来的那条走同一个口，`once` 保证只记一次。
  /// 复盘到点那一种不看价，`price` 传 nil。
  @discardableResult
  func markFired(id: String, at time: Double, price: Double?) -> Alert? {
    markFired(ids: [id], at: time, price: price).first
  }

  /// 同一口价一起响的那一批：**一次** `write`。
  ///
  /// 一口价同时穿过几十条线（大跌那一分钟、一只品种上挂满了画线提醒）时，从前是逐条
  /// `markFired`，每一条都整份拷贝存档、整表记一次同步账、排一次 alerts.json 落盘，
  /// `@Published` 也跟着发同样多次——`AlertWatcher` 每一次都 `purgeFired` 一遍，
  /// 又是同样多次整份写。N 条一起响就是 2N 次整表记账、2N 份落盘。
  /// 现在一批只写一次，`AlertWatcher` 收到一次、报完一次删掉。
  /// 返回真的被这一次标成已触发的那几条（已经不是 active 的跳过），顺序同 `ids`。
  @discardableResult
  func markFired(ids: [String], at time: Double, price: Double?) -> [Alert] {
    guard !ids.isEmpty else { return [] }
    let wanted = Set(ids)
    var fired: [String: Alert] = [:]
    var next = archive
    for i in next.alerts.indices where wanted.contains(next.alerts[i].id) && next.alerts[i].status == .active {
      next.alerts[i].status = .fired
      next.alerts[i].firedAt = time
      next.alerts[i].firedPrice = price
      fired[next.alerts[i].id] = next.alerts[i]
    }
    guard !fired.isEmpty else { return [] }
    for id in fired.keys { localFires[id] = time }
    write { $0 = next }
    var seen = Set<String>()
    return ids.compactMap { id in seen.insert(id).inserted ? fired[id] : nil }
  }

  /// 本机自己判响的那几次（id → `firedAt`）。同步换下来的「服务端已经响过」不经
  /// `markFired`，不在这里。`AlertWatcher` 靠它决定 Webhook 由谁发：本机判响的本机发，
  /// 服务端判响的服务端已经发过了。
  private var localFires: [String: Double] = [:]

  /// 这一次「已触发」是不是本机判出来的。
  func firedLocally(_ alert: Alert) -> Bool {
    guard let at = alert.firedAt else { return false }
    return localFires[alert.id] == at
  }

  /// 跟着画线存档对一遍账。返回真表示真的动了东西。
  ///
  /// 拿上一次见过的那份画线存档（`seenDrawings`）当「删之前」：上一份里有、这一份里没有的线
  /// 是本机刚删的，提醒跟着删；说不清来历的缺线只暂停、标「画线已不存在」，不删
  /// （见 `AlertArchive.reconcile`）。
  @discardableResult
  func reconcile(with drawings: DrawArchive, now: Double = Date().timeIntervalSince1970 * 1000) -> Bool {
    let previous = seenDrawings
    seenDrawings = drawings
    var next = archive
    guard AlertArchive.reconcile(&next, with: drawings, previous: previous, now: now) else { return false }
    write { $0 = next }
    return true
  }

  /// 记下此刻的画线存档，当下一次对账的「删之前」，但不对账。宿主在画线存档换档
  /// （登录 / 换号）、云端推下来之后调它，本机第一次删线就能级联到提醒。
  func noteDrawings(_ drawings: DrawArchive) { seenDrawings = drawings }

  /// 上一次对账（或 `noteDrawings`）见过的画线存档。
  private var seenDrawings: DrawArchive?

  /// 显式级联：这几条线被删了，挂在上面的提醒一并删掉（删除照常同步上去）。
  func removeAlerts(symbol: String, drawingIDs: Set<String>) {
    guard !drawingIDs.isEmpty else { return }
    write { _ = $0.removeAlerts(symbol: symbol, drawingIDs: drawingIDs) }
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

  /// 换过几次档案（登录、退登、换号）。`AlertWatcher` 靠它分清「换进来的这份档案里
  /// 本来就躺着的已触发」（旧包留下的，不再报，直接清）和「同步刚换下来的已触发」（要报）。
  /// 在给 `archive` 赋值**之前**加一：`@Published` 在 willSet 里发，订阅方那一拍读到的是新值。
  private(set) var generation = 0

  func useStorage(_ store: AlertFileStore, archive: AlertArchive) {
    self.store = store
    generation += 1
    // 换了人，上一个人的画线存档不能再当「删之前」。
    seenDrawings = nil
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
