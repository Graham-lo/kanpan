import KanpanChart
import KanpanCore
import SwiftUI
import UIKit

/// 换了数据之后视野该怎么办。
///
/// 三种情形在原型里是三套算法（`reset` / `switchInterval` / `applySpacing`），
/// 差别在于「保住什么」：换品种什么都不保，换周期保根宽，换风格保右缘。
enum ViewIntent: Equatable {
  case keep
  /// 换品种、第一次拿到数据：回到最新，按风格的默认根间距。
  case reset
  /// 换周期：根宽不变，看见的时间跨度跟着周期走。带的是切之前量出来的实际根间距。
  case switchInterval(spacing: Double)
  /// 换风格：右缘不动，按新风格的默认根间距重算窗宽。
  case applySpacing
}

/// 装着 `ChartView` 的盒子，外加一件事：等布局出来再兑现视野。
///
/// 视野要算就得先知道图区有多宽（`plotW`），而 `UIViewRepresentable` 造视图那一刻
/// 帧还是零，`chartLayout` 是 `nil`，算不出来。所以把意图记下来，`layoutSubviews`
/// 里再兑现。`ChartView` 是 `final`（快照测试要它的行为完全定死），所以这里用「包一层」
/// 而不是继承。
final class ChartBox: UIView {
  let chart = ChartView(frame: .zero)
  var pending: ViewIntent = .reset

  override init(frame: CGRect) {
    super.init(frame: frame)
    addSubview(chart)
  }

  required init?(coder: NSCoder) { fatalError("不从 xib 来") }

  override func layoutSubviews() {
    super.layoutSubviews()
    chart.frame = bounds
    chart.layoutIfNeeded()
    applyPending()
  }

  func applyPending() {
    guard pending != .keep, var s = chart.state, s.series.count > 0, let L = chart.chartLayout
    else { return }
    let plotW = L.plotW
    let next: ViewWindow
    switch pending {
    case .keep:
      return
    case .reset:
      next = ViewMath.reset(series: s.series, plotW: plotW, spacing: s.style.spacing)
    case .switchInterval(let spacing):
      next = ViewMath.switchInterval(
        to: s.series, plotW: plotW, spacing: spacing, anchorRight: nil)
    case .applySpacing:
      next = ViewMath.applySpacing(
        s.view, series: s.series, plotW: plotW, spacing: s.style.spacing)
    }
    pending = .keep
    s.view = next
    chart.state = s
    chart.onViewChanged?(next)
  }
}

/// 给 SwiftUI 递过去的一个把手。
///
/// 「回到最新」要叫的是 `ChartView.scrollToLatest()`，那是 UIKit 那一侧的方法；
/// SwiftUI 这边拿不到视图实例，所以建视图时把它挂进来。弱引用——视图归 SwiftUI 管，
/// 这里只是借来用一下。
@MainActor
final class ChartProxy {
  weak var box: ChartBox?

  func scrollToLatest() { box?.chart.scrollToLatest() }
  var isAtLatest: Bool { box?.chart.isAtLatest ?? true }
}

/// 把 `ChartView`（UIKit + CoreGraphics 手绘）嵌进 SwiftUI。
///
/// 这里刻意只做两件事：把 `state` 灌进去、把手势回调接出来。**不要**在这儿摆任何
/// SwiftUI 控件——图上的一切（十字线、读数、最新价胶囊）都归 `ChartRenderer` 画，
/// 混着摆就会出现两套坐标系，转屏和改副图高度时必然对不齐。
struct ChartHost: UIViewRepresentable {
  var state: ChartState?
  var proxy: ChartProxy?
  /// 手势改了视野。视野是**图自己**的状态，不走 SwiftUI 的 `@State` 回环——
  /// 每帧 60/120 次穿过 SwiftUI 的 diff 太贵，所以图自己改自己，改完通知外面记一笔。
  var onView: (ViewWindow) -> Void = { _ in }
  var onCrosshair: (Crosshair?) -> Void = { _ in }
  var onNeedsHistory: () -> Void = {}
  var onTapped: () -> Void = {}
  /// 画线壳（M7）。线本身住在 `ChartState.drawings` 里、手势归图，这个只负责
  /// 亮哪一颗按钮和按品种落盘。
  var drawing: DrawingController?

  func makeUIView(context: Context) -> ChartBox {
    let box = ChartBox(frame: .zero)
    proxy?.box = box
    wire(box)
    box.chart.state = state
    return box
  }

  func updateUIView(_ box: ChartBox, context: Context) {
    proxy?.box = box
    wire(box)
    guard var s = state else {
      box.chart.state = nil
      box.pending = .reset
      return
    }
    if let old = box.chart.state, old.series.count > 0 {
      // 视野归图自己管：外面传下来的那份是「上一次图告诉我的」，原样塞回去会把
      // 手势正在做的位移覆盖掉。只在品种/周期/风格真换了的时候才重算。
      s.view = old.view
      s.crosshair = old.crosshair
      // 线和视野一个道理：画的时候每帧都在动，外面那份必然是旧的。
      s.drawings = old.drawings
      if old.series.symbol != s.series.symbol {
        box.pending = .reset
      } else if old.series.interval != s.series.interval {
        let plotW = box.chart.chartLayout?.plotW ?? Double(box.bounds.width)
        box.pending = .switchInterval(
          spacing: old.view.barSpacing(step: old.series.step, plotW: plotW))
      } else if old.style.id != s.style.id {
        box.pending = .applySpacing
      }
    } else {
      box.pending = .reset
    }
    box.chart.state = s
    box.applyPending()
    // 放在灌完 state 之后：`focus` 会往图里塞这个品种的线，早一步会被上面那行盖掉。
    drawing?.focus(s.series.symbol)
  }

  private func wire(_ box: ChartBox) {
    drawing?.attach(box.chart)
    box.chart.onViewChanged = onView
    box.chart.onCrosshairChanged = onCrosshair
    box.chart.onNeedsHistory = onNeedsHistory
    box.chart.onTapped = onTapped
  }
}
