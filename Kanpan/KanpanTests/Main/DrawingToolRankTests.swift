import Foundation
import KanpanCore
import Testing

@testable import Kanpan

/// 画线条只露几把常用的（2026-10-05）：按次数排、同次数按面板顺序、没用过的按出厂偏好补位，
/// 这一回从面板挑的那把顶掉最后一格，总数过 256 整体减半。
@Suite @MainActor struct DrawingToolRankTests {

  @Test("没用过：竖屏四把、横屏五把，按出厂偏好的顺序")
  func defaultOrder() {
    #expect(DrawingToolRank.shown(usage: [:], count: 4) == [.trend, .hline, .fibonacci, .channel])
    #expect(DrawingToolRank.shown(usage: [:], count: 5) == [.trend, .hline, .fibonacci, .channel, .measure])
    #expect(DrawingToolRank.shown(usage: [:], count: 12).count == 12)
    #expect(Set(DrawingToolRank.defaultOrder) == Set(Drawing.Kind.palette), "补位顺序漏了面板上的工具")
  }

  @Test("按次数从多到少排，没用过的接在后面按出厂偏好补")
  func byCounts() {
    let usage = ["position": 9, "note": 5, "measure": 7]
    #expect(DrawingToolRank.shown(usage: usage, count: 4) == [.position, .measure, .note, .trend])
    #expect(DrawingToolRank.shown(usage: usage, count: 5) == [.position, .measure, .note, .trend, .hline])
  }

  @Test("次数一样按面板顺序（水平线在趋势线前面）")
  func tiesFollowPalette() {
    let usage = ["trend": 3, "hline": 3, "anchoredVWAP": 3]
    #expect(DrawingToolRank.shown(usage: usage, count: 4) == [.hline, .trend, .anchoredVWAP, .fibonacci])
  }

  @Test("认不出的键、0 和负数不算数")
  func junkIgnored() {
    let usage = ["laser": 99, "note": 0, "vline": -4]
    #expect(DrawingToolRank.shown(usage: usage, count: 4) == [.trend, .hline, .fibonacci, .channel])
  }

  @Test("手上拿着的不在前几把里，就顶掉最后一格；已经在里面就不动")
  func heldReplacesLast() {
    #expect(DrawingToolRank.shown(usage: [:], count: 4, held: .position) == [.trend, .hline, .fibonacci, .position])
    #expect(DrawingToolRank.shown(usage: [:], count: 4, held: .hline) == [.trend, .hline, .fibonacci, .channel])
    // 变体归到族首：拿着射线，摆出来的是趋势线那一格。
    #expect(DrawingToolRank.shown(usage: ["note": 4, "measure": 4, "vline": 4, "position": 4], count: 4, held: .ray)
            == [.vline, .measure, .note, .trend])
  }

  @Test("每选一次 +1；变体记在族首名下；面板外的不记")
  func counting() {
    var usage: [String: Int] = [:]
    usage = DrawingToolRank.counted(usage, .fibonacci)
    usage = DrawingToolRank.counted(usage, .fibonacci)
    usage = DrawingToolRank.counted(usage, .ray)
    #expect(usage == ["fibonacci": 2, "trend": 1])
    #expect(DrawingToolRank.counted(usage, .gannFan) == usage)
  }

  @Test("总数过 256 整体减半，减成 0 的删掉")
  func halving() {
    // 256 再加一笔 = 257，过了线：整体减半，备注 1 → 0 删掉。
    #expect(DrawingToolRank.counted(["trend": 200, "hline": 56], .note) == ["trend": 100, "hline": 28])
    let next = DrawingToolRank.counted(["trend": 255], .note)   // 256，不减
    #expect(next == ["trend": 255, "note": 1])
    // 一直点同一把：表永远不会无限涨。
    var u: [String: Int] = [:]
    for _ in 0..<5000 { u = DrawingToolRank.counted(u, .measure) }
    #expect(u.values.reduce(0, +) <= DrawingToolRank.decayCeiling)
  }

  @Test("画线一打开就把顺序定下来：这一回里点了工具也不重排，面板外挑的那把顶掉最后一格")
  func sessionIsStable() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = DrawingController(store: DrawStore(url: folder.appendingPathComponent("draws.json")))
    var usage: [String: Int] = ["note": 3]
    controller.toolUsage = { usage }
    controller.onPickTool = { usage = DrawingToolRank.counted(usage, $0) }

    controller.pick(.channel)                       // 打开画线：快照是 note 3
    #expect(usage == ["note": 3, "channel": 1])
    #expect(controller.shownTools(count: 4) == [.note, .trend, .hline, .channel],
            "这一回挑的平行通道不在前四把里，该顶掉最后一格")
    controller.pick(.trend)                         // 点条上的一把：不重排，平行通道还在
    #expect(controller.shownTools(count: 4) == [.note, .trend, .hline, .channel])
    controller.pick(.position)
    #expect(controller.shownTools(count: 4) == [.note, .trend, .hline, .position])
    #expect(controller.shownTools(count: 5) == [.note, .trend, .hline, .fibonacci, .position])

    controller.finish()
    controller.openTools()                          // 下一回：按新的次数表排
    #expect(controller.shownTools(count: 4) == [.note, .trend, .channel, .position])
  }
}
