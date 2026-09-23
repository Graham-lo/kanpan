import Foundation

/// 指标标识与展示信息；已支持集合由下方枚举定义，增量仅见 docs/待办交接-Codex-2026-09-22.md。
///
/// rawValue 是存档用的（写进偏好、缓存键），所以是英文、定死不许改；界面上露脸的
/// 是 `name` 和 `lineNames`，那两处一律中文（`kanpan-ui-labels-are-chinese`）。
public enum IndicatorID: String, Sendable, Codable, CaseIterable, Hashable {
  // ---- 声明顺序是有约束的：**主图的 case 必须全部排在副图 case 前面**。
  // 契约里 `overlayIndicatorIDs ++ subIndicatorIDs == indicatorIDs` 是按顺序比的
  // （Swift 侧 `PrefsFieldPlanTests`、Rust 侧 `sync_validation` 各断言一次），
  // 而那三张表都是照 `allCases` 生成的。所以 2026-09-22 新增的三把主图指标插在
  // 布林带后面，两把副图指标接在基差后面，不能图省事一律追加到末尾。
  case ma = "MA", ema = "EMA", boll = "BOLL"
  case vwap = "VWAP", supertrend = "ST", sar = "SAR"
  /// 主力订单流（2026-09-24）：挂单簿里过门槛的大单画成色带。它不是 K 线算出来的指标，
  /// 开关存在 `Prefs.orderFlow`、不进 `overlays`；枚举里有它是为了面板那一行和契约的词表。
  case orderFlow = "ORDERFLOW"
  case vol = "VOL", macd = "MACD", rsi = "RSI", kdj = "KDJ", srsi = "SRSI", atr = "ATR", oi = "OI"
  case lsr = "LSR", taker = "TAKER", basis = "BASIS"
  case dmi = "DMI"
  case cvd = "CVD"

  public enum Where: Sendable { case main, sub }

  public var placement: Where {
    switch self {
    case .ma, .ema, .boll, .vwap, .supertrend, .sar, .orderFlow: .main
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
    case .vwap: "当日均价线"
    case .supertrend: "超级趋势"
    case .sar: "抛物线转向"
    case .orderFlow: "主力订单流"
    case .dmi: "动向指标"
    case .cvd: "累计成交量差"
    }
  }

  // ---------------------------------------------------------------- 面板清单
  //
  // 面板上摆哪几把、按什么顺序摆，由下面这两张表说了算，**不是** `allCases`。
  //
  // 两者分开是为了「退役但不删」：`.srsi`（随机强弱）与 `.atr`（真实波幅）2026-09-22
  // 撤出面板，但枚举里必须留着——它们的 rawValue 可能已经存在某台设备的偏好里，
  // 删掉 case 会让那份偏好整个解不出来。留着 case、退出清单，再由
  // `retired` 在读偏好时把它们滤掉，老用户升级后看不见，新用户选不到，
  // 存档与同步契约一个字都不用动。
  //
  // 真实波幅撤了但算法留着：超级趋势的通道宽度就是 ATR(周期)×倍数，`SuperTrendState`
  // 内部照用 `RecursiveLine(.rma)` 算，只是不再单独占一张副图。

  /// 主图可选指标，面板顺序。
  public static let mainPalette: [IndicatorID] = [.ma, .ema, .boll, .vwap, .supertrend, .sar, .orderFlow]
  /// 副图可选指标，面板顺序。
  ///
  /// 累计成交量差紧跟成交量：两把读的是同一件事的两面（成交了多少 / 是谁在成交），
  /// 摆在一起才好挨着看。
  public static let subPalette: [IndicatorID] = [
    .vol, .cvd, .macd, .rsi, .kdj, .dmi, .oi, .lsr, .taker, .basis,
  ]
  /// 面板上还摆着的全部。
  public static let palette: [IndicatorID] = mainPalette + subPalette
  /// 退役的：还能解码、还能算，但不再出现在面板上，读偏好时要滤掉。
  public static let retired: [IndicatorID] = [.srsi, .atr]
  /// 这把还在面板上吗。
  public var isRetired: Bool { Self.retired.contains(self) }

