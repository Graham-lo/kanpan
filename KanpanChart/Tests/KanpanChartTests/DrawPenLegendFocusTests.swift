import CoreGraphics
import Foundation
import KanpanCore
import KanpanPresentation
import Testing
import UIKit

@testable import KanpanChart

/// 2026-10-08 视觉整改（图表与画线组）：画线一支笔、非编辑态退后、图例单行、叠加线过多淡出。
@MainActor
@Suite("画线笔·单行图例·叠加焦点")
struct DrawPenLegendFocusTests {
  static let size = CGSize(width: 402, height: 680)

  static func state(overlays: [IndicatorID], subs: [IndicatorID] = [.vol], crosshair: Crosshair? = nil) -> ChartState {
    Evidence.state(dark: false, size: size, overlays: overlays, subs: subs, crosshair: crosshair)
  }

  // ---------------------------------------------------------------- 笔

  @Test("没挑过颜色的线跟皮肤强调色，老线的显式色原样")
  func penFollowsSkin() {
    for dark in [false, true] {
      let t = Evidence.state(dark: dark, size: Self.size).colors
      var d = Drawing(kind: .trend, points: [DrawPoint(t: 0, p: 1), DrawPoint(t: 1, p: 2)])
      #expect(DrawPen.color(of: d, t) == t.accent)
      d.color = "#4A90E2"
      #expect(DrawPen.color(of: d, t) == "#4A90E2")
    }
  }

  @Test("色板五格全从皮肤来，第一格存 nil")
  func swatchesDeriveFromSkin() {
    let t = Evidence.state(dark: false, size: Self.size).colors
    let s = DrawPen.swatches(t)
    #expect(s.map(\.role) == ["skin", "light", "up", "down", "ink"])
    #expect(s[0].stored == nil && s[0].shown == t.accent)
    #expect(s[2].stored == t.up && s[3].stored == t.down && s[4].stored == t.ink)
    #expect(s[1].stored != t.accent)
    #expect(Set(s.map(\.shown)).count == 5, "五格色要彼此分得开")
  }

  @Test("跟皮肤的笔是皮肤强调色：青苔与陶土分得开，深浅两版都是；同色的格不重复摆")
  func penDiffersBySkin() {
    let pairs: [(PaletteSeed, PaletteSeed)] = [(Palette.sageSeed, Palette.terraSeed),
                                              (Palette.sageNightSeed, Palette.terraNightSeed)]
    for (a, b) in pairs {
      let ta = Palette.chart(a), tb = Palette.chart(b)
      #expect(DrawPen.color(nil, ta) == a.accent && DrawPen.color(nil, tb) == b.accent)
      #expect(DrawPen.color(nil, ta) != DrawPen.color(nil, tb))
      #expect(DrawPen.color(nil, ta) != ta.amber, "笔色不该还是金棕的 amber")
    }
    for seed in [Palette.sageSeed, Palette.sageNightSeed, Palette.terraSeed, Palette.terraNightSeed,
                 Palette.classicSeed, Palette.classicNightSeed] {
      let s = DrawPen.swatches(Palette.chart(seed)).map { $0.shown.value.uppercased() }
      #expect(Set(s).count == s.count, "\(seed.skin) 色板里有两格同色")
      #expect(s.count >= 4)
    }
  }

  @Test("非编辑态 70%，选中 100%，降低透明度时一律 100%")
  func restAlpha() {
    #expect(DrawPen.alpha(for: "a", selected: nil, reduceTransparency: false) == 0.7)
    #expect(DrawPen.alpha(for: "a", selected: "b", reduceTransparency: false) == 0.7)
    #expect(DrawPen.alpha(for: "a", selected: "a", reduceTransparency: false) == 1)
    #expect(DrawPen.alpha(for: "a", selected: nil, reduceTransparency: true) == 1)
    var r = ChartRenderer(state: Self.state(overlays: []))
    #expect(r.drawingRestAlpha == 0.7)
    r.reduceTransparency = true
    #expect(r.drawingRestAlpha == 1)
  }

  // ---------------------------------------------------------------- 单行图例

  @Test("放得下用全称，放不下换短称，再放不下收「+N」")
  func legendFit() {
    let measure = { (s: String) in Double(s.count) * 10 }
    let items = [LegendItem("MA5 100", short: "MA 100", color: "#000000"),
                 LegendItem("MA10 101", short: "101", color: "#000000"),
                 LegendItem("MA20 102", short: "102", color: "#000000"),
                 LegendItem("MA30 --", short: "--", color: "#000000")]
    let full = LegendFit.fit(items, width: 1000, measure: measure)
    #expect(full.more == 0 && full.texts.map(\.0) == ["MA5 100", "MA10 101", "MA20 102"], "读不出数的段要剔掉")
    let short = LegendFit.fit(items, width: 160, measure: measure)
    #expect(short.more == 0 && short.texts.map(\.0) == ["MA 100", "101", "102"])
    let tight = LegendFit.fit(items, width: 120, measure: measure)
    #expect(tight.texts.map(\.0) == ["MA 100"] && tight.more == 2)
    let total = tight.texts.reduce(0.0) { $0 + measure($1.0) + LegendFit.gap } + measure(LegendFit.moreText(tight.more))
    #expect(total <= 120)
  }

