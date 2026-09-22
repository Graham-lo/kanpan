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
  /// 搜索结果行右侧的小字标注。nil = 不标（默认那一家不标）。
  public let searchTag: String?
  /// 自选页有没有它自己的一个分类（默认那一家的品种按加密 / 美股分，不单列）。
  public let hasFavoriteCategory: Bool
  /// 参不参加板块页。板块分类表是按某一家的品种表做的，别家的品种不进板块。
  public let joinsSectors: Bool
  /// 冷启动什么都没有时默认看的那一只。
  public let defaultSymbol: String
  public typealias Factory = @Sendable (MarketRoutePolicy, MarketEndpoints, FeedLog) -> any MarketProvider
  /// 按线路建提供者（网关上可能是替身）。
  let make: Factory
  /// 按线路建一个**只供这家本家数据**的提供者：复盘记录、回放说的是这家自己的 K 线，
  /// 替身的数对不上，宁可取不到也不拿替身顶。没有替身的交易所两者相同。
  let makeOwn: Factory

  public init(id: String, market: String, displayName: String, searchTag: String?,
              hasFavoriteCategory: Bool, joinsSectors: Bool, defaultSymbol: String,
              makeOwn: Factory? = nil, make: @escaping Factory) {
    self.id = id; self.market = market; self.displayName = displayName; self.searchTag = searchTag
    self.hasFavoriteCategory = hasFavoriteCategory; self.joinsSectors = joinsSectors
    self.defaultSymbol = InstrumentID(venue: id, market: market, symbol: defaultSymbol).key
    self.make = make
    self.makeOwn = makeOwn ?? make
  }

  public var marketKey: String { "\(id)/\(market)" }
}

/// **唯一的「有哪些交易所」清单。**
///
/// 接第三家交易所：在 `KanpanNetwork/Sources/KanpanNetwork/<交易所>/` 建它的提供者，
/// 在这里 `all` 里加一行，服务端加一条透传。除此之外任何一层都不该出现那家交易所的
/// 名字（`Tools/check-venue-isolation.sh` 守着）。见 `docs/多交易所-接入指南.md`。
public enum VenueRegistry {
  public static let binance = VenueDescriptor(
    id: BinanceProvider.venue, market: BinanceProvider.market, displayName: "币安",
    searchTag: nil, hasFavoriteCategory: false, joinsSectors: true, defaultSymbol: "BTCUSDT",
    makeOwn: { policy, endpoints, log in
      BinanceProvider(upstream: .binance, hosts: BinanceProvider.hosts(endpoints), policy: policy, log: log)
    }
  ) { policy, endpoints, log in
    BinanceProvider(upstream: BinanceProvider.upstream(for: policy),
                    hosts: BinanceProvider.hosts(endpoints), policy: policy, log: log)
  }

  /// 注册顺序就是自选分类条、设置里出现的顺序。第一家是默认交易所。
  public static let all: [VenueDescriptor] = [binance]

  /// 默认交易所：没带交易所前缀的旧数据（裸符号）一律归它，用户自定义域名也只作用于它。
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

  /// 默认交易所的出厂 REST / 推送域名（设置页「自定义域名」的出厂值）。
  public static var defaultRestHost: String { BinanceProvider.defaultRestHost }
  public static var defaultStreamHost: String { BinanceProvider.defaultStreamHost }
  /// 冷启动热身时对默认交易所 REST 域名打的那条最轻的无鉴权请求（只为走通 DNS + TLS）。
  public static var defaultWarmPath: String { BinanceProvider.warmPath }
  /// 默认交易所该迁走的旧推送域名（存过它们的设备换回出厂值）。
  public static var legacyStreamHosts: [String] { BinanceProvider.legacyStreamHosts }
}
