import Foundation
import KanpanCore

/// 「看细节」（§10.1）：十字线选中一根大周期 K 线之后，换到更细的一档，
/// 并把视野**刚好铺成那根大 K 线覆盖的时间区间**——那一根里面究竟是怎么走出来的，
/// 一眼看完。
///
/// 这儿只有三件纯粹的算术：更细的那一档是哪一档、铺成多宽的时间窗、以及
/// 「切回大周期时该回到哪个视野」那个小栈（`DetailZoomStack`）。
enum DetailZoom {
  /// 细档至少要把大 K 线切成多少根。
  ///
  /// 不是取 14 档序列里紧挨着的那一档（4h 的下一档是 2h，一根大 K 线只分成两根，
  /// 铺满一屏就是两根蜡烛，什么细节都没有）。根宽有上限（`AICoinBehavior.maximumSpacing`
  /// = 40pt），手机图区宽 340～390pt，也就是说少于十根的区间根本铺不满一屏——
  /// 视野会被 `clampView` 撑回去，左边露出一截和这根大 K 线无关的历史。
  /// 取 12 是在这条硬约束上留一点余量：4h → 15m（16 根）、1h → 5m（12 根）、
  /// 1d → 2h（12 根），都是「一根拆开来看」该有的样子。
  static let minimumSubBars = 12

  /// 「看细节」该进哪一档：**还能把这根切成 12 根以上的那些档里最粗的一档**。
  ///
  /// 一档都不够细（5m / 3m 这种本来就很细的档）就退到最细的 1m——人点了这颗按钮，
  /// 总得有细节可看。已经是 1m 了返回 nil，那时候这颗按钮根本不该出现。
  static func finer(than interval: Interval) -> Interval? {
    let all = Interval.allCases
    guard let here = all.firstIndex(of: interval), here > 0 else { return nil }
    let span = Double(interval.stepMs)
    for i in stride(from: here - 1, through: 0, by: -1) {
      if span / Double(all[i].stepMs) >= Double(minimumSubBars) { return all[i] }
    }
    return all[0]
  }

  /// 铺成刚好覆盖那根大 K 线的时间窗，左右各留半根细 K 线的空隙。
  ///
  /// 蜡烛是**骑在自己开盘时刻上**画的（`clampView` 里 `first = firstTime - step/2`），
  /// 所以细序列里属于这根大 K 线的那些蜡烛，占的是 `[开 - s/2, 下一根开 - s/2]`。
  /// 两头各再让出半根，就是下面这个 `[开 - s, 下一根开]`——区间正中是那根大 K 线的
  /// 全部内容，两边各空半根，不会有一根蜡烛贴着边被切掉一半。
  ///
  /// `barEnd` 传**下一根大 K 线的开盘时刻**（没有下一根就按名义步长加一格）：1M / 1y
  /// 那两档的真实长度不等，拿名义步长算会漏掉月末那几天。
  static func window(barOpen: Double, barEnd: Double, finer: Interval) -> ViewWindow {
    let s = Double(finer.stepMs)
    return ViewWindow(from: barOpen - s, to: barEnd)
  }
}

/// 「切回大周期时回到切之前的那个视野」用的小栈，按品种记。
///
/// 只在**看历史**的时候压栈（跟着最新的那种情形没有什么要恢复的，回去就该贴着最新）。
/// 换品种整栈作废——同一段时间在另一个品种上什么都不是。
struct DetailZoomStack: Equatable {
  struct Frame: Equatable {
    var interval: Interval
    var view: ViewWindow
  }

  /// 栈里这几帧是谁的。空串 = 还没压过。
  private(set) var symbol: String = ""
  private(set) var frames: [Frame] = []

  /// 一趟「看细节」最多往下钻几层。钻到第四层还想往回翻的人是不存在的，
  /// 留着只会让很久以前的一个视野在某次换档时冷不丁跳出来。
  static let maximumDepth = 4

  var isEmpty: Bool { frames.isEmpty }

  mutating func push(symbol: String, interval: Interval, view: ViewWindow) {
    let key = symbol.uppercased()
    if key != self.symbol { frames = []; self.symbol = key }
    frames.removeAll { $0.interval == interval }
    frames.append(Frame(interval: interval, view: view))
    if frames.count > Self.maximumDepth { frames.removeFirst(frames.count - Self.maximumDepth) }
  }

  /// 切回某一档：把那一帧连同压在它上面的几帧一起弹掉，交出那份视野。
  /// 栈里没有这一档（或者换了品种）就返回 nil，按平时换周期办。
  mutating func pop(symbol: String, interval: Interval) -> ViewWindow? {
    guard symbol.uppercased() == self.symbol,
          let at = frames.lastIndex(where: { $0.interval == interval }) else { return nil }
    let view = frames[at].view
    frames.removeSubrange(at...)
    return view
  }

  mutating func clear() { frames = []; symbol = "" }
}
