import Foundation

/// 画线的**编辑**动作：落点吸附、拖动、撤销重做（M7）。
///
/// 和 `Drawing.swift` 分开是因为那份是 M1 的几何与命中（纯读），这份是改数据的那半边。
/// 三件事都写成纯值语义：给同样的输入必然给同样的输出，手势层只负责把屏幕坐标换算好
/// 丢进来——这样「吸到哪根」「拖完落在哪」「撤销回到哪一步」全都能用单测证死，
/// 不用去模拟器上点。

// MARK: - 落点吸附

/// 一次吸附的结果。
public struct DrawSnap: Sendable, Equatable {
  public var point: DrawPoint
  /// 吸到了第几根。`-1` 表示没吸（磁吸关着，或者根本没数据）。
  ///
  /// 手势层要靠它判「换根了没有」——换了才震一下，不然手指划过去一路都在响。
  public var index: Int

  public init(point: DrawPoint, index: Int) {
    self.point = point
    self.index = index
  }
}

/// 把一个自由的 (时间, 价格) 吸到最近那根 K 线上（§10.8：「点吸到最近 K 线的 OHLC」）。
///
/// 时间吸到根的 `openTime`——不是「根中心」的像素位置，而是这根在时间轴上的坐标，
/// 渲染器画竖线用的也是它（原型 `x(b.t0 + i * b.step)`）。不等距周期（1M）走
/// `series.time(at:)`，不能拿 `t0 + i * step` 算。
///
/// 价格吸到这根的开 / 高 / 低 / 收里最近的一个。原型的 `point()` 只吸时间不吸价格，
/// 任务书 A7.2 与 §10.8 都明确要求吸 OHLC，而 M4 的十字线磁吸（`nearestOHLC`）已经
/// 是这么做的了——画线跟着十字线走，同一个开关下两处行为一致。
public func snapDrawPoint(t: Double, p: Double, series: BarSeries, magnet: Bool) -> DrawSnap {
  guard magnet, series.count > 0 else { return DrawSnap(point: DrawPoint(t: t, p: p), index: -1) }
  let i = series.index(atTime: t)
  let ohlc = [series.open[i], series.high[i], series.low[i], series.close[i]]
  let snapped = ohlc.min(by: { abs($0 - p) < abs($1 - p) }) ?? p
  return DrawSnap(point: DrawPoint(t: Double(series.time(at: i)), p: snapped), index: i)
}

// MARK: - 拖动

/// 拖一条线：时间按「拖了多少毫秒」平移，价格按**像素**平移。
///
/// 价格为什么不直接加一个 `dp`：对数 / 百分比模式下等价差不等于等像素，手指往下拖
/// 100pt，低价那头该走的价差比高价那头小得多。所以调用方给的是一个
/// `priceShift`（`p ↦ pOf(yOf(p) + dy)`），这里只负责把它作用到该动的那些端点上。
/// 原型 `pointermove` 的 `shiftP` 就是这么写的。
///
/// `from` 是**按下那一刻**的那条线，不是当前值：整场拖动都拿它当基准，不逐帧累加，
/// 否则手指抖动的误差会一路攒进端点里（和 M4 手势的 `startView` 同一个道理）。
public func movedDrawing(
  _ from: Drawing, part: Drawing.Part, dt: Double, priceShift: (Double) -> Double
) -> Drawing {
  guard !from.locked else { return from }
  var d = from
  let index = part.index
  for i in d.points.indices where index == nil || index == i {
    d.points[i] = DrawPoint(t: from.points[i].t + (from.kind == .hline ? 0 : dt),
                           p: from.kind == .vline ? from.points[i].p : priceShift(from.points[i].p))
  }
  return d
}

/// 吸住之后要**离开**多远才松开（屏幕 pt）。吸上去那一步用的是 `radius`（10pt）。
///
/// 两个半径不一样大，才有「粘住」这回事：进 10pt 吸上，出 16pt 才放。
/// 一样大就是门槛线上的抖动——手指在边界上晃一个像素，吸／不吸每帧翻一次面。
public let drawSnapReleasePt: Double = 16

/// 换吸另一个 OHLC 的让步（屏幕 pt）：新的那个要比现在吸着的近过这么多才值得跳。
///
/// 没有这一让，两个点几乎等距的时候又会逐帧互抢，只是从「吸／不吸」的抖动换成
/// 「吸这个／吸那个」的抖动。
private let drawSnapHopPt: Double = 1

