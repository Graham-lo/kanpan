import Testing

@testable import KanpanCore

/// A1.3：根宽表必须和原型 `candleWidths` 完全相同，并满足奇偶、包含关系等不变量。
@Suite("根宽与像素对齐")
struct GeometryTests {
  @Test("当前参考手机：4pt 节距对应8px实体、2px影线")
  func referenceWidth() {
    let w = candlePixels(spacing: 4, scale: 3)
    #expect(w.body == 8 && w.wick == 2)
  }

  @Test("snap 落在设备像素边界", arguments: [1.0, 2.0, 3.0])
  func snapping(_ scale: Double) {
    var r = Rng(UInt64(scale * 100))
    for _ in 0..<2000 {
      let x = r.d(-500, 1500)
      let s = snap(x, scale: scale)
      #expect(abs(s * scale - (s * scale).rounded()) < 1e-9, "snap(\(x)) = \(s) 没对齐")
      #expect(abs(s - x) <= 0.5 / scale + 1e-9, "snap 挪太远")
      let h = hairline(x, scale: scale)
      #expect(abs((h * scale - 0.5) - (h * scale - 0.5).rounded()) < 1e-9, "hairline(\(x)) = \(h) 不在半像素上")
    }
  }

  /// 挤到 1.3 pt 以内只画影线；宽到 20 pt 一定是胖实体。
  @Test("thin 判定")
  func thinFlag() {
    #expect(candleMetrics(spacing: 1.0, scale: 2).thin, "aicoin 挤成这样还画实体")
    #expect(!candleMetrics(spacing: 20, scale: 2).thin, "aicoin 拉开了还不画实体")
  }

  /// 影线粗细取**整数个设备像素**：`max(1, round(max(0.5, (4.0 / 3)) * scale / 2))`，再除以 scale。
  ///
  /// 旧口径是 `max(0.5, (4.0 / 3)) / scale`，直接把风格表里的点值当逻辑宽度用。那样画出来
  /// 的竖线落在非整像素上，CoreGraphics 会把它摊到相邻两列、各给一半覆盖率——肉眼就是
  /// 「颜色变淡、影线糊在一起」。0.5 pt 的风格（靛/砖/骨/密）在 1x 下更是只有半像素，
  /// 等于画了一条 50% 灰。所以改成先量成整数设备像素再换回逻辑宽度。
  @Test("影线粗细换算")
  func wickWidth() {
    // 风格表的 `wick` 是**按 2x 屏写的设备像素**，先换算到当前倍率再量成整数。
    #expect(
      wickPixels(scale: 2) == max(1, Int(max(0.5, (4.0 / 3)).jsRounded())),
      "aicoin 影线像素数（2x 就是风格表原值）")
    for scale in [1.0, 2.0, 3.0] {
      let px = wickPixels(scale: scale)
      #expect(
        px == max(1, Int((max(0.5, (4.0 / 3)) * max(1, scale) / 2).jsRounded())),
        "aicoin@\(scale) 影线像素数")
      #expect(wickLineWidth(scale: scale) == Double(px) / scale, "aicoin@\(scale)")
      #expect(abs(wickLineWidth(scale: scale) * scale - Double(px)) < 1e-9)
      let m = candleMetrics(spacing: 8, scale: scale)
      let wickW = Double(px) / scale
      #expect(m.wickW == wickW, "aicoin@\(scale) wickW")
      #expect(m.minBody == 1 / scale, "aicoin@\(scale) minBody")
      #expect(m.outline == 1 / scale, "aicoin@\(scale) 描边线宽")
      #expect(m.bodyW > 0 && m.wickW > 0)
    }
  }
}

/// M6：蜡烛按整设备像素光栅化。
///
/// 起因是实机反馈「缩小后 K 线糊成一片、影线颜色发淡挤在一起」。根因有两条：影线宽度
/// 是 `max(0.5, (4.0 / 3)) / scale` 这样的小数，落笔压不满整像素，抗锯齿把它摊成半灰；
/// 实体宽没有「至少留 1 像素缝」的上限，捏小之后相邻两根直接连成一片（砖在默认根间距
/// 下实测缝是 **-1**，也就是重叠）。
///
/// 这个套件钉的是修完之后的物理保证，不是某几个具体数字。
@Suite("蜡烛整像素光栅化")
struct CandlePixelTests {
  static let scales: [Double] = [1, 2, 3]
  /// 在售 iOS 设备只有 2x 和 3x。1x 留在上面那几条不变量里跑（算法不能崩），但
  /// 「默认根间距下要有胖实体」这种观感要求只对真机倍率提——密 2.6pt / 骨 3.4pt
  /// 在 1x 下一格才 2–3 个像素，本来就只画得出一根线，旧代码也是（只是 thin 标志没置上）。
  static let deviceScales: [Double] = [2, 3]

