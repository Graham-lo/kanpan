import Testing

@testable import KanpanCore

/// A1.10：颜色值本身的运算。
///
/// 原来这儿逐字段比对的是原型带来的十一款风格（`Fx.styles`）。2026-09-15 风格表收成
/// AICoin 一套、2026-09-24 连风格字段一起删掉（见 `CandleStyle`），那一批对照就没有对象了；
/// 配色接线那几条随 `Palette` 一起搬进了 KanpanPresentation（`PaletteWiringTests`，审查 24），
/// 这里只剩 Core 自己的 `Hex` 混色。
@Suite("颜色值")
struct StyleTableTests {
  /// `mixHex` 两端与中点。原型用 JS `toString(16)`，出来是小写。
  @Test("mixHex")
  func mix() {
    #expect(mixHex("#000000", "#FFFFFF", 0).value == "#000000")
    #expect(mixHex("#000000", "#FFFFFF", 1).value == "#ffffff")
    #expect(mixHex("#000000", "#FFFFFF", 0.5).value == "#808080")
    #expect(mixHex("#DE2E57", "#0E9E78", 0).value == "#de2e57")
    #expect(mixHex("#DE2E57", "#0E9E78", 1).value == "#0e9e78")
    // 半透明色混色只看前三个通道，和原型 slice(1, 7) 一致。
    #expect(mixHex("#DE2E5780", "#0E9E7840", 0).value == "#de2e57")
  }
}
