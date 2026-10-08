import Foundation
import KanpanCore

/// 一家交易所在看盘里的全部「身份信息」。
public struct VenueDescriptor: Sendable {
  /// `InstrumentID.venue`。
  public let id: String
  /// `InstrumentID.market`。
  public let market: String
  /// 中文显示名（设置、日志里给人看）。
  public let displayName: String
  /// 品种展示里带的交易所缩写（用户 2026-10-08 定，三端一致，不用图标）：列表行名字前的灰小字
  /// （「币安 DOGE / USDT」）、图表顶栏角标（「币安 USDT 永续」）、桌面快捷方式撞名时的前缀。
  /// 空串 = 不带（美元指数不是交易所）。币安「币安」、OKX「OKX」、Bybit「Bybit」、Hyperliquid「HL」、Coinbase「CB」。
  public let shortName: String
  /// 自选页有没有它自己的一个分类（默认那一家的品种按加密 / 美股分，不单列）。
  public let hasFavoriteCategory: Bool
  /// 参不参加板块页。板块分类表是按某一家的品种表做的，别家的品种不进板块。
  public let joinsSectors: Bool
  /// 冷启动什么都没有时默认看的那一只。
  public let defaultSymbol: String
  /// 自选分类条上那一类叫什么。nil = 用 `displayName`（Coinbase 那一类就叫「Coinbase」）。
  let categoryName: String?
  public typealias Factory = @Sendable (MarketRoute, FeedLog) -> any MarketProvider
  /// 按线路建提供者。
  let make: Factory
  /// 按线路建一个**只供这家本家数据**的提供者（复盘记录、回放）。2026-10-08 起各家在两条线路上供的
  /// 都是自己的数（币安网关档不再有替身），所以和 `make` 是同一个；字段留着，上层的 `ownDataProvider` 不用改。
  let makeOwn: Factory

  public init(id: String, market: String, displayName: String, shortName: String,
              hasFavoriteCategory: Bool, joinsSectors: Bool, defaultSymbol: String,
              categoryName: String? = nil, makeOwn: Factory? = nil, make: @escaping Factory) {
    self.id = id; self.market = market; self.displayName = displayName; self.shortName = shortName
    self.categoryName = categoryName
    self.hasFavoriteCategory = hasFavoriteCategory; self.joinsSectors = joinsSectors
    self.defaultSymbol = InstrumentID(venue: id, market: market, symbol: defaultSymbol).key
    self.make = make
    self.makeOwn = makeOwn ?? make
  }

  public var marketKey: String { "\(id)/\(market)" }
  /// 自选页上它自己那一类的名字；nil = 不单列（按资产类型分）。
  public var favoriteCategory: String? { hasFavoriteCategory ? (categoryName ?? displayName) : nil }
}

/// **唯一的「有哪些交易所」清单。**
///
/// 接第三家交易所：在 `KanpanNetwork/Sources/KanpanNetwork/<交易所>/` 建它的提供者，
/// 在这里 `all` 里加一行，服务端加一条透传。除此之外任何一层都不该出现那家交易所的
/// 名字（`Tools/check-venue-isolation.sh` 守着）。见 `docs/多交易所-接入指南.md`。
public enum VenueRegistry {
  public static let binance = VenueDescriptor(
    id: BinanceProvider.venue, market: BinanceProvider.market, displayName: "币安",
    shortName: "币安", hasFavoriteCategory: false, joinsSectors: true, defaultSymbol: "BTCUSDT"
  ) { route, log in
    BinanceProvider(route: route, log: log)
  }

  /// OKX U 本位永续（`okx/usd_m/BTCUSDT`，键用币安形状的代号，OKX 目录里译成 `BTC-USDT-SWAP`）。
  /// 2026-10-08 起是独立的一家（此前只是币安永续在网关线路上的替身），自选里单独一类「OKX」。
  public static let okx = VenueDescriptor(
    id: OKXVenue.id, market: OKXVenue.market, displayName: OKXVenue.displayName,
    shortName: OKXVenue.shortName, hasFavoriteCategory: true, joinsSectors: false, defaultSymbol: "BTCUSDT"
  ) { route, log in
    OKXProvider(route: route, log: log)
  }

