import Foundation

/// 品种在交易所那边的挂牌状态（`exchangeInfo.symbols[].status`）。
///
/// 交易所那张表里状态有十来种（`PENDING_TRADING` / `TRADING` / `BREAK` / `HALT` /
/// `AUCTION_MATCH` / `END_OF_DAY` / `PRE_SETTLE` / `SETTLING` / `CLOSE` /
/// `PRE_DELIVERING` / `DELIVERING` / `DELIVERED`…），但对用户只有四件事有意义：
/// **能不能交易、还没开盘、临时停牌、已经下架**。界面按这一档决定要不要给实时价的样子，
/// 不加任何文字标签。
///
/// 只保留 `TRADING` 会把「下架」和「根本不存在」压成同一件事：自选里那一行会凭空消失，
/// 图表会拿一张陌生的占位表现出「正常」的样子（见审查 B-06）。
///
/// 而把停牌也算成下架同样是错的（审查复核项 3）：美股永续、贵金属每天收盘都会报
/// `BREAK` / `END_OF_DAY`，币安自己在维护窗口里报 `HALT`，OKX 那条网关也会把
/// 交易所状态映射成 `BREAK`。合成三档时它们每天晚上都「下架」一次——一整页美股变灰、
/// 「全部合约」少掉几十行、自选里的黄金像被摘牌。停牌是**临时**的：身份和外观都正常，
/// 价格不再动这件事由「价格不新鲜」那条规则自己处理，不需要状态再说一遍。
public enum SymbolStatus: String, Sendable, Equatable, Codable, CaseIterable {
  /// `TRADING`：正常挂牌，价格照常当实时价看。
  case tradable
  /// `PENDING_TRADING` / `PRE_TRADING`：已经在表里但还没开盘，没有实时价。
  case pending
  /// `BREAK` / `HALT` / `AUCTION_MATCH` / `END_OF_DAY`：**临时**停牌（收盘、休市、
  /// 集合竞价、交易所维护）。合约还在、还会再开，所以身份与外观一律按正常处理，
  /// 只有价格停着不动那一面交给「价格不新鲜」的规则。
  case halted
  /// `SETTLING` / `PRE_SETTLE` / `CLOSE` / `DELIVERING` / `DELIVERED`…：
  /// 已经停止交易且不会再开，不再有实时价。
  case delisted

  /// 交易所字符串 → 四档。认不出来的（含缺字段）按 `tradable`，
  /// 宁可把一个怪状态当正常，也不要凭一个没见过的枚举值把用户的自选打成灰的。
  public static func exchange(_ raw: String?) -> SymbolStatus {
    guard let raw, !raw.isEmpty else { return .tradable }
    switch raw.uppercased() {
    case "TRADING", "OPEN", "LIVE": return .tradable
    case "PENDING_TRADING", "PRE_TRADING", "PREOPEN", "PRE_OPEN": return .pending
    case "BREAK", "HALT", "HALTED", "AUCTION_MATCH", "END_OF_DAY", "SUSPEND", "SUSPENDED":
      return .halted
    case "SETTLING", "PRE_SETTLE", "CLOSE", "CLOSED", "DELIVERING", "PRE_DELIVERING",
         "DELIVERED": return .delisted
    default: return .tradable
    }
  }

  /// 这一档还该不该按「有实时价的正常合约」对待。
  ///
  /// `pending` 与 `delisted` 不该——一个还没开始，一个已经结束，都不会再有新价。
  /// `halted` 该：停牌只是这一段时间没有成交，合约还在交易所的表上，
  /// 列表里照常排、计数里照常算、颜色照常给；价格陈旧由价格那条规则去说。
  public var hasLivePrice: Bool { self == .tradable || self == .halted }

  /// 是不是「临时不成交」。只给需要区分停牌与正常的地方用（目前没有界面用它，
  /// 留着是为了让「停牌不是下架」这件事在代码里有名字）。
  public var isHalted: Bool { self == .halted }
}