  /// 影线永远是整数个设备像素，而且同一档风格的**物理宽度**跨屏一致。
  ///
  /// 跨屏一致的是「多宽」而不是「多少个像素」：`wick` 按 2x 屏写，所以目标物理宽度是
  /// `wick / 2` 点，屏幕越精细就该用越多个像素去铺它。从前这儿钉的是「像素数不许跟着
  /// scale 变」，等于让 3x 上的影线比 2x 细三分之一——墩在 3x 只有 0.667pt，而 AiCoin
  /// 实测是 1.0pt（见 docs/acceptance/M8/aicoin-对比.md §2.3），这正是实机反馈
  /// 「影线模糊、挤在一起」的一半原因。
  @Test("影线整像素", arguments: scales)
  func wickIsWholePixels(_ scale: Double) {
    let px = wickPixels(scale: scale)
    #expect(px >= 1, "aicoin 影线归零")
    let w = wickLineWidth(scale: scale)
    #expect(abs(w * scale - (w * scale).rounded()) < 1e-9, "aicoin@\(scale) 落不到整像素上")
    // 量化误差不超过半个设备像素；`px == 1` 是保底那一档（目标不足半像素时抬上来）。
    let want = max(0.5, (4.0 / 3)) / 2
    #expect(px == 1 || abs(w - want) <= 0.5 / scale + 1e-9, "aicoin@\(scale) 物理宽度跑了：\(w) vs \(want)")
  }

  /// 实体和影线奇偶相同 —— 这是 `evenUp` 的设计意图，以前渲染器只取 `body`、
  /// 影线另走一条路，奇偶从来没真的对上过。
  @Test("实体与影线奇偶相同", arguments: scales)
  func parity(_ scale: Double) {
    var sp = Chart.minBarSpacing
    while sp <= Chart.maxBarSpacing {
      let w = candlePixels(spacing: sp, scale: scale)
      #expect(w.body % 2 == w.wick % 2, "aicoin@\(scale) spacing=\(sp) 奇偶不同 \(w)")
      #expect(w.body >= w.wick, "aicoin@\(scale) spacing=\(sp) 实体比影线细")
      sp += 0.05
    }
  }

  /// 相邻两根之间至少留 1 个设备像素的缝——**实体和影线都算**。
  ///
  /// 退化成 `thin`（一格里放不下比影线更宽的实体）时画的是影线，那就轮到影线让缝：
  /// 从前只有实体受 `cell - 1` 约束，影线直接用风格量化值，于是捏小之后影线自己把一格
  /// 占满（墩在 3x 上影线 3 像素、一格只剩 3 像素时缝是 0），一排影线糊成一堵墙。
  /// 一格只有 1 个像素时谁也让不出来，那是密度上限，不在要求之列。
  @Test("实体之间至少 1 像素缝", arguments: scales)
  func gapAtLeastOnePixel(_ scale: Double) {
    var sp = Chart.minBarSpacing
    while sp <= Chart.maxBarSpacing {
      let w = candlePixels(spacing: sp, scale: scale)
      let cell = Int((sp * scale).rounded(.down))
      let ink = candleMetrics(spacing: sp, scale: scale).thin ? w.wick : w.body
      if cell >= 2 {
        #expect(cell - ink >= 1, "aicoin@\(scale) spacing=\(sp) 缝只剩 \(cell - ink)")
      }
      sp += 0.05
    }
  }

  /// 放大不能把蜡烛画细：实体宽随根间距单调不减。
  @Test("实体宽单调", arguments: scales)
  func monotonic(_ scale: Double) {
    var prev = -1
    var sp = Chart.minBarSpacing
    while sp <= Chart.maxBarSpacing {
      let b = candlePixels(spacing: sp, scale: scale).body
      #expect(b >= prev, "aicoin@\(scale) spacing=\(sp) 变细了 \(prev)→\(b)")
      prev = b
      sp += 0.05
    }
  }

  /// `thin` 是物理判据（一格里放不下比影线宽的实体），不是写死的 `spacing < 1.3`——
  /// 后者跟屏幕倍率和风格都无关，2x 和 3x 该退化的点根本不一样。
  @Test("thin 是物理判据", arguments: deviceScales)
  func thinIsPhysical(_ scale: Double) {
    // 挤到一格只剩 3 像素：不管什么风格都该退成一根线。
    let tight = 3.0 / scale
    #expect(candleMetrics(spacing: tight, scale: scale).thin,
            "aicoin@\(scale) 一格 3 像素还画实体")
    // 默认根间距下一根都不许退化，否则默认视图就没实体了。
    #expect(!candleMetrics(spacing: AICoinBehavior.initialSpacing, scale: scale).thin,
            "aicoin@\(scale) 默认根间距就退化了")
  }

  /// 默认根间距下实体一定比影线明显宽（不是「刚好差一点」），否则默认视图看不出涨跌。
  @Test("默认根间距下实体够胖", arguments: deviceScales)
  func defaultSpacingIsFat(_ scale: Double) {
    let w = candlePixels(spacing: AICoinBehavior.initialSpacing, scale: scale)
    let cell = Int((AICoinBehavior.initialSpacing * scale).rounded(.down))
    #expect(w.body > w.wick, "aicoin@\(scale) 默认档实体没比影线宽")
    #expect(cell - w.body >= 1, "aicoin@\(scale) 默认档没缝")
  }

  /// 非法输入（NaN / 0 / 负数）不能算出负宽或零宽。
  @Test("非法输入兜底")
  func garbageIn() {
    for sp in [0.0, -5, Double.nan, .infinity] {
      let w = candlePixels(spacing: sp, scale: 2)
      #expect(w.body >= 1 && w.wick >= 1, "spacing=\(sp) 算出 \(w)")
    }
    for sc in [0.0, -2, Double.nan] {
      let w = candlePixels(spacing: 8, scale: sc)
      #expect(w.body >= 1 && w.wick >= 1, "scale=\(sc) 算出 \(w)")
    }
  }
}
