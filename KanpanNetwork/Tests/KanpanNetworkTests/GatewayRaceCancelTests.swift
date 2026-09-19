import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 网关竞速的记账（谁是首选、输家歇多久）只有在「这一轮还算数」的时候才该写。
// 一笔请求在竞速途中被取消（换品种、换周期、上一份 feed 被停掉），或者用户刚换了
// 行情线路，这一轮的胜负就和下一笔无关了——照样记账的话，下一笔首屏会被一条
// 10 秒的冷却挡在门外，而那条冷却是凭一场没人要的竞速记下来的。
@Suite("网关竞速：取消与换线路之后不许污染路由账本")
struct GatewayRaceCancelTests {
  let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

  /// 慢的那台挂在闸门上，**不理会任务取消**——真网络回包就是这样：
  /// 上层把任务取消了，回包该来还是会来，竞速那一头还得等它退场。
  actor SlowGateway: HTTPTransport {
    let gate: Gate
    private(set) var hosts: [String] = []
    init(gate: Gate) { self.gate = gate }
    func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
      hosts.append(url.host ?? "")
      if url.host == "slow.test" { await gate.wait() }
      return json(#"{"source":"okx","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
    }
    func hits(_ host: String) -> Int { hosts.filter { $0 == host }.count }
  }

  @Test("BT-07 竞速途中这一笔被取消：不许给输家记冷却，下一笔照样两台一起发", .timeLimit(.minutes(1)))
  func cancelledRaceDoesNotCoolDownLosers() async throws {
    let gate = Gate()
    let net = SlowGateway(gate: gate)
    let transport = MarketRESTTransport(source: .okx, gateways: ["fast.test", "slow.test"], transport: net)

    let job = Task { try await transport.get(url, timeout: 10) }
    // 快的已经赢了，慢的还挂在闸门上：竞速正卡在「等输家退场」那一步。
    #expect(await waitUntil(5) { await gate.arrived > 0 })
    job.cancel()
    await gate.open()
    _ = try? await job.value

    // 第二笔是全新的一笔（没被取消）：两台都该被打到。
    _ = try? await Task { try await transport.get(url, timeout: 10) }.value
    #expect(await net.hits("slow.test") == 2)
    #expect(await net.hits("fast.test") == 2)
  }

  @Test("换线路之后，上一档竞速的结果不许再写进路由账本", .timeLimit(.minutes(1)))
  func policyChangeDuringRaceDoesNotCoolDownLosers() async throws {
    let gate = Gate()
    let net = SlowGateway(gate: gate)
    let transport = MarketRESTTransport(source: .okx, gateways: ["fast.test", "slow.test"], transport: net)

    let job = Task { try await transport.get(url, timeout: 10) }
    #expect(await waitUntil(5) { await gate.arrived > 0 })
    // 用户这会儿把线路按到另一档：`setPolicy` 会清冷却，而这一轮竞速还在路上。
    await transport.setPolicy(.gateway)
    await gate.open()
    _ = try? await job.value

    _ = try? await Task { try await transport.get(url, timeout: 10) }.value
    #expect(await net.hits("slow.test") == 2)
  }
}
