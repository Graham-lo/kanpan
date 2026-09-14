import Foundation

/// K 线图表的一组开关（对标 AICoin「K 线设置」里跟图有关的那几项）。
///
/// 默认值一律「维持现状」：全默认时渲染结果和没有这个结构时逐像素相同。
///
/// 这条不是客气话。A3.11 的 176 张基线是**已经定版的验收证据**，加功能不许让它漂移，
/// 所以每一项的默认值都必须落回旧代码原来那条分支上——`.style` 就是「读风格表自己的
/// 值」，`lastLine` / `drawings` 就是「照画」。凡是新增的画法（倒计时、至今涨幅），
/// 默认一律关，哪怕设置页里它本来是开的（`Prefs.countdown` §10.4 默认开）：
/// 那个开关由 app 层喂进来，不是这里的事。
public struct ChartOptions: Sendable, Equatable {
  /// 蜡烛画成什么：真实 OHLC，还是平均 K 线。
  public var kind: CandleKind = .candle
  /// 网格：跟随风格 / 强制显示 / 强制隐藏。
  public var grid: GridChoice = .style
  /// 实体：跟随风格 / 强制实心 / 强制阳线空心。
  public var body: BodyChoice = .style
  /// 实时价格线（主图那条横线 + 右轴胶囊）。关掉连倒计时一起没有——它是挂在胶囊底下的。
  public var lastLine: Bool = true
  /// 用户画的趋势线 / 水平线显不显示。关掉只是不画，数据一根不删。
  public var drawings: Bool = true
  /// 本根倒计时。还得 `ChartState.nowMs` 有值才画得出来。
  public var countdown: Bool = false
  /// 十字线打开时，在图例末尾多报一段「从这根到最新一根的涨跌幅」。
  public var sinceChange: Bool = false
  /// 蜡烛在主图区里的上下位置。只挪位置，不改大小，见 `PriceBias`。
  public var bias: PriceBias = .center
  /// 「回到最新」时最新一根落在横向的哪儿。只有复位入口读它，渲染器不关心。
  public var anchor: ViewAnchor = .right
  public init() {}
}

/// 蜡烛画法。
public enum CandleKind: String, Sendable, Codable, CaseIterable {
  case candle, heikin

  public var display: String {
    switch self {
    case .candle: "蜡烛"
    case .heikin: "平均K线"
    }
  }
}

/// 网格覆盖。`.style` 读风格表，另两档强制。
public enum GridChoice: String, Sendable, Codable, CaseIterable {
  case style, on, off

  public var display: String {
    switch self {
    case .style: "跟随风格"
    case .on: "显示"
    case .off: "隐藏"
    }
  }
}

/// 实体覆盖。`.style` 读风格表，另两档强制。
public enum BodyChoice: String, Sendable, Codable, CaseIterable {
  case style, solid, hollowUp

  public var display: String {
    switch self {
    case .style: "跟随风格"
    case .solid: "实心"
    case .hollowUp: "阳线空心"
    }
  }
}

/// 蜡烛在主图区里的上下位置。
///
/// 说的是**蜡烛**往哪边偏，不是留白往哪边偏——`.up` 是「蜡烛贴上面」，
/// 所以留白得堆到下面去。名字按用户看到的那件事取，别按实现取。
public enum PriceBias: String, Sendable, Codable, CaseIterable {
  case up, center, down

  public var display: String {
    switch self {
    case .up: "偏上"
    case .center: "居中"
    case .down: "偏下"
    }
  }

  /// 总留白量固定是 `2 × style.pad`（风格表里那个数），这里只决定它怎么分给上下。
  ///
  /// 之所以「总量不变只改分配」：留白总量一变，价格区间的跨度就变了，蜡烛会跟着
  /// 整体缩放。用户要的是「把蜡烛挪上去」，不是「把蜡烛画小一点」，两件事别混。
  var shares: (top: Double, bottom: Double) {
    switch self {
    case .up: (0.2, 0.8)
    case .center: (0.5, 0.5)
    case .down: (0.8, 0.2)
    }
  }
}

/// 「回到最新」时最新一根停在图区的哪一侧。
public enum ViewAnchor: String, Sendable, Codable, CaseIterable {
  case left, center, right

  public var display: String {
    switch self {
    case .left: "偏左"
    case .center: "居中"
    case .right: "靠右"
    }
  }
}