  /// Bybit U 本位永续（`bybit/usd_m/BTCUSDT`，代号原生就是币安形状）。2026-10-08 起接入，自选里单独一类「Bybit」。
  public static let bybit = VenueDescriptor(
    id: BybitVenue.id, market: BybitVenue.market, displayName: BybitVenue.displayName,
    shortName: BybitVenue.shortName, hasFavoriteCategory: true, joinsSectors: false, defaultSymbol: "BTCUSDT"
  ) { route, log in
    BybitProvider(route: route, log: log)
  }

  /// Hyperliquid 永续（USDC 保证金，也记 `usd_m`；键是 coin 名大写 `hyperliquid/usd_m/BTC`、`…/KPEPE`，原名由品种表译回）。
  /// 2026-10-08 起接入，自选里单独一类「Hyperliquid」。
  public static let hyperliquid = VenueDescriptor(
    id: HyperliquidVenue.id, market: HyperliquidVenue.market, displayName: HyperliquidVenue.displayName,
    shortName: HyperliquidVenue.shortName, hasFavoriteCategory: true, joinsSectors: false, defaultSymbol: "BTC"
  ) { route, log in
    HyperliquidProvider(route: route, log: log)
  }

  public static let coinbase = VenueDescriptor(
    id: CoinbaseVenue.id, market: CoinbaseVenue.market, displayName: CoinbaseVenue.displayName,
    shortName: CoinbaseVenue.shortName, hasFavoriteCategory: true, joinsSectors: false, defaultSymbol: "BTC-USD"
  ) { route, log in
    CoinbaseProvider(route: route, log: log)
  }

  /// 美元指数（`macro/index/DXY`）。不是交易所，是看盘自己的 `kanpan-api` 采的一只指数，
  /// 但对上层来说就是又一家「交易所」：品种表里一只、自选里单独一类「指数」、不进板块页、
  /// 不带交易所缩写（行上已经写着「美元指数」）。数据只从 `kanpan-api` 来（`MacroProvider`），
  /// 直连 / 网关两条线路都一样。
  public static let macro = VenueDescriptor(
    id: MacroProvider.venue, market: MacroProvider.market, displayName: "美元指数",
    shortName: "", hasFavoriteCategory: true, joinsSectors: false, defaultSymbol: "DXY",
    categoryName: "指数"
  ) { route, log in
    MacroProvider(route: route, log: log)
  }

  /// 主力订单流接了哪几家（顺序就是保底簿、分连接、图例的顺序）。条目定义在各家目录
  /// （`<交易所>/<交易所>OrderFlow.swift`），通用的 `OrderFlow/` 只查这张表。
  /// 和上面的行情交易所清单（`all`）是两回事：订单流可以接一家不在行情里的交易所（只看它的盘口和成交）。
  public static let orderFlow: [OrderFlowExchange] = [.binance, .okx, .coinbase, .bybit, .hyperliquid]

  /// 注册顺序就是自选分类条、设置里出现的顺序。第一家是默认交易所。
  public static let all: [VenueDescriptor] = [binance, okx, bybit, hyperliquid, coinbase, macro]

  /// 默认交易所：没带交易所前缀的旧数据（裸符号）一律归它。
  public static var `default`: VenueDescriptor { all[0] }

  /// 板块页取全市场行情的那一家（分类表是按它的品种表做的）。
  public static var sectorVenue: VenueDescriptor { all.first { $0.joinsSectors } ?? `default` }

  public static func descriptor(_ venue: String) -> VenueDescriptor? {
    let v = venue.lowercased()
    return all.first { $0.id == v }
  }

  /// 品种键 → 它所在的那一家。认不出的交易所按默认那一家。
  public static func descriptor(forSymbol key: String) -> VenueDescriptor {
    descriptor(InstrumentID(key).venue) ?? `default`
  }

  /// 默认交易所的出厂 REST / 推送域名。
  public static var defaultRestHost: String { BinanceProvider.defaultRestHost }
  public static var defaultStreamHost: String { BinanceProvider.defaultStreamHost }
  /// 默认交易所绝不能用的推送域名（测试网等）。
  public static var legacyStreamHosts: [String] { BinanceProvider.legacyStreamHosts }
}
