import CoreGraphics
import Testing
@testable import Kanpan

/// 落图记录整段滑出视野后，图上不许再留它的结论字、热区和到期线（这一轮审查自查）。
@MainActor
struct ReviewOverlayOffscreenTests {
  let plotW: CGFloat = 360
  let mainH: CGFloat = 400

  @Test func rangeLeftOfViewHasNoHotspot() {
    // 几天前的一条：起止都在图左边外面。原来这里给出左下角一块 50pt 的热区。
    #expect(RangeOverlayView.hotspot(start: -900, end: -400, plotW: plotW, mainH: mainH) == nil)
    #expect(!RangeOverlayView.rangeVisible(start: -900, end: -400, plotW: plotW))
    // 整段在右边外面也没有。
    #expect(RangeOverlayView.hotspot(start: 400, end: 500, plotW: plotW, mainH: mainH) == nil)
  }

  @Test func partlyVisibleRangeKeepsItsHotspotAtTheLeftEdge() throws {
    // 起点滑出左边、终点还在图里：标签与热区贴着左缘，照旧可点。
    let spot = try #require(RangeOverlayView.hotspot(start: -100, end: 30, plotW: plotW, mainH: mainH))
    #expect(spot.minX == 0)
    #expect(spot.maxY == mainH)
    #expect(spot.width >= 44)
    #expect(RangeOverlayView.rangeVisible(start: -100, end: 30, plotW: plotW))
    // 整段在图里：从起点左边 6pt 起，宽度夹在 44–96 之间再加两边各 6。
    let inside = try #require(RangeOverlayView.hotspot(start: 100, end: 300, plotW: plotW, mainH: mainH))
    #expect(inside.minX == 94)
    #expect(inside.width == 108)
  }

  @Test func expiryLineOnlyClampsWhileEditing() {
    // 取景时钉在图里，手柄够得着。
    #expect(RangeOverlayView.expiryX(-50, plotW: plotW, editing: true) == 18)
    #expect(RangeOverlayView.expiryX(900, plotW: plotW, editing: true) == plotW - 18)
    // 已落图的记录：视野外不画，视野里照实画（不再挪到 18）。
    #expect(RangeOverlayView.expiryX(-50, plotW: plotW, editing: false) == nil)
    #expect(RangeOverlayView.expiryX(900, plotW: plotW, editing: false) == nil)
    #expect(RangeOverlayView.expiryX(5, plotW: plotW, editing: false) == 5)
  }
}
