import Foundation

/// 三把「计算型」画线工具的算法：锚定 VWAP、区间成交量分布、锚定成交量分布（2026-09-20）。
///
/// 和别的画线不一样的地方只有一句：**它们的形状不在锚点里，在锚点圈住的那段 K 线里。**
/// 锚点只回答「从哪一根算起 / 到哪一根为止」，剩下的要把那一段逐根扫一遍才知道画成什么样。
/// 所以算法单独放这儿：纯函数、只吃 `BarSeries`、不认识像素也不认识 UIKit，
/// `DrawGeometry` 拿它的结果去摆像素，单测可以直接打这一层。
///
/// 三把都**只用当前周期的 K 线**，不像 TradingView 那样偷偷下钻到更小的周期去取更细的量。
/// 数据层没有跨周期下钻这条路，而这三样要的是「这一段的量堆在哪儿」，当前周期的分辨率
/// 对着一屏两三百根 K 线已经够看（见实施方案 §0）。

/// 一条锚定 VWAP 的轨迹。
public struct VWAPTrail: Sendable, Equatable {
  /// 从这一根开始（`series` 下标）。
  public var start: Int
  /// 每根一个值，与 `start...` 对齐。
  ///
  /// 累计成交量还是 0 的那一段（锚点之后头几根就没有成交）是 NaN——
  /// 「还算不出来」和「算出来是 0」是两回事，画的时候跳过这几根。
  public var values: [Double]

  public init(start: Int, values: [Double]) {
    self.start = start
    self.values = values
  }

  /// 末根那个值，也就是右端读数要写的数。
  public var latest: Double? { values.last.flatMap { $0.isFinite ? $0 : nil } }
}

/// 一段区间里成交量按价格分层的结果。
///
/// 行数固定 24（TV 的默认 Number of Rows），不给用户调——行数改成多少是我的决定，
/// 不是一个要用户先理解才选得出来的选项。
public struct VolumeProfile: Sendable, Equatable {
  /// 名义行数。价格区间退化成一条水平线时只有 1 行，见 `rowCount`。
  public static let rows = 24
  /// 价值区占总量的比例（CBOT 的老规矩，TV 也是 70%）。
  static let valueArea = 0.70

  /// 区间内的 `min(low)` / `max(high)`。
  public var lo: Double, hi: Double
  /// 每行多高。`hi == lo`（整段一字线）时是 0，那时只有一行，几何层给它一个固定行高。
  public var rowHeight: Double
  /// 每行的涨量 / 跌量。口径和蜡烛颜色一致：`close >= open` 记进 `up`。
  public var up: [Double], down: [Double]
  /// 总量最大的那一行。
  var poc: Int
  /// 价值区的首末行，含两端。
  var vaLow: Int, vaHigh: Int
  /// 参与计算的 K 线下标范围，含两端。
  public var first: Int, last: Int

  public init(lo: Double, hi: Double, rowHeight: Double, up: [Double], down: [Double],
              poc: Int, vaLow: Int, vaHigh: Int, first: Int, last: Int) {
    self.lo = lo; self.hi = hi; self.rowHeight = rowHeight
    self.up = up; self.down = down
    self.poc = poc; self.vaLow = vaLow; self.vaHigh = vaHigh
    self.first = first; self.last = last
  }

  /// 真实行数：正常 24，一字线区间 1。
  public var rowCount: Int { up.count }
  func rowLow(_ r: Int) -> Double { lo + rowHeight * Double(r) }
  func rowHigh(_ r: Int) -> Double { rowHeight > 0 ? lo + rowHeight * Double(r + 1) : hi }
  /// 这一行的中价，画 POC 线和判并列时用。
  func rowMid(_ r: Int) -> Double { (rowLow(r) + rowHigh(r)) / 2 }
  func rowTotal(_ r: Int) -> Double { up[r] + down[r] }
  public var total: Double { zip(up, down).reduce(0) { $0 + $1.0 + $1.1 } }
  /// 最长那一行的量。柱子的像素宽度按它归一。
  var maxRow: Double { (0 ..< rowCount).map(rowTotal).max() ?? 0 }
  func inValueArea(_ r: Int) -> Bool { r >= vaLow && r <= vaHigh }
}

