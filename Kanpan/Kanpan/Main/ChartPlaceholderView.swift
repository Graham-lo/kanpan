import UIKit
import Observation

/// 冷切到一只没快照的品种、K 线还在路上时，图区摆的那张占位图。
///
/// 只画三样，全是淡墨：24h 区间一道淡带、最新价一条细虚线（按它在 24h 区间里的位置摆）、
/// 顶上一条来回走的细进度条。没有文字、没有转圈——旧内容早已清掉（老蜡烛顶着新品种的名字
/// 多一帧都是错的），这张图只回答「这只大概在哪儿、正在来」。真序列一到 `ChartBox` 就把它收起。
///
/// 数据从 `ArrivalBoard.live` 来（`MarketModel.publishChartPlaceholder` 贴的），
/// 不碰行情模型本身。
final class ChartPlaceholderView: UIView {
  private let band = CAShapeLayer()
  private let line = CAShapeLayer()
  private let track = CALayer()
  private let runner = CALayer()
  private(set) var current: ArrivalBoard.ChartPlaceholder?
  private var dark = false

  /// 进度条高度与走一趟的时长。
  static let barHeight: CGFloat = 2
  static let sweep: CFTimeInterval = 1.1

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    isHidden = true
    accessibilityIdentifier = "chart.placeholder"
    line.lineWidth = 1
    line.lineDashPattern = [4, 3]
    line.fillColor = nil
    [band, line].forEach { layer.addSublayer($0) }
    layer.addSublayer(track)
    track.addSublayer(runner)
    track.masksToBounds = true
  }

  required init?(coder: NSCoder) { fatalError("不从 xib 来") }

  /// `nil` = 收起。
  func apply(_ placeholder: ArrivalBoard.ChartPlaceholder?, dark: Bool) {
    let wasHidden = isHidden
    isHidden = placeholder == nil
    guard placeholder != current || dark != self.dark || wasHidden != isHidden else { return }
    current = placeholder
    self.dark = dark
    if isHidden { runner.removeAllAnimations(); return }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let current, !isHidden else { return }
    let ink = dark ? UIColor.white : UIColor.black
    CATransaction.begin(); CATransaction.setDisableActions(true)
    let frames = Self.geometry(for: current, in: bounds)
    band.path = frames.band.map { UIBezierPath(rect: $0).cgPath }
    band.fillColor = ink.withAlphaComponent(0.04).cgColor
    line.path = frames.lineY.map { y in
      let p = UIBezierPath(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: bounds.width, y: y)); return p.cgPath
    }
    line.strokeColor = ink.withAlphaComponent(0.28).cgColor
    track.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.barHeight)
    runner.backgroundColor = ink.withAlphaComponent(0.32).cgColor
    let runW = max(40, bounds.width * 0.28)
    runner.bounds = CGRect(x: 0, y: 0, width: runW, height: Self.barHeight)
    runner.cornerRadius = Self.barHeight / 2
    runner.position = CGPoint(x: -runW / 2, y: Self.barHeight / 2)
    CATransaction.commit()
    runner.removeAllAnimations()
    if UIAccessibility.isReduceMotionEnabled {
      // 减少动效：不来回走，原地淡入淡出。
      runner.bounds.size.width = bounds.width
      runner.position.x = bounds.width / 2
      let fade = CABasicAnimation(keyPath: "opacity")
      fade.fromValue = 0.3; fade.toValue = 1; fade.duration = 0.9
      fade.autoreverses = true; fade.repeatCount = .infinity
      runner.add(fade, forKey: "fade")
    } else {
      let move = CABasicAnimation(keyPath: "position.x")
      move.fromValue = -runW / 2; move.toValue = bounds.width + runW / 2
      move.duration = Self.sweep; move.repeatCount = .infinity
      move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
      runner.add(move, forKey: "sweep")
    }
  }

  /// 纯几何：24h 区间上下各留 20% 的空，最新价按区间里的位置落；只有价没有区间就摆在正中。
  static func geometry(for p: ArrivalBoard.ChartPlaceholder, in rect: CGRect) -> (band: CGRect?, lineY: CGFloat?) {
    let top = rect.minY + rect.height * 0.2, h = rect.height * 0.6
    guard h > 0 else { return (nil, nil) }
    if let low = p.low, let high = p.high, high > low {
      let y = { (v: Double) in top + CGFloat((high - v) / (high - low)) * h }
      let band = CGRect(x: rect.minX, y: top, width: rect.width, height: h)
      let lineY = p.last.map { min(max(y($0), top), top + h) }
      return (band, lineY)
    }
    return (nil, p.last == nil ? nil : rect.midY)
  }
}

extension ChartBox {
  /// 图上没有状态（`chart.state == nil`）且这是行情主图时，照公告板摆 / 收占位图。
  /// 公告板一变就自己再来一遍（`withObservationTracking` 每次只响一下，所以响了重新挂）。
  func syncPlaceholder(enabled: Bool) {
    placeholderEnabled = enabled
    let next: ArrivalBoard.ChartPlaceholder?
    if placeholderArmed {
      next = board.currentChartPlaceholder
    } else {
      placeholderArmed = true
      next = withObservationTracking {
        board.currentChartPlaceholder
      } onChange: { [weak self] in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.placeholderArmed = false
          self.syncPlaceholder(enabled: self.placeholderEnabled)
        }
      }
    }
    let shown = enabled && chart.state == nil ? next : nil
    placeholderView.apply(shown, dark: lastDark ?? (traitCollection.userInterfaceStyle == .dark))
  }
}
