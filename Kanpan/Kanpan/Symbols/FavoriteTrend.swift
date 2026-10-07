import KanpanCore
import SwiftUI

// ============================================================ 自选行的 24 小时走势线与药丸闪动
//
// 2026-10-08 视觉与交互整改：
// - 自选行价格与涨跌药丸之间一条 56×20 的迷你走势线，取最近 24 小时的 15 分钟收盘
//   （`QuoteBook.onTrend`，和预览卡那份逐分钟线同一趟取），尾点接最新价；按这 24 小时的涨跌
//   用涨 / 跌色描 1.5pt，不填充、不垫底。没取到就空着那 56pt，不摆占位、不闪。
//   设置 › 通用「自选走势线」一颗全局开关（`Prefs.favoritesTrend`，出厂开，跟账号同步）。
// - 涨跌药丸在同一只的价真动了一口时按这一口的方向闪 150ms（底提亮一档再落回去），
//   口径照 `KanpanChart.ChartView.flashIfTicked`：换品种、换列表 / 分类都不算「一口」，
//   系统「减少动效」打开时不闪。只闪药丸，不动整行。

/// 一只品种最近 24 小时的走势：起点（24 小时前那根的开盘）和其后每根的收盘。纯值。
struct FavoriteTrend: Equatable, Sendable {
  /// 24 小时前那一刻的价（窗口里第一根的开盘），算 24 小时涨跌的分母。
  let open: Double
  /// 每根的收盘，按时间先后。最后一根是还没收的那根（盘中价）。
  let closes: [Double]

  /// 窗口长度与根数上限：24 小时 15 分钟线，多给一根让窗口左缘正好落在 24 小时前。
  static let window: Int64 = 24 * 3_600_000
  static let capacity = 97

  /// 从一段 K 线里截出最近 24 小时。少于两根、价不成数时返回 nil（画不出线就不画）。
  static func make(bars: [Bar], now: Int64) -> FavoriteTrend? {
    let start = now - window - 900_000
    let kept = bars.filter { $0.openTime >= start }.suffix(capacity)
    guard kept.count >= 2, let first = kept.first, first.open.isFinite, first.open > 0 else { return nil }
    let closes = kept.map(\.close)
    guard closes.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
    return FavoriteTrend(open: first.open, closes: closes)
  }

  /// 画出来的那一串点：尾点换成最新价（有的话），线的右端和价格那一格说的是同一口价。
  func points(last: Double?) -> [Double] {
    guard let last, last.isFinite, last > 0, !closes.isEmpty else { return closes }
    var out = closes
    out[out.count - 1] = last
    return out
  }

  /// 24 小时涨跌（比值，0.012 = +1.2%）：尾点对起点。
  func change(last: Double?) -> Double {
    let end = points(last: last).last ?? open
    return end / open - 1
  }
}

/// 自选行上那条 56×20 的走势线。没数据时只让出那块地方（不画、不占位），行里其余几格不挪。
struct FavoriteTrendLine: View, Equatable {
  let trend: FavoriteTrend?
  let last: Double?
  /// 涨 / 跌色（`theme.up` / `theme.down`），平盘用弱墨。
  let up: Color
  let down: Color
  let flat: Color

  static let width: CGFloat = 56
  static let height: CGFloat = 20
  static let lineWidth: CGFloat = 1.5

  nonisolated static func == (l: Self, r: Self) -> Bool {
    l.trend == r.trend && l.last == r.last && l.up == r.up && l.down == r.down && l.flat == r.flat
  }

  var body: some View {
    Group {
      if let trend {
        let change = trend.change(last: last)
        let ink = change > 0 ? up : (change < 0 ? down : flat)
        FavoriteTrendShape(points: trend.points(last: last))
          .stroke(ink, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round, lineJoin: .round))
      } else {
        Color.clear
      }
    }
    .frame(width: Self.width, height: Self.height)
    .accessibilityHidden(true)
  }
}

/// 折线本身：点按时间等距铺满宽，纵向按这一段的高低点铺满高（上下各留半根线宽，不被裁）。
/// 一条直线（高低点相等）画在正中。
struct FavoriteTrendShape: Shape {
  let points: [Double]

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard points.count >= 2, let lo = points.min(), let hi = points.max() else { return path }
    let inset = FavoriteTrendLine.lineWidth / 2
    let h = rect.height - inset * 2
    let step = rect.width / CGFloat(points.count - 1)
    let span = hi - lo
    for (i, value) in points.enumerated() {
      let x = rect.minX + CGFloat(i) * step
      let y = span > 0 ? rect.minY + inset + CGFloat((hi - value) / span) * h : rect.midY
      if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    return path
  }
}

/// 涨跌药丸收到的「这一口」：哪一只、什么价。药丸只在同一只的价真变了时闪。
struct PillTick: Equatable {
  let key: String
  let price: Double

  enum Direction: Equatable { case up, down }

  /// 闪不闪、往哪边闪。规则同 `ChartView.flashIfTicked`：前后两口都得有、是同一只、
  /// 都是成数的正价、而且真的变了；系统「减少动效」打开时一律不闪。
  static func flash(from old: PillTick?, to new: PillTick?, reduceMotion: Bool) -> Direction? {
    guard !reduceMotion, let old, let new, old.key == new.key,
          old.price.isFinite, new.price.isFinite, old.price > 0, new.price > 0,
          old.price != new.price else { return nil }
    return new.price > old.price ? .up : .down
  }

  /// 闪多久：和图上最新价胶囊一样（`ChartView.priceFlashDuration`）。
  static let duration: Duration = .milliseconds(150)
}
