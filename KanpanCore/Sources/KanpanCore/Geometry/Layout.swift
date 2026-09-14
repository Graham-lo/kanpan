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

  /// 「回到自动贴合」的小徽章，贴在**主图区底边**、价格轴那一列里。
  ///
  /// 只有手动定标（`PriceTransform.isManual`）时才画、才可点——它不是常驻按钮。
  ///
  /// 造型与锚点照 AICoin 安卓包实测（`#tv_scale_auto`，见
  /// `docs/AICoin-安卓包-UI规格提取.md` §3 / §23.3 / §23.4）：
  ///
  /// * **字面是「A」（Auto）不是「R」。** 从前这儿写的是一个圈着的「R」，注释里说是
  ///   「照 AiCoin 手机版」——那是没验证过的推断。反编译出来的 XML 写死 `android:text="A"`。
  /// * **弱徽章不是高亮按钮**：圆角 2dp 的小方块，灰字浅底。AICoin 把「回到最新」做成
  ///   蓝底白字实心 chip、把「自动定标」做成灰字浅底弱徽章，视觉权重是刻意分级的。
  /// * **贴主图区底边**，和「展开右侧面板」图标共用一条基线；不是挂在时间轴上面。
  ///   这条对我们尤其要紧：挂了 MACD + RSI 两个副图之后，时间轴离主图的价格刻度隔着
  ///   大半屏，一个管价格轴的钮摆在那儿等于找不到。
  ///
  /// 横向我们没照它的 `layout_gravity=end`：AICoin 的价格轴画在图里、浮层要 `marginEnd`
  /// 躲开它，我们的价格轴本来就是独立一列，所以跟着列里另外两个方块（最新价胶囊、
  /// 倒计时）一样从 `plotW + 2` 起算，自家对齐比模仿它的 gravity 重要。
  public var autoFitButton: (x: Double, y: Double, w: Double, h: Double) {
    // 10pt 字 + 上下 2pt / 左右 6pt 的内边距，比例照 AICoin 的 12sp + 2dp/6dp。
    // 字宽按等宽数字那一格算（`ChartFont.axis` 是 monospaced），免得 Core 依赖 UIKit。
    let h = 14.0
    let w = min(axisW - 4, 19)
    let m = main
    return (x: plotW + 2, y: m.y + m.h - h - 2, w: max(12, w), h: h)
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