/// 品种。字段取自 `exchangeInfo`（§4.1）。
public struct SymbolInfo: Sendable, Equatable, Codable, Identifiable {
  public var symbol: String            // BTCUSDT
  public var base: String              // BTC
  public var quote: String             // USDT
  public var pricePrecision: Int
  public var quantityPrecision: Int
  public var tickSize: Double
  public var underlyingType: String?
  public var underlyingSubTypes: [String]?
  public var contractType: String?
  /// 挂牌状态。目录层会把非 `TRADING` 的行**留在表里**并打上这一档（审查 B-06）。
  public var status: SymbolStatus
  /// 上线时间（`exchangeInfo.symbols[].onboardDate`，毫秒）。缺字段 / 旧缓存为 `nil`。
  public var onboardDate: Int64?

  public var id: String { symbol }
  /// 顶栏和品种页里显示的名字：BTC/USDT。
  public var display: String { base + "/" + quote }

  public init(symbol: String, base: String, quote: String = "USDT",
              pricePrecision: Int, quantityPrecision: Int = 3, tickSize: Double, underlyingType: String? = nil,
              underlyingSubTypes: [String]? = nil, contractType: String? = nil,
              status: SymbolStatus = .tradable, onboardDate: Int64? = nil) {
    self.symbol = symbol
    self.base = base
    self.quote = quote
    self.pricePrecision = pricePrecision
    self.quantityPrecision = quantityPrecision
    self.tickSize = tickSize
    self.underlyingType = underlyingType
    self.underlyingSubTypes = underlyingSubTypes
    self.contractType = contractType
    self.status = status
    self.onboardDate = onboardDate
  }

  /// 旧盘上的目录缓存里没有 `status`，解码时当 `tradable`——
  /// 否则一次升级就会让整张磁盘目录解不开、冷启动必须等网络。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    symbol = try c.decode(String.self, forKey: .symbol)
    base = try c.decode(String.self, forKey: .base)
    quote = try c.decodeIfPresent(String.self, forKey: .quote) ?? "USDT"
    pricePrecision = try c.decode(Int.self, forKey: .pricePrecision)
    quantityPrecision = try c.decodeIfPresent(Int.self, forKey: .quantityPrecision) ?? 3
    tickSize = try c.decode(Double.self, forKey: .tickSize)
    underlyingType = try c.decodeIfPresent(String.self, forKey: .underlyingType)
    underlyingSubTypes = try c.decodeIfPresent([String].self, forKey: .underlyingSubTypes)
    contractType = try c.decodeIfPresent(String.self, forKey: .contractType)
    status = try c.decodeIfPresent(SymbolStatus.self, forKey: .status) ?? .tradable
    onboardDate = try c.decodeIfPresent(Int64.self, forKey: .onboardDate)
  }

  /// 「新」记号的窗口：上线 30 天以内（P2.15）。
  public static let newListingWindowMs: Int64 = 30 * 86_400_000

  /// 上线不满 30 天。还没到上线时间的（预告上线）不算——它还没「上线」。
  public func isNewListing(nowMs: Int64) -> Bool {
    guard let onboardDate, onboardDate > 0 else { return false }
    let age = nowMs - onboardDate
    return age >= 0 && age <= Self.newListingWindowMs
  }

  /// 价格按 `tickSize` 定小数位：0.1 → 1 位，0.001 → 3 位（§A1.11）。
  public var priceDecimals: Int {
    guard tickSize > 0 else { return pricePrecision }
    let d = Int((-log10(tickSize)).rounded())
    return max(0, min(12, d))
  }

  /// 摆一口价要几位小数。
  ///
  /// 有 `tickSize` 时用 `priceDecimals`；没有步长时才用 `pricePrecision`。
  /// `placeholder` 的步长与精度都为 0，表示目录未知，
  /// 那就按这口价自己猜——写死 2 位会把 0.0000004 摆成 `0.00`，那是在说
  /// 「这东西不值钱」（审查 B-07）。
  public func displayDecimals(for price: Double) -> Int {
    tickSize > 0 || pricePrecision > 0 ? priceDecimals : priceDecimalsFallback(price)
  }

  /// 只知道代号时的占位行。
  ///
  /// 用在「目录里没有这个代号」的场合（审查复核项 4）：自选里那一行照旧要摆出来，
  /// 摆之前总得有个 `SymbolInfo`。只有 `symbol` 是真的；`base`/`quote` 按后缀拆，
  /// 精度留 0 表示「不知道」，由 `displayDecimals(for:)` 按价格猜。
  public static func placeholder(symbol: String, status: SymbolStatus = .tradable) -> SymbolInfo {
    let s = symbol.uppercased()
    let quote = ["USDT", "USDC", "USD1", "BUSD"].first { s.hasSuffix($0) } ?? "USDT"
    let base = s.hasSuffix(quote) ? String(s.dropLast(quote.count)) : s
    return SymbolInfo(symbol: s, base: base.isEmpty ? s : base, quote: quote,
                      pricePrecision: 0, tickSize: 0, status: status)
  }
}

