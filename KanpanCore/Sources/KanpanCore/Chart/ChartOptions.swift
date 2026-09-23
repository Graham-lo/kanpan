import Foundation

/// Shared chart options; defaults follow the current phone profile.
public struct ChartOptions: Sendable, Equatable {
  /// 主图画成什么：真实 OHLC 蜡烛、平均 K 线，还是只画收盘价折线。
  public var kind: CandleKind = .candle
  /// 网格：跟随风格 / 强制显示 / 强制隐藏。
  public var grid: GridChoice = .off
  /// 实体：实心 / 阳线空心。
  public var body: BodyChoice = .solid
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
  public var dataDisplay: CandleDataDisplay = .inside
  public var crossPrice: CrossPriceMode = .selected
  /// 主图价格轴允许翻转（上下颠倒）。**默认关**：一次误触就把整张图倒过来、
  /// 副图还不跟着翻，代价远大于它的用处；真要用的人去设置里开。
  public var allowMainInversion = false
  public var allowSubInversion = false
  public var adaptiveIndicators = false
  /// Native relative control, not a conversion from mirror screenshot coordinates.
  public var portraitHeight = 0.5
  public init() {}
}

/// 主图画法。
///
/// `line` 是「收盘价」：主图只画一条收盘价折线（外加照常的最新价线与右轴胶囊），
/// 价格区间也只按收盘价撑——影线不画，就不该让看不见的高低点把折线压扁。
/// 存盘与同步走 rawValue，三个名字都不能改。
public enum CandleKind: String, Sendable, Codable, CaseIterable {
  case candle, heikin, line

  public var display: String {
    switch self {
    case .candle: "蜡烛"
    case .heikin: "平均K线"
    case .line: "收盘价"
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

/// 阳线实体画法。
///
/// 原来还有一档 `.style`「跟随风格」——风格表只剩 AICoin 一套之后（见 `CandleStyle`），
/// 「跟随」和「实心」是同一件事，面板上并排摆两个一模一样的选项只会让人以为自己没点对。
/// 旧存档里的 `"style"` 在 `PrefsCodec` 里直接读成 `.solid`。
public enum BodyChoice: String, Sendable, Codable, CaseIterable {
  case solid, hollowUp

  public var display: String {
    switch self {
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

public enum CandleDataDisplay: String, Sendable, Codable, CaseIterable { case inside, top, follow }
public enum CrossPriceMode: String, Sendable, Codable, CaseIterable { case selected, close }
