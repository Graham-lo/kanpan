import Foundation
import KanpanCore
import Testing
@testable import KanpanAlerts

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

  @Test("线被删了，提醒跟着删")
  func deletingTheLineDeletesTheAlert() {
    let drawing = line("d1", p: 100)
    var archive = AlertArchive(alerts: [alert(for: drawing)])
    var drawings = DrawArchive()
    drawings["BTCUSDT"] = []
    #expect(AlertArchive.reconcile(&archive, with: drawings, now: 9) == true)
    #expect(archive.alerts.isEmpty)
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
