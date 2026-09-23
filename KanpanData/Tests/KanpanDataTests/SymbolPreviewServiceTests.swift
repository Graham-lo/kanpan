import Foundation
import Testing
import KanpanCore
import KanpanData
import KanpanNetwork

/// 预览卡取数挪进数据层之后（审查 18a）：它只认交进来的线路，不自己拼主机。
@Suite("预览卡取数跟着线路走")
struct SymbolPreviewServiceTests {

  @Test("网关线路、网关表空着：一笔都不往交易所发，K 线空、费率 nil")
  func gatewayWithoutHostsNeverDialsTheExchange() async {
    let lines = LogLines()
    let resolver = RouteResolver(policy: .gateway, endpoints: .default, log: FeedLog { lines.add($0) })
    let service = SymbolPreviewService(resolver: resolver)
    let started = Date()
    #expect(await service.bars(for: "BTCUSDT").isEmpty)
    #expect(await service.funding(for: "BTCUSDT") == nil)
    // 没有候选就直接跳过，不会去等一次超时。
    #expect(Date().timeIntervalSince(started) < 2)
    #expect(lines.all.contains { $0.contains("预览卡 K 线取不到") }, "取不到要留一行日志，不静默吞掉")
  }

  @Test("上游跟线路：直连是交易所本家，网关是网关上的那一路")
  func capabilitiesFollowRoute() {
    let direct = SymbolPreviewService(resolver: RouteResolver(policy: .direct, endpoints: .production))
    let gateway = SymbolPreviewService(resolver: RouteResolver(policy: .gateway, endpoints: .production))
    let key = VenueRegistry.default.defaultSymbol
    #expect(direct.capabilities(for: key).upstream
            == RouteResolver(policy: .direct, endpoints: .production).provider(forSymbol: key).capabilities.upstream)
    #expect(gateway.capabilities(for: key).upstream
            == RouteResolver(policy: .gateway, endpoints: .production).provider(forSymbol: key).capabilities.upstream)
  }
}

private final class LogLines: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []
  func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
  var all: [String] { lock.lock(); defer { lock.unlock() }; return items }
}
