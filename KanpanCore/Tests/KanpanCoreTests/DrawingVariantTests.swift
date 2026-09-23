import Foundation
import Testing

@testable import KanpanCore

/// 「趋势线换成两端延伸之后，再画还是线段」（用户 2026-09-23 报的）。
///
/// 样式表里换画法是用户的主动选择：换一次就记在这一族名下，之后面板上点那一格，
/// 落下来的就是上次选的那一种，直到他再换。这里证模型层：记不记得住、新线用不用、
/// 存档与云端那份缺键时读不读得回来。
@Suite("画线：每一族记住上次选的画法")
struct DrawingVariantTests {
  private let two = [DrawPoint(t: 1_000, p: 10), DrawPoint(t: 2_000, p: 12)]
  private let one = [DrawPoint(t: 1_000, p: 10)]

  @Test("三族在面板上各有一格，族里每一种都认得回那一格")
  func everyFamilyHasOnePaletteHead() {
    let families: [Drawing.Kind: [Drawing.Kind]] = [
      .trend: [.trend, .ray, .extended, .arrowLine],
      .hline: [.hline, .hray],
      .vline: [.vline, .crossLine],
    ]
    for (head, members) in families {
      #expect(Drawing.Kind.palette.contains(head))
      for kind in members { #expect(kind.paletteHead == head, "\(kind.rawValue) 该归 \(head.rawValue)") }
    }
    // 不在任何一族里的工具没有记忆可言。
    for kind in [Drawing.Kind.channel, .fibonacci, .measure, .note, .position] { #expect(kind.paletteHead == nil) }
  }

  @Test("换成两端延伸之后，面板点趋势线落下来的是两端延伸")
  func swapIsRememberedAndUsedByTheNextLine() {
    var prefs = DrawingPreferences()
    #expect(prefs.newDrawing(tool: .trend, points: two).kind == .trend, "没换过就还是线段")
    let swapped1 = prefs.rememberSwap(from: .trend, to: .extended)
    #expect(swapped1)
    #expect(prefs.variants == ["trend": .extended])
    let next = prefs.newDrawing(tool: .trend, points: two)
    #expect(next.kind == .extended)
    #expect(next.isValid)
    // 再换一次（在两端延伸那条上换成向右延伸）就换成新的；换回线段也算一次选择。
    let swapped2 = prefs.rememberSwap(from: .extended, to: .ray)
    #expect(swapped2)
    #expect(prefs.newDrawing(tool: .trend, points: two).kind == .ray)
    let swapped3 = prefs.rememberSwap(from: .ray, to: .trend)
    #expect(swapped3)
    #expect(prefs.newDrawing(tool: .trend, points: two).kind == .trend)
    // 同一个值再记一遍不算改动（省一次落盘和一次同步）。
    let swapped4 = prefs.rememberSwap(from: .ray, to: .trend)
    #expect(!swapped4)
  }

  @Test("三族互不相干")
  func familiesAreIndependent() {
    var prefs = DrawingPreferences()
    prefs.rememberSwap(from: .hline, to: .hray)
    prefs.rememberSwap(from: .vline, to: .crossLine)
    #expect(prefs.newDrawing(tool: .hline, points: one).kind == .hray)
    #expect(prefs.newDrawing(tool: .vline, points: one).kind == .crossLine)
    #expect(prefs.newDrawing(tool: .trend, points: two).kind == .trend)
    #expect(prefs.newDrawing(tool: .channel, points: two + one).kind == .channel)
  }

  @Test("跨族的换法不记，坏值不用")
  func crossFamilyAndBadValuesAreIgnored() {
    var prefs = DrawingPreferences()
    let swapped5 = prefs.rememberSwap(from: .trend, to: .hray)
    #expect(!swapped5)
    let swapped6 = prefs.rememberSwap(from: .fibonacci, to: .fibExtension)
    #expect(!swapped6)
    #expect(prefs.variants.isEmpty)
    // 存档或云端里出现一个不在这一族的值：点数可能对不上，宁可退回面板那一把。
    prefs.variants = ["trend": .hray, "hline": .extended]
    #expect(prefs.kind(for: .trend) == .trend)
    #expect(prefs.kind(for: .hline) == .hline)
    // 只认面板那一格作为键：拿族里的别的成员来问，不做二次换算。
    prefs.variants = ["trend": .extended]
    #expect(prefs.kind(for: .ray) == .ray)
  }

  @Test("样式各存各的：换过的那种有自己的就用自己的，没有就沿用面板那一格的")
  func styleFollowsTheExistingRules() {
    var prefs = DrawingPreferences()
    var red = Drawing(kind: .trend, points: two); red.color = Hex("#FF0000"); red.lineWidth = 3
    prefs.styles["trend"] = DrawingStyle(red)
    prefs.rememberSwap(from: .trend, to: .extended)
    var next = prefs.newDrawing(tool: .trend, points: two)
    #expect(next.kind == .extended)
    #expect(next.color == Hex("#FF0000"))
    #expect(next.lineWidth == 3)

    var blue = Drawing(kind: .extended, points: two); blue.color = Hex("#0000FF")
    prefs.styles["extended"] = DrawingStyle(blue)
    next = prefs.newDrawing(tool: .trend, points: two)
    #expect(next.color == Hex("#0000FF"))
    #expect(prefs.styles["trend"]?.color == Hex("#FF0000"), "两份样式互不覆盖")
  }

  @Test("存档往返；老存档与云端缺 variants 键照常读；认不出的画法丢掉不整份抛")
  func codableToleratesMissingAndUnknown() throws {
    var prefs = DrawingPreferences()
    prefs.rememberSwap(from: .trend, to: .extended)
    prefs.rememberSwap(from: .hline, to: .hray)
    let data = try JSONEncoder().encode(prefs)
    #expect(try JSONDecoder().decode(DrawingPreferences.self, from: data) == prefs)

    // 这一版之前落的存档：没有 variants 这个键。
    let old = #"{"favorites":["trend"],"magnet":false,"continuous":true,"styles":{}}"#
    let legacy = try JSONDecoder().decode(DrawingPreferences.self, from: Data(old.utf8))
    #expect(legacy.variants.isEmpty)
    #expect(legacy.magnet == false)
    #expect(legacy.kind(for: .trend) == .trend)

    // 以后的版本多了一种画法、这台还不认识：那一条丢掉，别的照读，整份不抛。
    let future = #"{"variants":{"trend":"curvedTrend","vline":"crossLine"}}"#
    let newer = try JSONDecoder().decode(DrawingPreferences.self, from: Data(future.utf8))
    #expect(newer.variants == ["vline": .crossLine])

    // 整份画线存档（`draws.json`）里的偏好也一样。
    var archive = DrawArchive()
    archive.preferences = prefs
    let round = try JSONDecoder().decode(DrawArchive.self, from: try JSONEncoder().encode(archive))
    #expect(round.preferences.variants == ["trend": .extended, "hline": .hray])
  }
}