  @Test("主图图例恒为一行：叠加再多（自适应开着）内缩也不长高")
  func mainInsetIsOneRow() {
    var st = Self.state(overlays: [.ma, .ema, .boll, .vwap])
    st.options.adaptiveIndicators = true
    st.params[.ma] = [5, 10, 20, 30, 60, 120]
    let r = ChartRenderer(state: st)
    #expect(r.mainLegendInset(plotW: 300) == AICoinBehavior.mainTopInset)
    let items = r.mainLegendItems()
    #expect(items.count >= 10)
    let line = LegendFit.fit(items, width: 300) { Double($0.width(ChartFont.axis)) }
    #expect(line.more > 0, "放不下的尾巴收进「+N」")
    // 十字线开着也一样：读数换成那一根的，还是一行。
    var crossed = st
    crossed.crosshair = Crosshair(index: 40)
    let rc = ChartRenderer(state: crossed)
    #expect(rc.mainLegendInset(plotW: 300) == AICoinBehavior.mainTopInset)
    #expect(rc.mainLegendItems().count == items.count)
  }

  @Test("短称去参数、留读数：MA 第一段留名，后面只剩数")
  func shortForms() {
    var st = Self.state(overlays: [.ma], subs: [.macd, .vol])
    st.params[.ma] = [5, 10]
    let r = ChartRenderer(state: st)
    let main = r.mainLegendItems()
    #expect(main[0].full.hasPrefix("MA5 ") && main[0].short.hasPrefix("MA "))
    #expect(main[1].full.hasPrefix("MA10 ") && !main[1].short.contains("MA"))
    let macd = r.subLegendItems(.macd)
    #expect(macd[0].full.hasPrefix("\(IndicatorID.macd.name)(") && macd[0].short == IndicatorID.macd.name)
    let vol = r.subLegendItems(.vol)
    #expect(vol[0].full.hasPrefix("成交量 ") && vol[0].short.hasPrefix("量 "))
  }

  @Test("对比图例单行：内缩恒为一行")
  func compareInsetOneRow() {
    var st = Self.state(overlays: [])
    st.percentAxis = true
    st.compare = (0..<8).map { k in
      CompareSeries(key: "binance/usd_m/C\(k)USDT", name: "COIN\(k)", color: "#FFB400",
                    open: st.series.open.map { Optional($0) }, close: st.series.close.map { Optional($0) })
    }
    #expect(ChartRenderer(state: st).mainLegendInset(plotW: 300) == AICoinBehavior.mainTopInset)
  }

  // ---------------------------------------------------------------- 叠加焦点

  @Test("六条以内一条都不淡")
  func noFadeAtSixOrFewer() {
    var st = Self.state(overlays: [.ma])
    st.params[.ma] = [5, 10, 20, 30, 60, 120]
    let r = ChartRenderer(state: st)
    #expect(r.overlayLineKeys().count == 6)
    #expect(r.overlayFocus() == nil)
  }

  @Test("超过六条：默认前六条，改过的那把优先，十字线读的那条最优先")
  func focusOrder() throws {
    var st = Self.state(overlays: [.ma, .ema])
    st.params[.ma] = [5, 10, 20, 30, 60, 120]
    st.params[.ema] = [7, 25]
    var r = ChartRenderer(state: st)
    let keys = r.overlayLineKeys()
    #expect(keys.count == 8)
    #expect(r.overlayFocus() == Set(keys.prefix(6)))

    // 改了指数均线的参数：焦点换到它那两条。
    var edited = st
    edited.params[.ema] = [7, 30]
    r.state = edited
    #expect(r.overlayEdited == .ema)
    #expect(r.overlayFocus() == [OverlayLineKey(.ema, 0), OverlayLineKey(.ema, 1)])

    // 十字线停在主图：焦点是读数离十字线价格最近的那一条。
    let index = st.series.count - 5
    let target = try #require(r.displayed(.ma)?.lines[3][index])
    var crossed = edited
    crossed.crosshair = Crosshair(index: index, price: target)
    r.state = crossed
    #expect(r.overlayFocus() == [OverlayLineKey(.ma, 3)])

    // 十字线在副图上不算读主图的线。
    crossed.crosshair = Crosshair(index: index, price: target, pane: .vol)
    r.state = crossed
    #expect(r.overlayFocus() == [OverlayLineKey(.ema, 0), OverlayLineKey(.ema, 1)])
  }

  @Test("一次换整套布局不算编辑了某一把")
  func wholesaleLayoutIsNotAnEdit() {
    let a = Self.state(overlays: [])
    var b = a
    b.overlays = [.ma, .ema]
    #expect(ChartRenderer.editedOverlay(from: a, to: b) == nil)
    var c = a
    c.overlays = [.vwap]
    #expect(ChartRenderer.editedOverlay(from: a, to: c) == .vwap)
  }
}