/// 一个代号「在不在品种目录里」这件事（审查复核项 4）。
///
/// 目录查不到有两种，摆出来必须不一样，可原来三处各按自己的默认值猜：
/// 自选页把查不到当 `.tradable`（于是一个已经不在表上的自选看着完全正常），
/// 品种页干脆把它从自选分区里 `compactMap` 掉（那一行凭空消失），
/// 目录层 `markDelisted` 对不在表里的代号直接 return（明确的下架记不下来）。
///
/// 现在一条规矩：
/// * `.listed` —— 目录里有它，一切按交易所那一档状态走；
/// * `.unknown` —— 目录到了、里面没有它。这是「未知」：那一行**留着**，按没有实时价
///   渲染（最后那口真价变灰、由实时价算出来的全留空），但不划掉、不删、也不算下架；
/// * `.unloaded` —— 目录还没到（冷启动第一帧、离线）。什么都不知道就别装作知道：
///   价还是刚从交易所来的，凭「目录慢」把它打灰是冤枉它。
public enum SymbolListing: Sendable, Equatable {
  case listed(SymbolStatus)
  case unknown
  case unloaded

  /// - Parameters:
  ///   - info: 目录里查出来的行，`nil` 表示查不到。
  ///   - catalogLoaded: 目录本身到了没有（一般就是 `!catalog.isEmpty`）。
  public static func of(_ info: SymbolInfo?, catalogLoaded: Bool) -> SymbolListing {
    if let info { return .listed(info.status) }
    return catalogLoaded ? .unknown : .unloaded
  }

  /// 还该不该按「有实时价的正常行」渲染。
  public var hasLivePrice: Bool {
    switch self {
    case .listed(let status): return status.hasLivePrice
    case .unknown: return false
    case .unloaded: return true
    }
  }

  /// 是不是**明确**已下架。只有目录里标过 `.delisted` 的才算；
  /// 「未知」不算——它只是我们不知道，不是交易所说它没了。
  public var isDelisted: Bool { self == .listed(.delisted) }
}

/// 24h 统计与当前成交。实时成交先到时按 open24h 重算滚动涨跌幅；
/// 日切口径由共享报价层处理，缺失统计保持缺失。
public struct Ticker: Sendable, Equatable {
  public var symbol: String
  public var last: Double
  /// 交易所 24 小时涨跌额；缺失时保留空值。
  public var priceChange: Double?
  public var changePercent: Double
  public var high: Double
  public var low: Double
  public var quoteVolume: Double
  public var markPrice: Double?
  public var open24h: Double?
  /// Exchange snapshot time (REST closeTime / WS C), never local arrival time.
  public var timeMs: Int64?
  public var lastTradeID: Int64?

  /// 振幅以24h开盘价为分母，独立于用户选择的日涨跌幅口径。
  public var amplitude24h: Double? {
    guard let open24h, open24h.isFinite, open24h > 0, high.isFinite, low.isFinite, high >= low else { return nil }
    return (high - low) / open24h * 100
  }

  public init(symbol: String, last: Double, changePercent: Double,
              high: Double, low: Double, quoteVolume: Double, markPrice: Double? = nil, open24h: Double? = nil,
              timeMs: Int64? = nil, lastTradeID: Int64? = nil, priceChange: Double? = nil) {
    self.symbol = symbol
    self.last = last
    self.priceChange = priceChange.flatMap { $0.isFinite ? $0 : nil }
    self.changePercent = changePercent
    self.high = high
    self.low = low
    self.quoteVolume = quoteVolume
    self.markPrice = markPrice
    self.open24h = open24h
    self.timeMs = timeMs
    self.lastTradeID = lastTradeID
  }
}