extension Drawing {
  // ------------------------------------------------------------ 时间 → 下标
  //
  // `BarSeries.index(atTime:)` 找的是**最近**那一根，两边都能跑；这里要的是
  // 「区间的左边界从哪一根算起、右边界到哪一根为止」，多含或少含一根就是多算 / 少算
  // 一整根的量，所以自己二分，口径写死成「>= 锚点」和「<= 锚点」。

  /// 第一根 `openTime >= t` 的下标。整段都早于 `t`（锚点落在末根之后）→ nil。
  static func firstBar(atOrAfter t: Double, in series: BarSeries) -> Int? {
    guard series.count > 0, Double(series.lastTime) >= t else { return nil }
    var lo = 0, hi = series.count - 1
    while lo < hi {
      let mid = (lo + hi) / 2
      if Double(series.time(at: mid)) >= t { hi = mid } else { lo = mid + 1 }
    }
    return lo
  }

  /// 最后一根 `openTime <= t` 的下标。整段都晚于 `t` → nil。
  static func lastBar(atOrBefore t: Double, in series: BarSeries) -> Int? {
    guard series.count > 0, Double(series.firstTime) <= t else { return nil }
    var lo = 0, hi = series.count - 1
    while lo < hi {
      let mid = (lo + hi + 1) / 2
      if Double(series.time(at: mid)) <= t { lo = mid } else { hi = mid - 1 }
    }
    return lo
  }

  // ------------------------------------------------------------ 锚定 VWAP

  /// 从第一根 `openTime >= anchorT` 的 K 线起，把 `Σ(hlc3·v) / Σv` 一路累到末根。
  ///
  /// 价源是 `hlc3 = (H+L+C)/3`（TV 的默认），不给 hl2 / close 的选项。
  /// 锚点落在末根之后 → nil（那一段里一根 K 线都没有，画不出东西）。
  ///
  /// 末根每个 tick 都在变，所以这是一路重算的 O(n)——n 就是锚点到现在的根数。
  /// 不做增量缓存：真慢了再加，别为一个还没量到的问题先背一个失效规则（§9）。
  static func vwapTrail(anchorT: Double, series: BarSeries) -> VWAPTrail? {
    guard let start = firstBar(atOrAfter: anchorT, in: series) else { return nil }
    var pv = 0.0, vv = 0.0
    var values: [Double] = []
    values.reserveCapacity(series.count - start)
    for i in start ..< series.count {
      let h = series.high[i], l = series.low[i], c = series.close[i], v = series.volume[i]
      // 坏根（交易所补的洞、聚合出来的空桶）跳过，不推进累计：拿一个 NaN 进去，
      // 从它往后每一根的 VWAP 都是 NaN，一条线会整段消失。
      if h.isFinite, l.isFinite, c.isFinite, v.isFinite, v >= 0 {
        pv += (h + l + c) / 3 * v
        vv += v
      }
      values.append(vv > 0 ? pv / vv : .nan)
    }
    return VWAPTrail(start: start, values: values)
  }

  // ------------------------------------------------------------ 成交量分布

