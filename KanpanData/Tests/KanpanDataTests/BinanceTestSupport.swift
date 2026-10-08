import Foundation
import KanpanCore
import KanpanNetwork
@testable import KanpanData

// 这批用例早于「提供者」那一层，手里握着的是币安的 REST / WS 假件。
// 把它们包成 `BinanceProvider` 再交给上层，用例本身不用逐个改写。

extension BinanceProvider {
  /// 用一个现成的 REST 客户端（多半带着假的 transport）建一个币安提供者。
  static func wrapping(_ rest: BinanceREST, policy: MarketRoutePolicy = .direct) -> BinanceProvider {
    BinanceProvider(hosts: rest.hosts, policy: policy, rest: rest)
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
  /// 老用例的注入口：`primary` 是直连档用的 REST（打币安本家），`backup` 是网关档用的 REST
  /// （打新加坡那台的透传；2026-10-08 之前它是 OKX 替身，现在同样是币安的数、只是经网关转一道）。
  /// `http` 是直接问网关的那几笔（订单流品种表等）；不给就是真 `URLSessionTransport`——
  /// 会真的去连 `gw.test` 这类假主机，等满超时（审查第 44 项：路由用例 7 秒多就耗在这里）。
  init(hosts: BinanceHosts, paths: Paths, log: FeedLog = .silent,
       primary: BinanceREST, backup: BinanceREST, sockets: any WSSocketFactory,
       http: (any HTTPTransport)? = nil, policy: MarketRoutePolicy) {
    self.init(paths: paths, log: log, policy: policy) { _, policy in
      BinanceProvider(hosts: hosts, policy: policy,
                      rest: policy == .gateway ? backup : primary, sockets: sockets,
                      http: http ?? URLSessionTransport(), log: log)
    }
  }
}

extension CompareFeed {
  /// 老用例的注入口：一家币安本家（带假 transport 的 REST）+ 一条假推送。
  /// 别的交易所一律「认不出」，正好守住「别家的 key 不许向币安冒领行情」。
  init(rest: BinanceREST, ws: BinanceWS, pacer: any Pacer = SystemPacer(), snapshots: Paths? = nil) {
    let binance = BinanceProvider.wrapping(rest)
    self.init(provider: { venue in venue == BinanceProvider.venue ? binance : nil }, stream: ws, pacer: pacer,
              snapshots: snapshots)
  }
}