  /// 把一串存档里的指标滤成「现在还摆着的」，顺序不动、不去重。
  public static func alive(_ ids: [IndicatorID]) -> [IndicatorID] { ids.filter { !$0.isRetired } }

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

  /// 每把指标的出厂参数。**客户端只此一份**：偏好的出厂值（`factoryParams`）、
  /// 图表状态的缺省、存档修补（`IndicatorParamRule.sanitize`）、引擎补位
  /// （`normalizedParams`）都从这里取。
  ///
  /// 审查 2026-09-24 §2：以前这里写的是通用教科书值（均线 7/25/99、MACD 12/26/9），
  /// 偏好出厂值却是 `AICoinBehavior` 里另抄的 AICoin 值（10/30/120/256、10/30/9），
  /// 图表状态又是第三份（没有指数均线）——同一个用户，新装时看到的是 AICoin 值，
  /// 一条参数坏了被修补时却掉回 7/25/99。现在只有 AICoin 手机端这一套
  /// （`kanpan-single-aicoin-candle-style`：图表底座照 AICoin 还原）。
  public var defaultParams: [Int] {
    switch self {
    case .ma: [10, 30, 120, 256]
    case .ema: [12, 144, 169, 200]
    case .boll: [20, 2]
    case .vol: [5, 10, 30, 60, 120]
    case .macd: [10, 30, 9]
    case .rsi: [6, 12, 24]
    case .kdj: [9, 3, 3]
    case .srsi: [14, 14, 3, 3]
    case .atr: [14]
    case .supertrend: [10, 3]
    case .dmi: [14]
    // 当日VWAP 的起点是当日零点，抛物线转向的加速步长是定死的 0.02/0.20：
    // 两把都没有该让用户去拨的参数
    // （`kanpan-sector-page-no-basis-picker`：口径这种东西我来定，不摆出来给他选）。
    // 累计成交量差是逐根净额的累加，没有窗口长度这回事；归零的锚和当日VWAP 一样
    // 是定死的（日内按 UTC 零点），同样不摆给用户拨。
    // 主力订单流的桶宽、门槛、条数、颜色都由代码定死，没有参数。
    case .vwap, .sar, .orderFlow, .cvd, .oi, .lsr, .taker, .basis: []
    }
  }

  /// 新装时写进偏好、图表状态缺省就带着的那几把的参数（值就是 `defaultParams`）。
  /// 只放这四把是历史形状：偏好存档与同步里一直带着它们，别的指标没记就是没记。
  public static let factoryParams: [IndicatorID: [Int]] =
    Dictionary(uniqueKeysWithValues: [IndicatorID.ma, .ema, .vol, .macd].map { ($0, $0.defaultParams) })

  /// 算之前把参数理成这把指标能直接下标取用的长度。
  ///
  /// 参数是从偏好里来的：用户手输、云端同步、老版本存下来的都有，长度不可信。
  /// 固定个数的那几把（布林、MACD、KDJ、随机强弱、真实波幅、超级趋势、动向）在引擎里
  /// 按 `p[0]`…`p[3]` 直接取，少一个就是越界崩溃——所以缺的位置用默认值补上，
  /// 多出来的丢掉。按列表画的那几把（均线、指数均线、强弱、均量）条数本来就随用户，原样。
  /// 取值本身（0、负数）不在这里改：各条线对脏窗口长度自有处理，画成「这段没有线」
  /// （见 `IndicatorEdgeTests`、`degenerateParamsAtIndexZero`）。
  public func normalizedParams(_ params: [Int]?) -> [Int] {
    guard let params else { return defaultParams }
    switch self {
    case .ma, .ema, .rsi, .vol:
      return params
    default:
      return defaultParams.indices.map { i in i < params.count ? params[i] : defaultParams[i] }
    }
  }