  /// `[fromT, toT]` 圈住的那一段 K 线（含两端那根）按价格分层的成交量。
  ///
  /// `toT == nil` 表示「一直到末根」——锚定分布就是这么长出来的，末根一推新量柱子就跟着长。
  /// 圈不到任何一根、或者那一段里没有一根有效 K 线 → nil。
  ///
  /// 分桶口径：每根把自己的 `volume` **按价格重叠比例**摊到 `[low, high]` 盖住的每一行上，
  /// 不是整根丢进收盘价那一行。一根长影线的量本来就分布在它走过的整段价格上，
  /// 整根丢进一行会凭空堆出一个假的高峰。
  static func volumeProfile(fromT: Double, toT: Double?, series: BarSeries) -> VolumeProfile? {
    guard series.count > 0, let first = firstBar(atOrAfter: fromT, in: series) else { return nil }
    let last: Int
    if let toT {
      guard let end = lastBar(atOrBefore: toT, in: series) else { return nil }
      last = end
    } else {
      last = series.count - 1
    }
    guard first <= last else { return nil }

    // 区间的价格范围。坏根不参与——它会把 lo / hi 拉成 NaN，整张分布就废了。
    var lo = Double.infinity, hi = -Double.infinity
    for i in first ... last {
      let l = series.low[i], h = series.high[i]
      guard l.isFinite, h.isFinite, h >= l else { continue }
      lo = min(lo, l); hi = max(hi, h)
    }
    guard lo.isFinite, hi.isFinite, hi >= lo else { return nil }

    // 一字线区间（整段 high == low，停牌或极端冷门合约）退化成一行：24 行高度全是 0，
    // 摊出来是 24 个重叠的零高柱子，读不出任何东西。
    let count = hi > lo ? VolumeProfile.rows : 1
    let height = hi > lo ? (hi - lo) / Double(VolumeProfile.rows) : 0
    var up = [Double](repeating: 0, count: count)
    var down = [Double](repeating: 0, count: count)
    func rowLow(_ r: Int) -> Double { lo + height * Double(r) }
    func rowHigh(_ r: Int) -> Double { height > 0 ? lo + height * Double(r + 1) : hi }
    func row(of price: Double) -> Int {
      guard height > 0 else { return 0 }
      return min(count - 1, max(0, Int(((price - lo) / height).rounded(.down))))
    }
    for i in first ... last {
      let l = series.low[i], h = series.high[i], v = series.volume[i]
      guard l.isFinite, h.isFinite, h >= l, v.isFinite, v > 0 else { continue }
      // 涨跌跟蜡烛同一口径（`ChartRenderer` 画蜡烛也是 `close >= open` 算涨），
      // 柱子的颜色才和它底下那根对得上。
      let rising = series.close[i] >= series.open[i]
      func add(_ amount: Double, to r: Int) {
        if rising { up[r] += amount } else { down[r] += amount }
      }
      let span = h - l
      if height <= 0 || span <= 0 {
        add(v, to: row(of: l))   // 一字线的根：整根落在它自己那一行
        continue
      }
      let r0 = row(of: l), r1 = row(of: h)
      if r0 == r1 { add(v, to: r0); continue }
      for r in r0 ... r1 {
        let overlap = min(h, rowHigh(r)) - max(l, rowLow(r))
        guard overlap > 0 else { continue }
        add(v * overlap / span, to: r)
      }
    }

    // POC：量最大的那一行。并列取更靠近区间中价的那一行——并列多半出现在空区间
    // （全是 0），这时候挑中间那行比挑第 0 行诚实。
    let mid = (lo + hi) / 2
    var poc = 0
    for r in 1 ..< count {
      let total = up[r] + down[r], best = up[poc] + down[poc]
      if total > best { poc = r; continue }
      if total == best, abs((rowLow(r) + rowHigh(r)) / 2 - mid) < abs((rowLow(poc) + rowHigh(poc)) / 2 - mid) {
        poc = r
      }
    }

    // 价值区：从 POC 起向两侧扩，每步比较上方两行之和与下方两行之和，并入大的一侧，
    // 直到累计量够 70%。这是 CBOT 的老算法，TV 也是这么算的。
    let total = zip(up, down).reduce(0) { $0 + $1.0 + $1.1 }
    var vaLow = poc, vaHigh = poc
    var acc = up[poc] + down[poc]
    let target = total * VolumeProfile.valueArea
    while acc < target, vaLow > 0 || vaHigh < count - 1 {
      func sum(_ a: Int, _ b: Int) -> Double {
        [a, b].filter { $0 >= 0 && $0 < count }.reduce(0) { $0 + up[$1] + down[$1] }
      }
      let above = vaHigh < count - 1 ? sum(vaHigh + 1, vaHigh + 2) : -1
      let below = vaLow > 0 ? sum(vaLow - 1, vaLow - 2) : -1
      // 相等先并上方（含两侧都到头时的 -1 == -1，那时下面的 guard 直接收工）。
      if above >= below {
        guard vaHigh < count - 1 else { break }
        vaHigh += 1; acc += up[vaHigh] + down[vaHigh]
        if vaHigh < count - 1 { vaHigh += 1; acc += up[vaHigh] + down[vaHigh] }
      } else {
        guard vaLow > 0 else { break }
        vaLow -= 1; acc += up[vaLow] + down[vaLow]
        if vaLow > 0 { vaLow -= 1; acc += up[vaLow] + down[vaLow] }
      }
    }

    return VolumeProfile(lo: lo, hi: hi, rowHeight: height, up: up, down: down,
                         poc: poc, vaLow: vaLow, vaHigh: vaHigh, first: first, last: last)
  }
}
