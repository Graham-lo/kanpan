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
  var d = from
  switch part {
  case .a:
    d.a = DrawPoint(t: from.a.t + dt, p: priceShift(from.a.p))
  case .b:
    if let b = from.b { d.b = DrawPoint(t: b.t + dt, p: priceShift(b.p)) }
  case .body:
    if from.kind == .hline {
      // 水平线横跨整宽，横着拖它没有任何视觉效果，却会把端点时间拖到视野外——
      // 原型在这儿也只改价格不改时间。
      d.a = DrawPoint(t: from.a.t, p: priceShift(from.a.p))
    } else {
      d.a = DrawPoint(t: from.a.t + dt, p: priceShift(from.a.p))
      if let b = from.b { d.b = DrawPoint(t: b.t + dt, p: priceShift(b.p)) }
    }
  }
  return d
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
