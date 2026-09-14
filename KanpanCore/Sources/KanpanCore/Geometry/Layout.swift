import Foundation

/// 一块画布：主图或某个副图。
public struct Pane: Sendable, Equatable {
  /// 主图是 `nil`，副图是它画的指标。
  public var indicator: IndicatorID?
  public var y: Double
  public var h: Double
  public var isMain: Bool { indicator == nil }
  public init(indicator: IndicatorID?, y: Double, h: Double) {
    self.indicator = indicator; self.y = y; self.h = h
  }
}

/// 一帧的布局（§5.3）。所有距离都从当前风格表读，没有全局常数。
public struct Layout: Sendable, Equatable {
  public var W: Double
  public var H: Double
  public var plotW: Double
  public var mainH: Double
  public var subH: Double
  public var timeY: Double
  public var panes: [Pane]

  public var main: Pane { panes[0] }
  /// 价格轴宽（右侧）。
  public var axisW: Double { W - plotW }

  public init(width W: Double, height H: Double, style: CandleStyle, subs: [IndicatorID]) {
    self.W = W
    self.H = H
    plotW = max(40, W - style.axisW)
    subH = min(style.subH, max(44, (H - style.timeH) * 0.3))
    mainH = max(80, H - style.timeH - Double(subs.count) * subH)
    timeY = H - style.timeH
    var list = [Pane(indicator: nil, y: 0, h: mainH)]
    var y = mainH
    for k in subs {
      list.append(Pane(indicator: k, y: y, h: subH))
      y += subH
    }
    panes = list
  }
}
