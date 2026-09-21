import Foundation
import KanpanCore
import KanpanChart
import Testing
import UIKit
@testable import KanpanMain

@Suite(.serialized) @MainActor struct ShareTests {
  private func item() -> ShareItem {
    let line = Drawing(id: "original", kind: .hline, points: [DrawPoint(t: 1000, p: 100)])
    return ShareItem(id: "share", from: "qa_friend", symbol: "BTCUSDT", market: "binance/usd_m", interval: .h1,
                     view: ShareWindow(from: 1000, to: 2000), drawings: [line], alerted: [line.id], createdAt: "2026-09-22T00:00:00Z")
  }
  @Test func copiesOnlyReplaceIdentity() {
    let original = item(); let copied = original.copies()
    #expect(copied[0].id != original.drawings[0].id)
    var restored = copied[0]; restored.id = original.drawings[0].id
    #expect(restored == original.drawings[0]); #expect(original.preferred(in: copied) == [copied[0].id])
  }
  @Test func intervalIsRestoredOnlyWithoutUserChange() {
    var preview = SharePreviewInterval(before: .m5, shared: .h1)
    #expect(preview.restore(current: .h1) == .m5)
    #expect(preview.restore(current: .h4) == nil)
    preview.userPicked(); #expect(preview.restore(current: .h1) == nil)
  }
  @Test func keepIsOneUndoStepAndSurvivesChartReplacement() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = DrawStore(url: folder.appendingPathComponent("draws.json"))
    let own = Drawing(id: "own", kind: .hline, points: [DrawPoint(t: 1000, p: 90)])
    try file.save(DrawArchive(bySymbol: ["BTCUSDT": [own]]))
    let controller = DrawingController(store: file)
    let series = BarSeries(symbol: "BTCUSDT", interval: .h1, t0: 0, open: [100,101], high: [105,106], low: [90,91], close: [101,102], volume: [1,2])
    let state = ChartState(series: series, symbol: SymbolInfo(symbol: "BTCUSDT", base: "BTC", pricePrecision: 2, tickSize: 0.1), view: ViewWindow(to: 3_600_000, span: 3_600_000))
    let chart = ChartView(frame: CGRect(x: 0, y: 0, width: 390, height: 400)); chart.state = state
    controller.attach(chart); controller.focus("BTCUSDT")
    controller.preview(item())
    #expect(chart.guestDrawings == item().drawings); #expect(chart.ownDimmed)
    #expect(chart.drawings == [own]); #expect(try file.read()["BTCUSDT"] == [own])
    let copies = item().copies()
    #expect(controller.append(copies, symbol: "BTCUSDT"))
    controller.endPreview()
    #expect(!chart.ownDimmed && chart.guestDrawings.isEmpty)
    #expect(try file.read()["BTCUSDT"].count == 2)
    let replacement = ChartView(frame: chart.frame); replacement.state = state
    controller.attach(replacement)
    controller.undo(); #expect(controller.items == [own]); #expect(try file.read()["BTCUSDT"] == [own])
    controller.redo(); #expect(controller.items == [own] + copies)
  }
  @Test func keepReceiptAndCacheAreAccountScoped() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let inbox = ShareInbox(); let original = item()
    var cache = ShareInbox.Cache(); cache.items = [original]
    inbox.activate(directory: folder, owner: UUID(), cache: cache, api: nil)
    let first = try inbox.prepareKeep(original)
    #expect(try inbox.prepareKeep(original) == first)
    inbox.kept(original)
    #expect(inbox.unseen.isEmpty)
    let restored = try ShareInbox.read(directory: folder)
    inbox.activate(directory: folder, owner: UUID(), cache: restored, api: nil)
    #expect(try inbox.prepareKeep(original) == first)
    inbox.activate(directory: folder, owner: nil, cache: ShareInbox.Cache(), api: nil)
    #expect(inbox.items.isEmpty && inbox.friends.isEmpty)
  }
}