/// 弱磁吸：比的是**屏幕距离**，所以反转轴、对数轴下都成立。
///
/// `current` 是**上一帧吸到的那个点**，手势层每帧把上一次的结果喂回来，这一层才有迟滞
/// （真机逐帧录像里的那个抖动：斐波那契拖第二点时，锚点一帧吸在 OHLC 上、下一帧弹回手指
/// 原位，来回约 10pt，七条水平线和它们的字跟着一起抖）。
/// 从前这支函数是无状态的：每一帧独立判「离最近的 OHLC 不到 10pt 就吸，否则原样」，
/// 而手指横扫过一根根 K 线时这个距离正好绕着 10pt 上下摆，于是每帧翻一次面。
///
/// 现在分三步：
///
/// ① 先按老规矩算出这一帧的候选（手指底下那根的 OHLC，横纵都在 `radius` 之内）；
/// ② 已经吸住一个点、而且手指还没走出 `release`：只在候选明显更近（近过
///    `drawSnapHopPt`）时跳过去，否则**原封不动**把上一帧那个点还回去——
///    时间、价格、根号都不动，所以线一帧都不会抖；
/// ③ 没吸住过，或者手指已经走远：照老规矩，有候选吸候选，没有就原样落点。
///
/// 手感就是 TradingView 那种弱磁吸：贴上去就跟着那个点走，要么换到更近的一个点上，
/// 要么手指明确甩开它，中间没有第三种状态。
public func snapDrawPoint(t: Double, p: Double, series: BarSeries, magnet: Bool,
                          xOf: (Double) -> Double, yOf: (Double) -> Double, radius: Double = 10,
                          current: DrawSnap? = nil,
                          release: Double = drawSnapReleasePt) -> DrawSnap {
  let raw = DrawSnap(point: DrawPoint(t: t, p: p), index: -1)
  guard magnet, series.count > 0 else { return raw }
  let fx = xOf(t), fy = yOf(p)
  /// 某个吸附点此刻离手指多远（屏幕距离，用**当前这一帧**的换算）。
  func reach(_ snap: DrawSnap) -> Double {
    hypot(xOf(snap.point.t) - fx, yOf(snap.point.p) - fy)
  }

  var candidate: DrawSnap?
  let i = series.index(atTime: t)
  let time = Double(series.time(at: i))
  if abs(xOf(time) - fx) <= radius {
    let prices = [series.open[i], series.high[i], series.low[i], series.close[i]]
    if let near = prices.min(by: { abs(yOf($0) - fy) < abs(yOf($1) - fy) }),
       abs(yOf(near) - fy) <= radius {
      candidate = DrawSnap(point: DrawPoint(t: time, p: near), index: i)
    }
  }

  if let current, current.index >= 0 {
    let held = reach(current)
    if held <= release {
      if let candidate, reach(candidate) < held - drawSnapHopPt { return candidate }
      return current
    }
  }
  return candidate ?? raw
}

// MARK: - 撤销重做

/// 画线的撤销栈。
///
/// 存的是每次改动**之前**的整份快照，不是操作日志：画线最多 50 条、一条就几个
/// Double，整份拷下来也比记「反向操作」省心得多，而且天然不会因为某个操作忘了写
/// 逆运算而回不去。
///
/// 任务书 A7.1 的底栏只有 趋势线 / 水平线 / 删除 / 完成 四项，所以撤销重做不占底栏，
/// 放在提示条右端（见 `docs/acceptance/M7.md` 的分歧记录）。
public struct DrawHistory: Sendable, Equatable {
  /// 最多记多少步。再多没意义：画线是随手的事，不是文档编辑。
  public static let depth = 50

  public private(set) var past: [[Drawing]] = []
  public private(set) var future: [[Drawing]] = []

  public init() {}

  public var canUndo: Bool { !past.isEmpty }
  public var canRedo: Bool { !future.isEmpty }

  /// 改之前记一笔。任何新动作都会把「重做」那一摞作废——分支了就回不去了。
  public mutating func commit(before: [Drawing]) {
    past.append(before)
    if past.count > Self.depth { past.removeFirst(past.count - Self.depth) }
    future.removeAll()
  }

  /// 撤销。`current` 是现在屏幕上的那份，会被推进「重做」那摞。
  public mutating func undo(current: [Drawing]) -> [Drawing]? {
    guard let prev = past.popLast() else { return nil }
    future.append(current)
    return prev
  }

  public mutating func redo(current: [Drawing]) -> [Drawing]? {
    guard let next = future.popLast() else { return nil }
    past.append(current)
    return next
  }

  /// 切品种 / 切周期时清掉：两个品种的线互不相干，撤销串台会很吓人。
  public mutating func clear() {
    past.removeAll()
    future.removeAll()
  }
}
