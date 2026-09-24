import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 小组件快照在 App Group 里那份文件的读写（`Kanpan/KanpanShared/WidgetSnapshotFile.swift`）。
///
/// 「写下去再读回来一字不差」原在 `KanpanCoreTests/WidgetSnapshotTests`；审查 24 把快照的
/// 文件 IO 请出 Core 之后搬到这里，用例名与断言不变。快照本身的挑行、补价用例仍在 Core。
@Suite struct WidgetSnapshotFileTests {
  private func colors() -> WidgetSnapshot.Colors {
    WidgetSnapshot.Colors(ground: "#FFFFFF", ink: "#000000", ink2: "#333333", ink3: "#666666",
                          line: "#EEEEEE", accent: "#00AA00", up: "#00AA00", down: "#DD0000")
  }

  private func snapshot(rolling: Bool = true) -> WidgetSnapshot {
    let q = { (s: String, p: Double, c: Double) in
      WidgetSnapshot.Quote(symbol: s, price: p, change: c, decimals: 2, closes: [1, 2, 3], timeMs: 1_000, open: p / (1 + c / 100))
    }
    return WidgetSnapshot(updatedAt: 1_000, favorites: ["BTCUSDT", "ETHUSDT", "SOLUSDT", "DOGEUSDT", "XRPUSDT"],
                          groups: [.init(id: "g1", name: "主流", symbols: ["ETHUSDT", "BTCUSDT"])],
                          quotes: ["BTCUSDT": q("BTCUSDT", 100, 1), "ETHUSDT": q("ETHUSDT", 50, -2),
                                   "SOLUSDT": q("SOLUSDT", 10, 0)],
                          light: colors(), dark: colors(), appearance: .auto, rolling: rolling)
  }

  @Test("写下去再读回来一字不差")
  func roundTrip() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let s = snapshot()
    try s.write(to: WidgetSnapshot.url(in: dir))
    #expect(WidgetSnapshot.read(from: WidgetSnapshot.url(in: dir)) == s)
  }
}
