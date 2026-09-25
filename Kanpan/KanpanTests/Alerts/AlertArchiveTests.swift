import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 存档与对账：画线一动，提醒跟着怎么走（方案第 10 节「画线前台提醒的三条规则」）。
@Suite("提醒存档")
struct AlertArchiveTests {
  private func line(_ id: String, p: Double) -> Drawing {
    Drawing(id: id, kind: .hline, points: [DrawPoint(t: 1_000, p: p)])
  }

  private func alert(for drawing: Drawing, symbol: String = "BTCUSDT", armedAt: Double = 1) -> Alert {
    Alert(symbol: symbol, drawingID: drawing.id,
          lines: AlertGeometry.lines(for: drawing) ?? [],
          armedAt: armedAt,
          title: Alert.title(symbol: symbol, drawingKind: drawing.kind),
          created: armedAt)
  }

  @Test("线在本机被删了（上一份存档里还在），提醒跟着删")
  func deletingTheLineDeletesTheAlert() {
    let drawing = line("d1", p: 100)
    var archive = AlertArchive(alerts: [alert(for: drawing)])
    var before = DrawArchive()
    before["BTCUSDT"] = [drawing]
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = []
    #expect(AlertArchive.reconcile(&archive, with: drawings, previous: before, now: 9) == true)
    #expect(archive.alerts.isEmpty)
  }

  @Test("线找不到、又说不清是被删的（同步还没到 / 老版本认不出）：提醒留着，暂停并标「画线已不存在」")
  func missingLineKeepsTheAlertPaused() {
    let drawing = line("d1", p: 100)
    let original = alert(for: drawing)
    var archive = AlertArchive(alerts: [original])
    let drawings = DrawArchive()
    #expect(AlertArchive.reconcile(&archive, with: drawings, now: 9) == true)
    #expect(archive.alerts.count == 1)
    #expect(archive.alerts[0].id == original.id)
    #expect(archive.alerts[0].status == .paused)
    #expect(AlertArchive.isDrawingMissing(archive.alerts[0]))
    #expect(AlertArchive.drawingMissingNote == "画线已不存在")
    #expect(AlertRecordText.meta(archive.alerts[0], zone: .fixed(0), decimals: 1, conditionInline: true)
            == "画线已不存在 · 价格达到")
    // 上一份里也没有这条线：同样不删。
    #expect(AlertArchive.reconcile(&archive, with: drawings, previous: DrawArchive(), now: 10) == false)
    #expect(archive.alerts.count == 1)
  }

  @Test("线回来了：暂停的那条恢复生效，并从现在起算")
  func returningLineReactivatesTheAlert() {
    let drawing = line("d1", p: 100)
    var archive = AlertArchive(alerts: [alert(for: drawing)])
    _ = AlertArchive.reconcile(&archive, with: DrawArchive(), now: 9)
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [drawing]
    #expect(AlertArchive.reconcile(&archive, with: drawings, now: 20_000) == true)
    #expect(archive.alerts[0].status == .active)
    #expect(archive.alerts[0].armedAt == 20_000)
    #expect(!AlertArchive.isDrawingMissing(archive.alerts[0]))
  }

  @Test("显式级联删除：只删挂在这几条线上的画线提醒")
  func cascadeRemovesOnlyThoseLines() {
    let a = alert(for: line("d1", p: 100))
    let b = alert(for: line("d2", p: 200))
    let c = alert(for: line("d1", p: 100), symbol: "ETHUSDT")
    var archive = AlertArchive(alerts: [a, b, c])
    #expect(archive.removeAlerts(symbol: "BTCUSDT", drawingIDs: ["d1"]) == 1)
    #expect(archive.alerts.map(\.id) == [b.id, c.id])
  }

  @Test("线被挪了，按同一个 id 重算并重新上膛")
  func movingTheLineRearmsTheSameAlert() {
    let drawing = line("d1", p: 100)
    let original = alert(for: drawing)
    var archive = AlertArchive(alerts: [original])
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [line("d1", p: 250)]
    #expect(AlertArchive.reconcile(&archive, with: drawings, now: 9_000) == true)
    #expect(archive.alerts.count == 1)
    #expect(archive.alerts[0].id == original.id)          // 同一条提醒，不是新的
    #expect(archive.alerts[0].lines.first?.points.first?.p == 250)
    #expect(archive.alerts[0].armedAt == 9_000)           // 刚挪过去不该被历史 K 线判成已触发
  }

  @Test("只改颜色不动提醒")
  func restylingTheLineLeavesTheAlertAlone() {
    let drawing = line("d1", p: 100)
    var archive = AlertArchive(alerts: [alert(for: drawing)])
    var moved = drawing
    moved.color = "#FF0000"
    moved.locked = true
    moved.hidden = true
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = [moved]
    #expect(AlertArchive.reconcile(&archive, with: drawings, now: 9_000) == false)
    #expect(archive.alerts[0].armedAt == 1)
  }

  @Test("挂着提醒的线才画铃铛，已触发的不画")
  func firedAlertsDropTheBell() {
    let a = alert(for: line("d1", p: 100))
    var b = alert(for: line("d2", p: 200))
    b.status = .fired
    let archive = AlertArchive(alerts: [a, b])
    #expect(archive.alertedDrawingIDs(symbol: "BTCUSDT") == ["d1"])
  }

  @Test("等着的排前面")
  func activeAlertsSortFirst() {
    var fired = alert(for: line("d1", p: 100), armedAt: 5_000)
    fired.status = .fired
    let waiting = alert(for: line("d2", p: 200), armedAt: 1_000)
    let archive = AlertArchive(alerts: [fired, waiting])
    #expect(archive.sorted.map(\.drawingID) == ["d2", "d1"])
  }

  @Test("存档读回来还是那一份")
  func theArchiveRoundTrips() throws {
    let archive = AlertArchive(alerts: [alert(for: line("d1", p: 100))])
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json")
    let store = AlertFileStore(url: url)
    try store.save(archive)
    #expect(try store.read() == archive)
    try? FileManager.default.removeItem(at: url)
  }

  @Test("读不动就当空档，不抛")
  func abrokenFileReadsAsEmpty() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-\(UUID().uuidString).json")
    try Data("not json".utf8).write(to: url)
    #expect(AlertFileStore(url: url).load().alerts.isEmpty)
    try? FileManager.default.removeItem(at: url)
  }
}
