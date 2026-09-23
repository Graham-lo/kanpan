import Foundation
import KanpanCore
import KanpanNetwork
@testable import KanpanData

// 这批用例早于「提供者」那一层，手里握着的是币安的 REST / WS 假件。
// 把它们包成 `BinanceProvider` 再交给上层，用例本身不用逐个改写。

extension BinanceProvider {
  /// 用一个现成的 REST 客户端（多半带着假的 transport）建一个币安本家的提供者。
  static func wrapping(_ rest: BinanceREST, upstream: BinanceUpstream = .binance,
                       policy: MarketRoutePolicy = .direct) -> BinanceProvider {
    BinanceProvider(upstream: upstream, hosts: rest.hosts, policy: policy, rest: rest)
  }
}

extension MarketFeed {
  init(rest: BinanceREST, ws: BinanceWS, cache: BarCache = BarCache(),
       paths: Paths = .caches(), pacer: Pacer = SystemPacer(),
       clock: @escaping @Sendable () -> Date = { Date() },
       reconcileMs: Double = 5000, includeTicker: Bool = true,
       initialLimit: Int = BinanceREST.maxKlines, log: FeedLog = .silent) {
    self.init(provider: BinanceProvider.wrapping(rest), stream: ws, cache: cache, paths: paths,
              pacer: pacer, clock: clock, reconcileMs: reconcileMs, includeTicker: includeTicker,
              initialLimit: initialLimit, log: log)
  }
}

extension SymbolCatalog {
  init(rest: BinanceREST, paths: Paths = .caches(), log: FeedLog = .silent) {
    self.init(provider: BinanceProvider.wrapping(rest), paths: paths, log: log)
  }
}

extension OISource {
  init(hosts: BinanceHosts = .default, rest: BinanceREST,
       transport: HTTPTransport = URLSessionTransport(),
       store: OIStore, log: FeedLog = .silent) {
    self.init(provider: BinanceProvider.wrapping(rest), gateways: hosts.oiProxies,
              transport: transport, store: store, log: log)
  }
}

extension RoutedMarketFeed {
  /// 老用例的注入口：`primary` 是币安本家的 REST，`backup` 是网关上替身的 REST。
  init(hosts: BinanceHosts, paths: Paths, log: FeedLog = .silent,
       primary: BinanceREST, backup: BinanceREST, sockets: any WSSocketFactory,
       policy: MarketRoutePolicy) {
    self.init(paths: paths, log: log, policy: policy) { _, policy in
      let upstream = BinanceProvider.upstream(for: MarketRoute(policy: policy, endpoints: .production))
      return BinanceProvider(upstream: upstream, hosts: hosts, policy: policy,
                             rest: upstream == .binance ? primary : backup, sockets: sockets, log: log)
    }
  }
}

extension CompareFeed {
  /// 老用例的注入口：一家币安本家（带假 transport 的 REST）+ 一条假推送。
  /// 别的交易所一律「认不出」，正好守住「别家的 key 不许向币安冒领行情」。
  init(rest: BinanceREST, ws: BinanceWS, pacer: any Pacer = SystemPacer()) {
    let binance = BinanceProvider.wrapping(rest)
    self.init(provider: { venue in venue == BinanceProvider.venue ? binance : nil }, stream: ws, pacer: pacer)
  }
}
