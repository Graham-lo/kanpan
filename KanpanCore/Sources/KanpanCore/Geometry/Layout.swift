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

  /// 「回到自动贴合」的小钮，摆在价格轴底部、时间轴上面那一格。
  ///
  /// 位置照 AiCoin：桌面版那儿是「对数 / %  / 自动」三个钮，手机版地方不够，
  /// 换成一个圈着的「R」。我们是手机，所以取手机那一版；「对数 / 百分比」两档在
  /// 设置面板里已经有了（A6.8），这儿只留「自动」这一件事。
  ///
  /// 只有手动定标（`PriceTransform.isManual`）时才画、才可点。
  public var autoFitButton: (x: Double, y: Double, w: Double, h: Double) {
    let d = min(22, max(14, axisW - 8))
    return (x: plotW + (axisW - d) / 2, y: timeY - d - 6, w: d, h: d)
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
    width W: Double, height H: Double, style: CandleStyle, subs: [IndicatorID],
    subScale: [IndicatorID: Double] = [:]
  ) {
    self.W = W
    self.H = H
    plotW = max(40, W - style.axisW)
    timeY = H - style.timeH

    // 单个副图的高度上限，口径和以前一样是**按单个算**的（不是按总和）：
    // 副图多到把主图挤没时兜底的是下面 `mainH` 的 80，这条只管别让某一块太胖。
    let cap = max(44, (H - style.timeH) * 0.3)
    // 倍率夹到 0.5…2：这是公开入口，外面塞个离谱的数进来会把主图压到 80 的保底值上。
    func heightOf(_ k: IndicatorID) -> Double {
      let s = min(2, max(0.5, subScale[k] ?? 1))
      return min(max(44, (style.subH * s).rounded()), cap)
    }

    let hs = subs.map(heightOf)
    // 空列表时保留老式子的结果（`min(style.subH, cap)`），不然极矮窗口下这个代表值
    // 会跳一下——它不参与绘制，但进了取证表。
    subH = hs.first ?? min(max(44, style.subH), cap)
    mainH = max(80, H - style.timeH - hs.reduce(0, +))
    var list = [Pane(indicator: nil, y: 0, h: mainH)]
    var y = mainH
    for (k, h) in zip(subs, hs) {
      list.append(Pane(indicator: k, y: y, h: h))
      y += h
    }
    panes = list
  }
}
