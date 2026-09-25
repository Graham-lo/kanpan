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

  @Test("画线一动，提醒跟着对账")
  func reconcileFollowsTheDrawings() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [hline("d1", p: 250)]
    #expect(store.reconcile(with: drawings, now: 30) == true)
    #expect(store.alert(id: alert.id)?.armedAt == 30)
    drawings["BTCUSDT"] = []
    #expect(store.reconcile(with: drawings, now: 40) == true)
    #expect(store.all.isEmpty)
  }

  @Test("没见过这条线就缺线：只暂停不删；noteDrawings 记过之后本机删线才级联")
  func missingLineIsPausedUntilSeenDeleted() {
    let store = fresh()
    let alert = store.add(drawing: hline("d1"), symbol: "BTCUSDT", now: 5)!
    // 同步先到了提醒、线还没到：这一次对账不许删。
    #expect(store.reconcile(with: DrawArchive(), now: 10) == true)
    #expect(store.alert(id: alert.id)?.status == .paused)
    // 线到了：恢复。
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [hline("d1")]
    store.noteDrawings(drawings)
    #expect(store.reconcile(with: drawings, now: 20) == true)
    #expect(store.alert(id: alert.id)?.status == .active)
    // 本机把线删了：级联删。
    #expect(store.reconcile(with: DrawArchive(), now: 30) == true)
    #expect(store.all.isEmpty)
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
