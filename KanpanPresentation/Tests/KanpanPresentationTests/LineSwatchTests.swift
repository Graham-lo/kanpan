import Testing
import KanpanCore
@testable import KanpanPresentation

/// 指标参数表的线条可选色（2026-10-08）：出厂色排第一，其余全从皮肤派生。
@Suite("指标线可选色")
struct LineSwatchTests {
  static let seeds = [Palette.sageSeed, Palette.sageNightSeed, Palette.terraSeed, Palette.terraNightSeed,
                      Palette.classicSeed, Palette.classicNightSeed]
  /// 原来那排跟皮肤无关的通用色，一支都不许再出现。
  static let generic: Set<String> = ["#E2B34F", "#4A90E2", "#A078D0", "#37A78F", "#E46A76", "#D88040", "#B8C4D8"]

  @Test("出厂色第一，其余从皮肤派生、对图区 ≥ 3:1、不重复", arguments: seeds)
  func derivedFromSkin(_ seed: PaletteSeed) {
    let fallback = Palette.chart(seed).palette[0]
    let list = Palette.lineSwatches(default: fallback, seed: seed)
    #expect(list.first == fallback)
    #expect(list.count >= 4 && list.count <= 6)
    let bg = Palette.chart(seed).bg
    for c in list.dropFirst() {
      #expect(Palette.contrast(c, bg) >= 3, "\(c) 在 \(bg) 上看不清")
      #expect(!Self.generic.contains(c.value.uppercased()))
    }
    #expect(Set(list.map { $0.value.uppercased() }).count == list.count)
  }

  @Test("角色名：第一支是 default，其余角色唯一，色值与 lineSwatches 一致", arguments: seeds)
  func rolesAreStable(_ seed: PaletteSeed) {
    let fallback = Palette.chart(seed).palette[0]
    let options = Palette.lineSwatchOptions(default: fallback, seed: seed)
    #expect(options.first?.role == "default")
    #expect(Set(options.map(\.role)).count == options.count)
    #expect(Set(options.map(\.role)).isSubset(of: ["default", "accent", "accentLift", "up", "down", "ink"]))
    #expect(options.map(\.hex) == Palette.lineSwatches(default: fallback, seed: seed))
  }

  @Test func liftKeepsHueAndBrightens() {
    let base: Hex = "#2E7D6B"
    let lifted = Palette.lift(base, 0.42)
    #expect(Palette.hueDistance(base, lifted) < 2)
    #expect(Palette.contrast(lifted, "#FFFFFF") < Palette.contrast(base, "#FFFFFF"))
    #expect(Palette.lift(base, 0) == base)
    #expect(Palette.lift("#000000", 1) == "#FFFFFF")
  }
}
