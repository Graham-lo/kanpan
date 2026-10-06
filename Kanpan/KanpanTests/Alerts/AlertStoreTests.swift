import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 存档的管家：建、删、改条件、触发即删、以及「同一条线只留一条提醒」。
@Suite("提醒仓库")
@MainActor
struct AlertStoreTests {
  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  private func hline(_ id: String, p: Double = 100) -> Drawing {
    Drawing(id: id, kind: .hline, points: [DrawPoint(t: 1_000, p: p)])
  }

  @Test("加一条，图上那条线就该挂铃铛了")
  func addingAnAlertMarksTheLine() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)
    #expect(alert != nil)
    #expect(store.alertedDrawingIDs(symbol: "BTCUSDT") == ["d1"])
    #expect(alert?.status == .active)
    #expect(alert?.armedAt == 5)
    #expect(alert?.market == "binance/usd_m")
  }

  @Test("摊不出线的种类不建")
  func unsupportedKindsAreRefused() {
    let store = fresh()
    let note = Drawing(id: "n1", kind: .note, points: [DrawPoint(t: 1_000, p: 100)])
    #expect(store.add(drawing: note, symbol: "BTCUSDT") == nil)
    #expect(store.all.isEmpty)
  }

  @Test("已经走完的趋势线段不建（永远不会响）；画在过去的回撤照建，它往右延（深度审查 E-1）")
  func spentSegmentsAreRefusedPastFibIsNot() throws {
    let store = fresh()
    let now = 10 * 3_600_000.0
    let trend = Drawing(id: "t1", kind: .trend, points: [DrawPoint(t: 1_000, p: 100), DrawPoint(t: 2_000, p: 120)])
    #expect(store.add(drawing: trend, symbol: "BTCUSDT", now: now) == nil)
    #expect(store.all.isEmpty)
    // 同一条线自己开了往右延（射线）就照建。
    let ray = Drawing(id: "r1", kind: .ray, points: trend.points)
    #expect(store.add(drawing: ray, symbol: "BTCUSDT", now: now) != nil)
    var fib = Drawing(id: "f1", kind: .fibonacci, points: [DrawPoint(t: 1_000, p: 200), DrawPoint(t: 2_000, p: 100)])
    fib.levels = [0, 0.618, 1]
    let alert = try #require(store.add(drawing: fib, symbol: "BTCUSDT", now: now))
    #expect(alert.lines.allSatisfy { $0.extendRight })
    #expect(!alert.isSpent(at: now))
  }

  @Test("同一条线再点一次是「还要」，不是「再来一条」")
  func askingTwiceRearmsInsteadOfDuplicating() {
    let store = fresh()
    let first = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)
    store.markFired(id: first!.id, at: 6, price: 100)
    let again = store.add(drawing: hline("d1", p: 250), symbol: "BTCUSDT", now: 9)
    #expect(store.all.count == 1)
    #expect(again?.id == first?.id)
    #expect(again?.status == .active)
    #expect(again?.firedAt == nil)
    #expect(again?.armedAt == 9)
    #expect(again?.lines.first?.points.first?.p == 250)
  }

  @Test("触发即删：已触发的清掉并记一笔账（同步推删除），生效中的与复盘到点不动")
  func purgeFiredRemovesOnlyFiredAlerts() {
    let store = fresh()
    var booked: [[String]] = []
    store.onChange = { booked.append($0.alerts.map(\.id)) }
    let fired = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    let live = store.add(drawing: hline("d2", p: 90), symbol: "BTCUSDT", now: 5)!
    store.markFired(id: fired.id, at: 6, price: 123)
    #expect(store.visible.map(\.id) == [live.id])
    var due = KanpanCore.Alert(id: "r1", kind: .reviewDue, symbol: "BTCUSDT", armedAt: 1, dueAt: 2,
                    title: "BTC 到点了", created: 1)
    due.status = .fired; due.firedAt = 3
    store.settleReviewDue(ReviewDueAlerts.Plan(upsert: [due], remove: []))
    booked.removeAll()
    store.purgeFired(ids: [fired.id, live.id, "r1"])
    #expect(store.alert(id: fired.id) == nil)
    #expect(store.alert(id: live.id)?.status == .active)
    #expect(store.alert(id: "r1") != nil)
    #expect(!store.firedLocally(fired))
    // 删的这一笔走了 `write`：账号桥收到的是删掉之后的那一版。
    #expect(booked == [[live.id, "r1"]])
    // 复盘到点的「已到点」照样看得见。
    #expect(Set(store.visible.map(\.id)) == [live.id, "r1"])
  }

  @Test("换进来的档案要记一次代次，好让提醒的看门人分清旧档案与新同步")
  func useStorageBumpsGeneration() {
    let store = fresh()
    let before = store.generation
    store.useStorage(AlertFileStore(url: FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json")), archive: AlertArchive())
    #expect(store.generation == before + 1)
  }

  @Test("同一条只记一次触发")
  func firingTwiceOnlyCountsOnce() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    #expect(store.markFired(id: alert.id, at: 6, price: 100) != nil)
    #expect(store.markFired(id: alert.id, at: 7, price: 101) == nil)
    #expect(store.alert(id: alert.id)?.firedPrice == 100)
  }

  @Test("条件只有这一处能改")
  func theConditionIsEditable() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT")!
    #expect(alert.condition == .touch)
    store.setCondition(.close, id: alert.id)
    #expect(store.alert(id: alert.id)?.condition == .close)
  }

  @Test("改动都会喊账号桥一声")
  func everyChangeNotifiesTheBridge() {
    let store = fresh()
    var beats = 0
    store.onChange = { _ in beats += 1 }
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT")!
    store.setCondition(.close, id: alert.id)
    store.remove(id: alert.id)
    #expect(beats == 3)
    // 没真的变就不该喊。
    store.setCondition(.close, id: alert.id)
    #expect(beats == 3)
  }

  @Test("画线一动，提醒跟着对账；线删了提醒照留、照常生效（2026-10-06 画线与提醒互相独立）")
  func reconcileFollowsTheDrawings() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [hline("d1", p: 250)]
    #expect(store.reconcile(with: drawings, now: 30) == true)
    #expect(store.alert(id: alert.id)?.armedAt == 30)
    let moved = store.alert(id: alert.id)!
    drawings["BTCUSDT"] = []
    #expect(store.reconcile(with: drawings, now: 40) == false)
    #expect(store.alert(id: alert.id) == moved)
    #expect(store.alert(id: alert.id)?.status == .active)
    #expect(store.alertedDrawingIDs(symbol: "BTCUSDT") == ["d1"])
  }

  @Test("线从没见过、同步还没到：不暂停、不删；线到了也不重新上膛（几何没变）")
  func missingLineIsNeitherPausedNorDeleted() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    #expect(store.reconcile(with: DrawArchive(), now: 10) == false)
    #expect(store.alert(id: alert.id)?.status == .active)
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [hline("d1")]
    #expect(store.reconcile(with: drawings, now: 20) == false)
    #expect(store.alert(id: alert.id)?.armedAt == 5)
  }

  @Test("旧版本留下的暂停态画线提醒：换档后复活成生效中，走 write（落盘 + 记账同步）")
  func legacyPausedAlertIsRevivedAndSynced() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("alerts-\(UUID().uuidString).json")
    let file = AlertFileStore(url: url)
    var paused = Alert(symbol: "BTCUSDT", drawingID: "gone",
                       lines: AlertGeometry.lines(for: hline("gone")) ?? [],
                       armedAt: 1, title: "BTC", created: 1)
    paused.status = .paused
    try file.save(AlertArchive(alerts: [paused]))
    let store = fresh()
    var beats = 0
    store.onChange = { _ in beats += 1 }
    store.useStorage(file, archive: file.load())
    #expect(store.reviveLegacyPaused(now: 99) == true)
    #expect(store.alert(id: paused.id)?.status == .active)
    #expect(store.alert(id: paused.id)?.armedAt == 99)
    #expect(store.alert(id: paused.id)?.lines == paused.lines)
    #expect(beats == 1)
    #expect(file.load().alerts.first?.status == .active)
    #expect(store.reviveLegacyPaused(now: 100) == false)
  }

  @Test("同步换下来的、复盘到点派生的不受 200 条上限：照单全收；上限只卡本机新建")
  func syncedAndDerivedAlertsIgnoreTheLimit() {
    let store = fresh()
    var archive = AlertArchive()
    archive.alerts = (0..<(AlertArchive.limit + 5)).map { i in
      Alert(symbol: "ETHUSDT", drawingID: "s\(i)", lines: AlertGeometry.lines(for: hline("s\(i)")) ?? [],
            armedAt: 1, title: "ETH", created: 1)
    }
    store.publishSynced(archive)
    #expect(store.all.count == AlertArchive.limit + 5)
    let due = Alert(id: "rX", kind: .reviewDue, symbol: "BTCUSDT", lines: [], armedAt: 1, dueAt: 9_000,
                    reviewID: "X", title: "BTC 到点了", created: 1)
    store.settleReviewDue(ReviewDueAlerts.Plan(upsert: [due]))
    #expect(store.alert(id: "rX") != nil)
    #expect(store.all.count == AlertArchive.limit + 6)
    // 本机新建照旧卡住、说一声。
    #expect(store.add(drawing: hline("local"), symbol: "BTCUSDT") == nil)
    #expect(store.addPrice(symbol: "BTCUSDT", target: 1, current: 2, label: "1") == nil)
    #expect(store.notice != nil)
  }

  @Test("存满了就说一声，不悄悄丢")
  func aFullArchiveSaysSo() {
    let store = fresh()
    for i in 0..<AlertArchive.limit {
      store.add(drawing: hline("d\(i)", p: Double(i)), symbol: "BTCUSDT")
    }
    #expect(store.all.count == AlertArchive.limit)
    #expect(store.add(drawing: hline("overflow", p: 1), symbol: "BTCUSDT") == nil)
    #expect(store.notice != nil)
  }

  @Test("云端推下来的那一版：先落盘，再上屏")
  func syncedValuesLandInTwoSteps() throws {
    let store = fresh()
    var archive = AlertArchive()
    archive.alerts = [Alert(symbol: "ETHUSDT", drawingID: "d9",
                            lines: AlertGeometry.lines(for: hline("d9")) ?? [],
                            armedAt: 1, title: "ETH", created: 1)]
    try store.commitSynced(archive)
    #expect(store.all.isEmpty)          // 落盘那一步不动可见状态
    store.publishSynced(archive)
    #expect(store.all.count == 1)
  }
}
