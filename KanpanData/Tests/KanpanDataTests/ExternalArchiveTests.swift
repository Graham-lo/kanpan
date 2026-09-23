import Foundation
import Testing
@testable import KanpanData
import KanpanNetwork
import KanpanCore

@Suite("外部指标归档：列保留与格式升级")
struct ExternalArchiveTests {
  @Test("四个比率经过日片、聚合片、网关 JSON 均不丢失")
  func columns() throws {
    let day: Int64 = 1_735_689_600_000
    let rows = [OIPoint(time: day, value: 123, topTraderAccountRatio: 1.1,
      topTraderPositionRatio: 1.2, accountRatio: 0.8, takerVolumeRatio: 1.3),
      OIPoint(time: day + 300_000, value: 124, accountRatio: 0.9)]
    #expect(OIArchive.decodeSlice(OIArchive.encodeSlice(rows, dayStartMs: day)) == rows)
    #expect(OIArchive.decodeRange(OIArchive.encodeRange(rows, from: day, to: day + 600_000))?.points == rows)
    let wire = Data("[[1735689600000,123,1.1,1.2,0.8,1.3],[1735689900000,124,null,null,0.9,null]]".utf8)
    #expect(try OISource.decodeGateway(wire) == rows)
    #expect(try OISource.decodeGateway(Data("[[1735689600000,123]]".utf8)) == [OIPoint(time: day, value: 123)])
    #expect(throws: (any Error).self) {
      try OISource.decodeGateway(Data("[[1735689600000,123]]".utf8), requireMetrics: true)
    }
    #expect(OISource.downsample(rows, to: .h1).first?.accountRatio == 0.9)
    #expect(OISource.downsample(rows, to: .h1).first?.value == 124)
  }

  @Test("旧 magic 必须未命中，不把没有比率的缓存当新格式")
  func oldMagicMisses() {
    var slice = OIArchive.encodeSlice([OIPoint(time: 0, value: 1)], dayStartMs: 0)
    slice[0] = 0x31
    #expect(OIArchive.decodeSlice(slice) == nil)
    var range = OIArchive.encodeRange([OIPoint(time: 0, value: 1)], from: 0, to: 300_000)
    range[0] = 0x32
    #expect(OIArchive.decodeRange(range) == nil)
  }
}

@Suite("外部指标：近期和历史取数")
struct ExternalSourceTests {
  @Test("近期三个端点各用自己的值，主动买卖比不冒用未完成统计桶")
  func recent() async throws {
    let now: Int64 = 1_800_000_000_000
    let transport = MetricsTransport(now: now)
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let source = OISource(rest: BinanceREST(transport: transport), transport: transport, store: OIStore(paths: paths))
    let ratio = await source.fetchMetric(.lsr, symbol: "BTCUSDT", interval: .m5, from: now - 600_000, to: now, now: now)
    let taker = await source.fetchMetric(.taker, symbol: "BTCUSDT", interval: .m5, from: now - 600_000, to: now, now: now)
    let basis = await source.fetchMetric(.basis, symbol: "BTCUSDT", interval: .m5, from: now - 600_000, to: now, now: now)
    #expect(ratio.complete && taker.complete && basis.complete)
    #expect(ratio.points.first?.value == 0.8)
    #expect(taker.points == [OIPoint(time: now - 300_000, value: 1.2)])
    #expect(basis.points.first?.value == -0.03)
  }

  @Test("多空比历史取账户列，主动买卖比取成交列，基差不会请求远期归档")
  func history() async {
    let now: Int64 = 1_800_000_000_000
    let time = now - 60 * 86_400_000
    let transport = MetricsTransport(now: now)
    let paths = Paths(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let source = OISource(hosts: BinanceHosts(oiProxy: "fixture.example"), rest: BinanceREST(transport: transport),
                          transport: transport, store: OIStore(paths: paths))
    let ratio = await source.fetchMetric(.lsr, symbol: "BTCUSDT", interval: .m5, from: time, to: time + 600_000, now: now)
    let taker = await source.fetchMetric(.taker, symbol: "BTCUSDT", interval: .m5, from: time, to: time + 600_000, now: now)
    #expect(ratio.points.first?.value == 0.7)
    #expect(taker.points.first?.value == 1.4)
    let before = await transport.count
    let basis = await source.fetchMetric(.basis, symbol: "BTCUSDT", interval: .m5, from: time, to: time + 600_000, now: now)
    #expect(basis.complete && basis.points.isEmpty)
    #expect(await transport.count == before)
  }

  private actor MetricsTransport: HTTPTransport {
    let now: Int64
    private(set) var count = 0
    init(now: Int64) { self.now = now }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      count += 1
      let body: String
      switch url.lastPathComponent {
      case "globalLongShortAccountRatio": body = "[{\"longShortRatio\":\"0.8\",\"timestamp\":\(now - 300_000)}]"
      case "takerlongshortRatio": body = "[{\"buySellRatio\":\"1.2\",\"timestamp\":\(now - 300_000)},{\"buySellRatio\":\"9\",\"timestamp\":\(now)}]"
      case "basis": body = "[{\"basis\":\"-3\",\"basisRate\":\"-0.0003\",\"timestamp\":\(now - 300_000)}]"
      default: body = "[[\(now - 60 * 86_400_000),123,8,9,0.7,1.4]]"
      }
      return HTTPReply(status: 200, headers: [:], body: Data(body.utf8))
    }
  }
}
