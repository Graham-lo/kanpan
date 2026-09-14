import Foundation
import Testing
@testable import KanpanCore

@Suite("AICoin 共用布局")
struct LayoutTests {
  @Test("所有风格同尺寸；主图、时间轴、副图铺满且互不重叠")
  func sharedGeometry() {
    for (w, h) in [(402.0, 600.0), (375, 450), (874, 270), (744, 950), (320, 200)] {
      for subs in [[], [IndicatorID.macd], [.vol, .oi, .macd]] {
        let reference = Layout(width: w, height: h, subs: subs)
        for style in CandleStyle.all {
          let layout = Layout(width: w, height: h, subs: subs)
          #expect(layout == reference)
          #expect(layout.main.h > 0)
          #expect(layout.timeY == layout.mainH)
          #expect(layout.plotW > 0)
          var end = layout.mainH + AICoinBehavior.timeHeight
          for pane in layout.panes.dropFirst() {
            #expect(abs(pane.y - end) < 1e-8)
            #expect(pane.h > 0)
            end = pane.y + pane.h
          }
          #expect(abs(end - h) < 1e-8)
        }
      }
    }
  }

  @Test("主副比例与自定义副图高度不随风格改变")
  func proportionalPanes() {
    let layout = Layout(width: 402, height: 617, subs: [.vol, .oi, .macd])
    #expect(layout.mainH == 300)
    #expect(layout.panes[1].h == 100)
    #expect(layout.panes[1].y == 317)
    let custom = Layout(width: 402, height: 617, subs: [.macd, .rsi],
                        subScale: [.macd: 2, .rsi: 0.5])
    #expect(custom.panes[1].h == custom.panes[2].h * 4)
    #expect(Layout(width: 402, height: 617, subs: [.macd, .rsi],
                   subScale: [.macd: 2, .rsi: 0.5]) == custom)
  }
}

@Suite("指标元信息")
struct IndicatorMetaTests {
  @Test("10 个指标，主图三种", arguments: IndicatorID.allCases)
  func placement(_ id: IndicatorID) {
    let main: Set<IndicatorID> = [.ma, .ema, .boll]
    #expect((id.placement == .main) == main.contains(id), "\(id.rawValue) 放错地方")
    #expect(!id.name.isEmpty)
  }

  @Test("默认参数与线名对得上", arguments: IndicatorID.allCases)
  func paramsAndLines(_ id: IndicatorID) {
    let p = id.defaultParams
    #expect(p.count == id.paramLabels.count, "\(id.rawValue) 参数个数和标签数不一致")
    #expect(p.filter { $0 > 0 }.count == p.count, "\(id.rawValue) 有非正参数")
    let names = id.lineNames(params: p)
    #expect(!names.isEmpty, "\(id.rawValue) 没有线名")
    #expect(Set(names).count == names.count, "\(id.rawValue) 线名重了：\(names)")
  }

  @Test("默认参数与原型一致")
  func defaultsMatchPrototype() {
    #expect(IndicatorID.ma.defaultParams == [7, 25, 99])
    #expect(IndicatorID.ema.defaultParams == [12, 26])
    #expect(IndicatorID.boll.defaultParams == [20, 2])
    #expect(IndicatorID.vol.defaultParams == [5, 10])
    #expect(IndicatorID.macd.defaultParams == [12, 26, 9])
    #expect(IndicatorID.rsi.defaultParams == [6, 12, 24])
    #expect(IndicatorID.kdj.defaultParams == [9, 3, 3])
    #expect(IndicatorID.srsi.defaultParams == [14, 14, 3, 3])
    #expect(IndicatorID.atr.defaultParams == [14])
    // §3.2 定死：主图默认 MA，副图默认 MACD + RSI
    #expect(IndicatorID.defaultOverlays == [.ma])
    #expect(IndicatorID.defaultSubs == [.macd, .rsi])
  }

  @Test("0–100 的副图锁刻度")
  func fixedScales() {
    // 原型 `drawSub`：RSI 与 StochRSI 传 [0,100]，KDJ 传 null（J 会冲出 0–100）。
    for id in [IndicatorID.rsi, .srsi] {
      let f = id.fixedScale
      #expect(f?.lo == 0 && f?.hi == 100)
    }
    for id in [IndicatorID.kdj, .macd, .atr, .vol, .oi] {
      #expect(id.fixedScale == nil, "\(id.rawValue) 不该锁刻度")
    }
    // 参考线：原型 RSI 30/70，KDJ 与 StochRSI 20/80，别的不画。
    #expect(IndicatorID.rsi.guides == [30, 70])
    #expect(IndicatorID.kdj.guides == [20, 80], "J 会冲出 0–100，参考线只画两条")
    #expect(IndicatorID.srsi.guides == [20, 80])
    for id in [IndicatorID.macd, .atr, .vol, .oi, .ma, .ema, .boll] {
      #expect(id.guides.isEmpty, "\(id.rawValue) 不该有参考线")
    }
  }

  /// 增量重算的回算根数必须盖得住递归深度，否则末根一动尾巴就飘。
  @Test("回算根数够深", arguments: IndicatorID.allCases)
  func tailIsDeepEnough(_ id: IndicatorID) {
    let p = id.defaultParams
    let tail = id.tailBars(params: p)
    #expect(tail >= 1)
    if let m = p.max() { #expect(tail > m, "\(id.rawValue) 回算 \(tail) 根盖不住参数 \(m)") }
    // MACD 是 EMA 套 EMA，StochRSI 是 RSI 套 Stoch，都得比单层更深
    #expect(IndicatorID.macd.tailBars(params: [12, 26, 9]) >= 52)
    #expect(IndicatorID.srsi.tailBars(params: [14, 14, 3, 3]) >= 42)
  }

  @Test("线名跟着参数走")
  func lineNamesFollowParams() {
    #expect(IndicatorID.ma.lineNames(params: [5, 10]) == ["MA5", "MA10"])
    #expect(IndicatorID.ema.lineNames(params: [8]) == ["EMA8"])
    #expect(IndicatorID.vol.lineNames(params: [5, 10]) == ["MA5", "MA10"])
    #expect(IndicatorID.boll.lineNames(params: [20, 2]) == ["MID", "UP", "DN"])
    #expect(IndicatorID.kdj.lineNames(params: [9, 3, 3]) == ["K", "D", "J"])
  }

  @Test("结果取值越界给 NaN")
  func resultValuesAt() {
    let r = IndicatorResult(lines: [[1, 2, 3], [4, 5, 6]], histogram: nil)
    #expect(r.values(at: 1) == [2, 5])
    let over = r.values(at: 99), under = r.values(at: -1)
    #expect(over.filter(\.isNaN).count == 2 && under.filter(\.isNaN).count == 2)
  }
}
