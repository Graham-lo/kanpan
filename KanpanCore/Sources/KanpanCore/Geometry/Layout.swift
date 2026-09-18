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

/// 一帧的布局（§5.3）。所有视觉风格共用 AICoin 分区，风格不改变看盘位置。
public struct Layout: Sendable, Equatable {
  public var W: Double
  public var H: Double
  public var plotW: Double
  public var mainH: Double
  /// 副图高。**每个副图可以不一样高**（A6.4 的小/中/大三档），所以这个字段只是个
  /// 代表值：有副图时等于第一个副图的高度，没有副图时等于风格表那档夹过上限的值。
  ///
  /// 留着它是因为外面有人读（取证探针 A3.2 的 `subH` 那一行、`LayoutTests`）。
  /// 要某一块的真实高度一律读 `panes[k].h`，别拿这个数去乘个数。
  public var subH: Double
  public var timeY: Double
  public var panes: [Pane]

  public var main: Pane { panes[0] }
  /// 价格轴宽（右侧）。
  public var axisW: Double { W - plotW }

  /// 真机 A 徽章位于价格轴内；下方灰圆是侧栏控制，不能混用。
  public var autoFitButton: (x: Double, y: Double, w: Double, h: Double) {
    (plotW + max(2, (axisW - 16) / 2), max(0, mainH - 42), 16, 17)
  }

  /// 手指落在那个小钮上没有。判定范围比画出来的大一圈（44pt 的可点区域按不到就当没有）。
  public func hitsAutoFit(x: Double, y: Double) -> Bool {
    let b = autoFitButton
    let pad = max(0, (44 - b.w) / 2)
    return x >= b.x - pad && x <= b.x + b.w + pad && y >= b.y - pad && y <= b.y + b.h + pad
  }

  /// - Parameter subScale: 每个副图各自的高度倍率（A6.4 `Prefs.subHeights`）。
  ///   缺省 / 查不到就是 1.0 = 风格表原值 = 现状。三档的具体倍率定义在 app 层
  ///   （`SubPaneHeight.scale`），Core 只收倍率，不在这儿再定义一份，不然两处会漂。
  public init(
    width W: Double, height H: Double, subs: [IndicatorID],
    subScale: [IndicatorID: Double] = [:], mainWeight: Double = 3, axisWidth: Double = AICoinBehavior.axisWidth
  ) {
    self.W = W
    self.H = H
    plotW = max(40, W - axisWidth)
    let content = max(1, H - AICoinBehavior.timeHeight)
    let weights = subs.map { id -> Double in
      let raw = subScale[id] ?? 1
      return raw.isFinite ? min(2, max(0.5, raw)) : 0.5
    }
    let unit = content / (max(0.5, mainWeight) + weights.reduce(0, +))
    mainH = content - weights.reduce(0, +) * unit
    timeY = mainH
    subH = weights.first.map { $0 * unit } ?? unit
    var list = [Pane(indicator: nil, y: 0, h: mainH)]
    var y = mainH + AICoinBehavior.timeHeight
    for (id, weight) in zip(subs, weights) {
      let height = weight * unit
      list.append(Pane(indicator: id, y: y, h: height))
      y += height
    }
    panes = list
  }
}

/// The user's one-screen preference takes priority for the usual 3–4 panels.
/// Only windows too small for readable panes need overflow scrolling.
public enum ChartContentLayout {
  /// 这张图一共要多高。绝大多数时候就是视口本身——只有窗口矮到连一格都读不出来时
  /// 才溢出来滚动。
  ///
  /// 以前这个签名还收 `control:`（主副图比例）和 `subScale:`（各副图的高度倍率），
  /// 函数体一个都没用到，调用处那句 `control: state.options.portraitHeight` 是喂给
  /// 空气的——`portraitHeight` 真正起作用的地方是 `mainWeight(height:control:count:)`。
  /// 2026-09-19 删掉这两个参数：留着只会让人以为高度还受它们影响，进而去找一个
  /// 根本不存在的写入端。
  public static func height(viewport: Double, subs: [IndicatorID], portrait: Bool) -> Double {
    max(viewport, (portrait ? 120 : 72) + Double(subs.count) * (portrait ? 40 : 28) + AICoinBehavior.timeHeight)
  }
  public static func mainWeight(height: Double, control: Double, count: Int) -> Double {
    guard count > 0 else { return 3 }
    let setting = control.isFinite ? min(1, max(0, control)) : 0.5
    let content = max(1, height - AICoinBehavior.timeHeight)
    let minimumSub = min(40, content / Double(count + 3))
    let preferred = 3 * (0.5 + setting)
    return min(preferred, max(0.5, content / minimumSub - Double(count)))
  }
}

public enum CandleDataBox {
  /// Container-relative placement; midpoint is an implementation choice, not an iPhone measurement.
  public static func rect(plotWidth: Double, mainHeight: Double, selectedX: Double,
                          desiredWidth: Double, desiredHeight: Double, follow: Bool) -> (x: Double, y: Double, width: Double, height: Double) {
    let width = max(1, min(desiredWidth, plotWidth - 8))
    let height = max(1, min(desiredHeight, mainHeight - 8))
    let x = follow && selectedX < plotWidth / 2 ? plotWidth - width - 4 : 4
    return (max(0, x), min(44, max(4, mainHeight - height - 4)), width, height)
  }
}

public enum ChartGestureRoute {
  /// 副图内长按移动整个面板；主图与价格轴保持原来的手势职责。
  public static func reorderPane(x: Double, y: Double, plotWidth: Double, panes: [Pane]) -> IndicatorID? {
    guard x >= 0, x < plotWidth else { return nil }
    return panes.first { $0.indicator != nil && y >= $0.y && y < $0.y + $0.h }?.indicator
  }

  public static func pageScroll(x: Double, y: Double, dx: Double, dy: Double, touches: Int,
                                plotWidth: Double, mainHeight: Double, manualY: Bool, selecting: Bool) -> Bool {
    guard touches == 1, !selecting, abs(dy) > 1.5 * abs(dx) else { return false }
    if y < mainHeight && (x > plotWidth || manualY) { return false }
    return true
  }
}

/// Continuous panel resize uses the same relative weights as preset heights.
public enum SubPaneResize {
  public static func scale(initialHeight: Double, translation: Double, contentHeight: Double,
                           otherWeight: Double) -> Double {
    guard contentHeight > 0, translation.isFinite, otherWeight > 0 else { return 1 }
    let desired = min(contentHeight - 1, max(1, initialHeight + translation))
    return min(2, max(0.5, desired * otherWeight / (contentHeight - desired)))
  }
}
