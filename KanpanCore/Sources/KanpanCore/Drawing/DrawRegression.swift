import Foundation

// ============================================================ 回归通道
//
// 「回归通道」和「平行通道」看着像，来路完全不同：平行通道的三个点全是用户比划的，
// 回归通道只让用户圈起止两点，中心线是区间里那段收盘价的**最小二乘拟合**，
// 通道宽度取拟合残差的标准差。用户比划不出一条最小二乘线，也不该让他去比划。
//
// 为什么算完就存成三个点、而不是每帧现算：`drawingGeometry` 拿不到 K 线
// （它只认 `时间 → x`、`价格 → y` 两个闭包），而且它在**每一次触摸**里都要跑一遍
// （`hitDraw` 走的就是它）。把回归塞进去，等于手指每动一下就重跑一遍最小二乘；
// 换个周期、翻到没有那段数据的地方，线还会自己变形——用户画完的东西不该会动。
// 所以拟合只在落笔那一刻做一次，结果落成 a / b（中心线两端）+ c（通道宽度那一侧），
// 之后它就是一条普通的三点线，拖、存、同步全走原来那条路。

extension Drawing {
  /// 把用户圈的两点补成回归通道的三点。K 线不够（少于 3 根）就回落成一条普通趋势线。
  ///
  /// - Parameters:
  ///   - anchors: 用户点的起止两点，顺序随手，内部按时间排。
  ///   - series: 当前这张图的 K 线。只取区间内的收盘价。
  ///   - sigma: 通道半宽取几倍残差标准差。默认 2——常见的「回归通道」口径。
  public static func fittedRegression(
    from anchors: [DrawPoint], series: BarSeries, sigma: Double = 2
  ) -> [DrawPoint]? {
    guard anchors.count == 2 else { return nil }
    let lo = min(anchors[0].t, anchors[1].t), hi = max(anchors[0].t, anchors[1].t)
    guard lo.isFinite, hi.isFinite, hi > lo, series.count > 0 else { return nil }

    var xs: [Double] = [], ys: [Double] = []
    for i in 0 ..< series.count {
      let t = Double(series.time(at: i))
      guard t >= lo, t <= hi else { continue }
      let close = series.close[i]
      guard close.isFinite else { continue }
      xs.append(t); ys.append(close)
    }
    guard xs.count >= 3 else { return nil }

    // 时间戳是 1.7e12 量级，直接拿它做最小二乘，Σx² 会去到 1e24——双精度只剩几位
    // 有效数字，斜率就是噪声。所以先把横轴平移到区间中点再拟合。
    let mx = xs.reduce(0, +) / Double(xs.count)
    let my = ys.reduce(0, +) / Double(ys.count)
    var sxx = 0.0, sxy = 0.0
    for (x, y) in zip(xs, ys) { let dx = x - mx; sxx += dx * dx; sxy += dx * (y - my) }
    guard sxx > 0, sxx.isFinite, sxy.isFinite else { return nil }
    let slope = sxy / sxx
    guard slope.isFinite else { return nil }
    func fit(_ t: Double) -> Double { my + slope * (t - mx) }

    var sse = 0.0
    for (x, y) in zip(xs, ys) { let e = y - fit(x); sse += e * e }
    // 样本标准差（n-1）：n 小的时候用 n 会把通道估窄，回归通道本来就常画在几十根上。
    let sd = (sse / Double(max(1, xs.count - 1))).squareRoot()
    guard sd.isFinite else { return nil }

    let a = DrawPoint(t: lo, p: fit(lo))
    let b = DrawPoint(t: hi, p: fit(hi))
    // 第三点就是「通道边在哪儿」，和平行通道的第三点同一个含义——所以后面拖它、
    // 存它、和平行通道共用同一套几何，一行特殊代码都不用写。
    let c = DrawPoint(t: hi, p: fit(hi) + max(sd * sigma, 0))
    guard a.p.isFinite, b.p.isFinite, c.p.isFinite else { return nil }
    return [a, b, c]
  }
}
