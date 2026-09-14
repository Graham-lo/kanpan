import Foundation

/// 价格轴一格的「好看的步长」：1 / 2 / 2.5 / 5 / 10 × 10^k（§5.8，原型 `niceStep`）。
public func niceStep(span: Double, want: Double) -> Double {
  guard span > 0 else { return 1 }
  let rough = span / max(1, want)
  let mag = pow(10, floor(log10(rough)))
  let n = rough / mag
  let step: Double = n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10
  return step * mag
}

private let MIN: Int64 = 60_000
private let HOUR: Int64 = 3_600_000
private let DAY: Int64 = 86_400_000

/// 时间轴允许的步长阶梯（原型 `TIME_STEPS`）。
public let timeSteps: [Int64] = [
  MIN, 5 * MIN, 15 * MIN, 30 * MIN, HOUR, 2 * HOUR, 4 * HOUR, 6 * HOUR, 12 * HOUR,
  DAY, 2 * DAY, 7 * DAY, 14 * DAY, 30 * DAY, 90 * DAY, 180 * DAY, 365 * DAY,
]

/// 取第一个 ≥ `span / 能放下的标签数` 的阶梯。
public func timeStep(spanMs: Double, plotW: Double, perLabelPx: Double = Chart.timeLabelPx) -> Int64 {
  let want = max(2, floor(plotW / perLabelPx))
  let rough = spanMs / want
  for s in timeSteps where Double(s) >= rough { return s }
  return timeSteps[timeSteps.count - 1]
}

/// 时间轴上要画的刻度（原型 `timeTicks`）：按时区对齐到整点 / 整日。
public func timeTicks(view: ViewWindow, plotW: Double, offsetMinutes: Int, perLabelPx: Double = Chart.timeLabelPx) -> [(t: Double, step: Int64)] {
  let step = timeStep(spanMs: view.span, plotW: plotW, perLabelPx: perLabelPx)
  let shift = Double(offsetMinutes) * 60_000
  let s = Double(step)
  var out: [(Double, Int64)] = []
  var t = ceil((view.from + shift) / s) * s - shift
  while t <= view.to {
    out.append((t, step))
    t += s
  }
  return out
}

/// 价格轴刻度（原型 `drawPriceGrid` 的循环）：在**变换后**的空间里等距。
public func priceTicks(range: PriceRange, mode: PriceMode, paneH: Double) -> [Double] {
  let a = mode.forward(range.lo, base: range.base)
  let z = mode.forward(range.hi, base: range.base)
  guard z > a else { return [] }
  let step = niceStep(span: z - a, want: max(2, floor(paneH / Chart.priceLabelPx)))
  var out: [Double] = []
  var f = (a / step).rounded(.up) * step
  while f <= z {
    out.append(f)
    f += step
  }
  return out
}
