import Foundation

/// 指标标识与展示信息；已支持集合由下方枚举定义，增量仅见 docs/待办交接-Codex-2026-09-22.md。
///
/// rawValue 是存档用的（写进偏好、缓存键），所以是英文、定死不许改；界面上露脸的
/// 是 `name` 和 `lineNames`，那两处一律中文（`kanpan-ui-labels-are-chinese`）。
public enum IndicatorID: String, Sendable, Codable, CaseIterable, Hashable {
  case ma = "MA", ema = "EMA", boll = "BOLL"
  case vol = "VOL", macd = "MACD", rsi = "RSI", kdj = "KDJ", srsi = "SRSI", atr = "ATR", oi = "OI"
  case lsr = "LSR", taker = "TAKER", basis = "BASIS"

  public enum Where: Sendable { case main, sub }

  public var placement: Where {
    switch self {
    case .ma, .ema, .boll: .main
    default: .sub
    }
  }

  public var name: String {
    switch self {
    case .ma: "均线"
    case .ema: "指数均线"
    case .boll: "布林带"
    case .vol: "成交量"
    case .macd: "平滑异同"
    case .rsi: "相对强弱"
    case .kdj: "随机指标"
    case .srsi: "随机强弱"
    case .atr: "真实波幅"
    case .oi: "持仓量"
    case .lsr: "多空比"
    case .taker: "主动买卖比"
    case .basis: "基差"
    }
  }

  /// 这个指标要几列外部数据；nil 表示它只吃 K 线，自己算得出来。
  ///
  /// 加这个是为了把「外部输入」这件事说清楚：引擎的留用判断和缓存键都得知道
  /// 某个指标的值不只取决于 K 线（见 `IndicatorEngine.ensure` 里的留用条件），
  /// 从前只有持仓量一个，是硬写成 `id != .oi` 的后门；现在四个了，再开后门必漏。
  public var externalColumns: Int? {
    switch self {
    case .oi, .lsr, .taker, .basis: 1
    default: nil
    }
  }

  /// 值是外面喂进来的（持仓量、多空比、主动买卖比、基差），不是 K 线算出来的。
  public var isExternal: Bool { externalColumns != nil }

  public var defaultParams: [Int] {
    switch self {
    case .ma: [7, 25, 99]
    case .ema: [12, 26]
    case .boll: [20, 2]
    case .vol: [5, 10]
    case .macd: [12, 26, 9]
    case .rsi: [6, 12, 24]
    case .kdj: [9, 3, 3]
    case .srsi: [14, 14, 3, 3]
    case .atr: [14]
    case .oi, .lsr, .taker, .basis: []
    }
  }

  public var paramLabels: [String] {
    switch self {
    case .ma: ["短", "中", "长"]
    case .ema: ["短", "长"]
    case .boll: ["周期", "倍数"]
    case .vol: ["均量一", "均量二"]
    case .macd: ["快", "慢", "信号"]
    case .rsi: ["①", "②", "③"]
    case .kdj: ["周期", "快线", "慢线"]
    case .srsi: ["相对强弱", "随机周期", "快线", "慢线"]
    case .atr: ["周期"]
    case .oi, .lsr, .taker, .basis: []
    }
  }

  /// 每条线的名字，图例里用。
  public func lineNames(params: [Int]) -> [String] {
    switch self {
    case .ma, .ema: params.map { "\(name)\($0)" }
    case .boll: ["中轨", "上轨", "下轨"]
    case .vol: params.map { "均量\($0)" }
    case .macd: ["差值", "信号"]
    case .rsi: params.map { "强弱\($0)" }
    case .kdj: ["快线", "慢线", "敏感线"]
    case .srsi: ["快线", "慢线"]
    case .atr: ["真实波幅"]
    case .oi: ["持仓量"]
    case .lsr: ["多空比"]
    case .taker: ["主动买卖比"]
    case .basis: ["基差率"]
    }
  }

  /// 锁死的纵轴区间（§8）。原型 `drawSub`：RSI 与 StochRSI 锁 0–100；
  /// **KDJ 不锁**——J 线常年冲出 0–100，锁了就看不见了，它走自适应。
  /// 多空比 / 主动买卖比 / 基差也一律不锁：前两个是比值，平时贴着 1 上下几个百分点晃，
  /// 锁进一个固定区间就成一条直线；基差率更是常年在 ±0.1% 内。它们靠 `guides` 上的
  /// 那条基准线读方向，不靠固定刻度。
  public var fixedScale: (lo: Double, hi: Double)? {
    switch self {
    case .rsi, .srsi: (0, 100)
    default: nil
    }
  }

  /// 参考线（原型 `subLines` 的第三个参数）。RSI 是 30/70，KDJ 与 StochRSI 是 20/80。
  public var guides: [Double] {
    switch self {
    case .rsi: [30, 70]
    case .kdj, .srsi: [20, 80]
    // 多空比 / 主动买卖比的分水岭是 1（多空一样多、主动买卖一样多），基差是 0。
    case .lsr, .taker: [1.0]
    case .basis: [0]
    default: []
    }
  }

  /// 副图默认：MACD + RSI；主图默认：MA（§3.2，定死）。
  public static let defaultOverlays: [IndicatorID] = [.ma]
  public static let defaultSubs: [IndicatorID] = [.macd, .rsi]

  /// 增量重算要回头算多少根：最长参数 + 1（§5.7）。
  public func tailBars(params: [Int]) -> Int {
    let maxParam = params.max() ?? 1
    switch self {
    case .srsi: return (params.first ?? 14) + (params.dropFirst().first ?? 14) + maxParam + 1
    case .macd: return (params.max() ?? 26) * 2 + 1
    default: return maxParam + 1
    }
  }
}

/// 一个指标算出来的东西。
public struct IndicatorResult: Sendable, Equatable {
  /// 画成线的那些列，顺序与 `lineNames` 一致。
  public var lines: [[Double]]
  /// MACD 的柱；别的指标是 nil。
  public var histogram: [Double]?

  public init(lines: [[Double]], histogram: [Double]? = nil) {
    self.lines = lines
    self.histogram = histogram
  }

  /// 第 i 根上每条线的值，图例用。
  public func values(at i: Int) -> [Double] {
    lines.map { $0.indices.contains(i) ? $0[i] : .nan }
  }
}