  public var paramLabels: [String] {
    switch self {
    // 均线、指数均线、均量是按列表画的，条数随用户；面板上按「周期1、周期2…」排，
    // 这里给出厂那几条的名字，个数跟着 `defaultParams` 走。
    case .ma, .ema, .vol: defaultParams.indices.map { "周期\($0 + 1)" }
    case .boll: ["周期", "倍数"]
    case .macd: ["快", "慢", "信号"]
    case .rsi: ["①", "②", "③"]
    case .kdj: ["周期", "快线", "慢线"]
    case .srsi: ["相对强弱", "随机周期", "快线", "慢线"]
    case .atr: ["周期"]
    case .supertrend: ["周期", "倍数"]
    case .dmi: ["周期"]
    case .vwap, .sar, .orderFlow, .cvd, .oi, .lsr, .taker, .basis: []
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
    // 超级趋势与抛物线转向都只有一条线，多空靠 `IndicatorResult.dir` 换色，
    // 不拆成「多头 / 空头」两条——拆了图例上永远有一条是「--」。
    case .vwap: ["当日均价"]
    case .supertrend: ["超级趋势"]
    case .sar: ["转向点"]
    // 图例那一行的名字（ChartRenderer+OrderFlow 画「主力 买 … · 卖 …」）。
    case .orderFlow: ["主力"]
    case .dmi: ["多头动向", "空头动向", "趋势强度"]
    case .cvd: ["累计成交量差"]
    }
  }

  /// 这把主图指标从调色板的第几格开始取色。
  ///
  /// 调色板只有六格，主图上同时可能挂着均线（三条）、指数均线（两条）和当日VWAP
  /// （一条），刚好六条。各自从不同的格子起取，两条线才不会撞成同一个颜色：
  /// 均线 0/1/2、指数均线 3/4、当日VWAP 5。超级趋势与抛物线转向不在此列——
  /// 它们按多空用皮肤自己的涨跌色，不占调色板的格子。
  ///
  /// 放在这里而不是绘制层，是因为设置面板里那个颜色选择器要显示同一个默认值；
  /// 从前那道 `+3` 的偏移在绘制层和面板各写了一遍，改一处另一处就不认了。
  public var paletteOffset: Int {
    switch self {
    case .ema: 3
    case .vwap: 5
    default: 0
    }
  }

  /// 画成什么。默认是折线；抛物线转向是一根一个点，连起来就错了——
  /// 它的相邻两点之间没有「中间值」这回事，翻向那一根更是直接从价格下面跳到上面。
  public enum Plot: Sendable { case line, dots }
  public var plot: Plot { self == .sar ? .dots : .line }

  /// 锁死的纵轴区间（§8）。原型 `drawSub`：RSI 与 StochRSI 锁 0–100；
  /// **KDJ 不锁**——J 线常年冲出 0–100，锁了就看不见了，它走自适应。
  /// 多空比 / 主动买卖比 / 基差也一律不锁：前两个是比值，平时贴着 1 上下几个百分点晃，
  /// 锁进一个固定区间就成一条直线；基差率更是常年在 ±0.1% 内。它们靠 `guides` 上的
  /// 那条基准线读方向，不靠固定刻度。
  ///
  /// 动向指标同样不锁：三条线理论上在 0–100 之间，可实盘里趋势强度常年趴在 10–40，
  /// 锁到 0–100 就把它压成贴着底的一条平线。
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
    // 累计成交量差的分水岭是 0：这一段是被买上去的还是被卖下去的，就看线在 0 的哪一边。
    case .basis, .cvd: [0]
    // 趋势强度 25 以上才算真有趋势，是 Wilder 自己给的那条线。
    case .dmi: [25]
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
  /// 逐根的多空方向（> 0 多、< 0 空、NaN 不着色），只有超级趋势与抛物线转向给。
  ///
  /// 为什么不拆成两条线：拆了图例上永远有一条读作「--」，而且两条线各自被调色板
  /// 分到一个跟涨跌毫无关系的颜色。方向单独一列，绘制那一层就能拿它把**同一条线**
  /// 按根分段上色，用的是这套皮肤自己的涨跌色（`kanpan-kline-colors-are-aicoin-only`）。
  public var dir: [Double]?

  public init(lines: [[Double]], histogram: [Double]? = nil, dir: [Double]? = nil) {
    self.lines = lines
    self.histogram = histogram
    self.dir = dir
  }

  /// 第 i 根上每条线的值，图例用。
  public func values(at i: Int) -> [Double] {
    lines.map { $0.indices.contains(i) ? $0[i] : .nan }
  }
}
