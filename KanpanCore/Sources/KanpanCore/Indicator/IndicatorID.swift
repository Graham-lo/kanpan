import Foundation

/// 指标标识与展示信息；已支持集合由下方枚举定义，增量仅见 docs/待办交接-Codex-2026-09-22.md。
public enum IndicatorID: String, Sendable, Codable, CaseIterable, Hashable {
  case ma = "MA", ema = "EMA", boll = "BOLL"
  case vol = "VOL", macd = "MACD", rsi = "RSI", kdj = "KDJ", srsi = "SRSI", atr = "ATR", oi = "OI"

  public enum Where: Sendable { case main, sub }

  public var placement: Where {
    switch self {
    case .ma, .ema, .boll: .main
    default: .sub
    }
  }

  public var name: String {
    switch self {
    case .ma: "MA"
    case .ema: "EMA"
    case .boll: "BOLL"
    case .vol: "成交量"
    case .macd: "MACD"
    case .rsi: "RSI"
    case .kdj: "KDJ"
    case .srsi: "StochRSI"
    case .atr: "ATR"
    case .oi: "持仓量"
    }
  }

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
    case .oi: []
    }
  }

  public var paramLabels: [String] {
    switch self {
    case .ma: ["短", "中", "长"]
    case .ema: ["短", "长"]
    case .boll: ["周期", "倍数"]
    case .vol: ["MA1", "MA2"]
    case .macd: ["快", "慢", "信号"]
    case .rsi: ["①", "②", "③"]
    case .kdj: ["N", "K", "D"]
    case .srsi: ["RSI", "Stoch", "K", "D"]
    case .atr: ["周期"]
    case .oi: []
    }
  }

  /// 每条线的名字，图例里用。
  public func lineNames(params: [Int]) -> [String] {
    switch self {
    case .ma, .ema: params.map { "\(name)\($0)" }
    case .boll: ["MID", "UP", "DN"]
    case .vol: params.map { "MA\($0)" }
    case .macd: ["DIF", "DEA"]
    case .rsi: params.map { "RSI\($0)" }
    case .kdj: ["K", "D", "J"]
    case .srsi: ["K", "D"]
    case .atr: ["ATR"]
    case .oi: ["持仓量"]
    }
  }

  /// 锁死的纵轴区间（§8）。原型 `drawSub`：RSI 与 StochRSI 锁 0–100；
  /// **KDJ 不锁**——J 线常年冲出 0–100，锁了就看不见了，它走自适应。
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
