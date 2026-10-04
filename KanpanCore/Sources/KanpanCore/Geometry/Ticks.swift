import Foundation

/// 价格轴一格的「好看的步长」：1 / 2 / 2.5 / 5 / 10 × 10^k（§5.8，原型 `niceStep`）。
func niceStep(span: Double, want: Double) -> Double {
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

/// 时间轴允许的步长阶梯（原型 `TIME_STEPS`，末尾补了 2 / 5 / 10 年）。
///
/// 原型封顶一年：月线缩到最密时 BTC 九年历史塞进三百来点宽，一年一格只有三十几点，
/// 标签挤成一团（审查 B·P3-3）。一周及以上的步长只是「标称长度」，用来挑档；
/// 真正的刻度按日历摆（见 `timeTicks`）。
let timeSteps: [Int64] = [
  MIN, 5 * MIN, 15 * MIN, 30 * MIN, HOUR, 2 * HOUR, 4 * HOUR, 6 * HOUR, 12 * HOUR,
  DAY, 2 * DAY, 7 * DAY, 14 * DAY, 30 * DAY, 90 * DAY, 180 * DAY, 365 * DAY,
  730 * DAY, 1825 * DAY, 3650 * DAY,
]

/// 按日历月推进的档：一档跨几个月。月 / 季 / 半年 / 年 / 2 年 / 5 年 / 10 年。
func calendarMonths(step: Int64) -> Int? {
  switch step {
  case 30 * DAY: return 1
  case 90 * DAY: return 3
  case 180 * DAY: return 6
  case 365 * DAY: return 12
  case 730 * DAY: return 24
  case 1825 * DAY: return 60
  case 3650 * DAY: return 120
  default: return nil
  }
}

/// 公历某年某月某日（本地零点）距 1970-01-01 的天数（Howard Hinnant 的 days_from_civil）。
/// 和 `DateParts` 的拆法互为逆运算，都不走 `Calendar`——画一帧要算几十个，`Calendar` 太重。
public func daysFromCivil(year y0: Int, month m: Int, day d: Int) -> Int {
  let y = m <= 2 ? y0 - 1 : y0
  let era = (y >= 0 ? y : y - 399) / 400
  let yoe = y - era * 400
  let mp = (m + 9) % 12                       // 三月 = 0
  let doy = (153 * mp + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  return era * 146_097 + doe - 719_468
}

/// 1970-01-05 是周一，比 epoch（周四）晚 4 天：周 / 两周的刻度以它为锚。
private let MONDAY_ANCHOR: Int64 = 4 * DAY

/// 取第一个 ≥ `span / 能放下的标签数` 的阶梯。
func timeStep(spanMs: Double, plotW: Double, perLabelPx: Double = Chart.timeLabelPx) -> Int64 {
  let want = max(2, floor(plotW / perLabelPx))
  let rough = spanMs / want
  for s in timeSteps where Double(s) >= rough { return s }
  return timeSteps[timeSteps.count - 1]
}

/// 时间轴上要画的刻度（原型 `timeTicks`）：按时区对齐。
///
/// - 一天以内：对齐到整点 / 整日（步长整倍数）。
/// - 周 / 两周：对齐到**周一**零点。原型按 epoch 整倍数对齐，1970-01-01 是周四，
///   于是周线上的刻度全落在周四、指在两根 K 线之间（审查 B·P3-3）。
/// - 月及以上：对齐到**某月 1 号**零点，按日历月推进——季落在 1/4/7/10 月、半年落在 1/7 月、
///   年落在 1 月 1 号、2 / 5 / 10 年落在能整除的年份。原型拿 30 / 90 / 365 天的秒数整除，
///   标出来是「03-17」「2023-11」这种逐年漂移、没有意义的日子。
public func timeTicks(view: ViewWindow, plotW: Double, offsetMinutes: Int, perLabelPx: Double = Chart.timeLabelPx) -> [(t: Double, step: Int64)] {
  guard view.from.isFinite, view.to.isFinite, view.to > view.from else { return [] }
  let step = timeStep(spanMs: view.span, plotW: plotW, perLabelPx: perLabelPx)
  let shift = Double(offsetMinutes) * 60_000
  var out: [(Double, Int64)] = []
  if let months = calendarMonths(step: step) {
    let start = DateParts(ms: view.from, offsetMinutes: offsetMinutes)
    var index = start.year * 12 + (start.month - 1)
    let r = ((index % months) + months) % months
    if r != 0 { index += months - r }
    // 视野再宽也就几十格；上限只防坏输入把循环拖死。
    for _ in 0..<4096 {
      let year = Int((Double(index) / 12).rounded(.down))
      let month = index - year * 12 + 1
      let t = Double(daysFromCivil(year: year, month: month, day: 1)) * Double(DAY) - shift
      if t > view.to { break }
      if t >= view.from { out.append((t, step)) }
      index += months
    }
    return out
  }
  let s = Double(step)
  let anchor = step % (7 * DAY) == 0 ? Double(MONDAY_ANCHOR) : 0
  var t = ceil((view.from + shift - anchor) / s) * s + anchor - shift
  while t <= view.to {
    out.append((t, step))
    t += s
  }
  return out
}

/// 同上，但时区口径按「这一屏右边缘那个时刻」解一次（审查 B-08）。
///
/// 刻度的**对齐**只能用一个偏移（整屏同一套网格线），跨夏令时那一屏最多差一格；
/// 每个刻度上的**文案**是 `fmtTick(ms:step:offsetMinutes: TZOffset)` 各自按自己的时刻算的，
/// 所以历史标签不会整段平移。
public func timeTicks(view: ViewWindow, plotW: Double, offsetMinutes: TZOffset,
                      perLabelPx: Double = Chart.timeLabelPx) -> [(t: Double, step: Int64)] {
  timeTicks(view: view, plotW: plotW,
            offsetMinutes: offsetMinutes.minutes(at: view.to), perLabelPx: perLabelPx)
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
