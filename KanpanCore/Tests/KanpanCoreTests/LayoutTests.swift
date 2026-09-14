import Foundation
import Testing

@testable import KanpanCore

/// §5.3 布局：主图 + 0…N 个副图 + 时间轴 + 右侧价格轴。
///
/// 所有距离都从当前风格读，不许有全局常数——换风格时留白跟着变，这是 11 款
/// 风格「换的是距离不是颜色」那句话的落点。
@Suite("布局")
struct LayoutTests {
  /// 覆盖真机四个极端 + 一台平板（原型 DEVICES 的宽高）。
  static let devices: [(String, Double, Double)] = [
    ("SE3", 375, 667), ("13 mini", 375, 812), ("15", 393, 852),
    ("16 Pro", 402, 874), ("17 Pro Max", 440, 956), ("iPad mini", 744, 1133),
  ]

  @Test("面板首尾相接，不重叠不留缝", arguments: devices)
  func panesTile(_ dev: (String, Double, Double)) {
    for st in CandleStyle.all {
      for subs in [[], [IndicatorID.macd], [.macd, .rsi], [.macd, .rsi, .kdj]] {
        let L = Layout(width: dev.1, height: dev.2, style: st, subs: subs)
        #expect(L.panes.count == subs.count + 1)
        #expect(L.main.isMain && L.main.y == 0)
        for k in 1..<L.panes.count {
          #expect(L.panes[k].y == L.panes[k - 1].y + L.panes[k - 1].h,
                  "\(dev.0)/\(st.id)：第 \(k) 块没接上")
          #expect(L.panes[k].indicator == subs[k - 1])
          #expect(!L.panes[k].isMain)
        }
        #expect(L.panes.filter { $0.h > 0 }.count == L.panes.count)
      }
    }
  }

  @Test("时间轴位置与价格轴宽", arguments: devices)
  func axes(_ dev: (String, Double, Double)) {
    for st in CandleStyle.all {
      let L = Layout(width: dev.1, height: dev.2, style: st, subs: [.macd, .rsi])
      #expect(L.timeY == dev.2 - st.timeH)
      #expect(L.axisW == st.axisW, "\(st.id) 价格轴宽没跟风格走")
      #expect(L.plotW == dev.1 - st.axisW)
      #expect(L.plotW > 0 && L.plotW < dev.1)
    }
  }

  /// 副图再多也不能把主图挤没：主图有 80pt 保底，副图高有 30% 上限。
  @Test("主图保底与副图上限")
  func mainFloorAndSubCap() {
    let st = CandleStyle.default
    for n in 0...6 {
      let subs = Array(repeating: IndicatorID.macd, count: n)
      let L = Layout(width: 393, height: 852, style: st, subs: subs)
      #expect(L.mainH >= 80, "\(n) 个副图把主图挤到 \(L.mainH)")
      #expect(L.subH <= (852 - st.timeH) * 0.3 + 1e-9)
      #expect(L.subH >= 44, "副图再矮也要 44")
    }
    // 极矮的窗口（分屏、键盘弹出）也不能算出负数
    let tiny = Layout(width: 320, height: 200, style: st, subs: [.macd, .rsi])
    #expect(tiny.mainH >= 80 && tiny.subH >= 44 && tiny.plotW >= 40)
  }

  /// 极窄窗口下 plotW 有 40pt 保底，不然价格轴能把画布吃光。
  @Test("极窄窗口保底")
  func narrowWindow() {
    for w in [40.0, 60, 80, 100] {
      let L = Layout(width: w, height: 600, style: CandleStyle.default, subs: [])
      #expect(L.plotW >= 40, "宽 \(w) 时 plotW=\(L.plotW)")
    }
  }

  /// 换风格换的是距离：轴宽、时间轴高、副图高至少有一项不同。
  @Test("风格影响留白")
  func stylesChangeSpacing() {
    let sizes = CandleStyle.all.map { st -> [Double] in
      let L = Layout(width: 393, height: 852, style: st, subs: [.macd])
      return [L.plotW, L.timeY, L.subH, L.mainH]
    }
    #expect(Set(sizes.map { "\($0)" }).count > 1, "11 款风格布局完全一样，那 §6 的表没接上")
  }

  @Test("主图始终是第 0 块")
  func mainIsFirst() {
    let L = Layout(width: 393, height: 852, style: CandleStyle.default, subs: [.vol, .macd, .rsi])
    #expect(L.main == L.panes[0])
    #expect(L.panes.filter(\.isMain).count == 1)
    #expect(L.panes.dropFirst().map(\.indicator) == [.vol, .macd, .rsi])
  }
}

/// §8 指标元信息：默认参数、线名、固定刻度、增量回算根数。
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
