import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport

// 压测 · 并发竞速下的网关冷却账本：谁的消息新按谁记。
//
// 两台网关 a / b。b 每次都回 503；a 第 1、2 笔各挂在自己的闸门上，放行时按用例给「成功」或「超时」。
// 两笔竞速一前一后发出、收尾顺序交错，第三笔看 a 还能不能用。

private actor TwoGateways: HTTPTransport {
  enum Outcome { case ok, timeout }
  let first = Gate(), second = Gate()
  private var outcomes: [Int: Outcome] = [:]
  private(set) var aCalls = 0
  private(set) var bCalls = 0

  func set(_ call: Int, _ outcome: Outcome) { outcomes[call] = outcome }

  func get(_ url: URL, timeout: TimeInterval) async throws -> HTTPReply {
    if url.host == "b.test" {
      bCalls += 1
      return json(#"{"error":"unavailable"}"#, status: 503)
    }
    aCalls += 1
    let call = aCalls
    if call == 1 { await first.wait() }
    if call == 2 { await second.wait() }
    if outcomes[call] == .timeout { throw URLError(.timedOut) }
    return json(#"{"source":"okx","symbol":"BTCUSDT","interval":"1m","bars":[]}"#)
  }
}

@Suite("压测 · 并发竞速下的网关冷却账本")
struct StressGatewayLedgerTests {
  let url = URL(string: "https://fapi.binance.com/fapi/v1/klines?symbol=BTCUSDT&interval=1m&limit=300")!

  /// 第一笔先发、后收尾并赢在 a；第二笔后发、先收尾且两台都失败（先给 a 记了冷却）。
  @Test("先失败的那场给 a 记了冷却，a 随后在另一场赢了：冷却清掉，下一笔照常走 a", .timeLimit(.minutes(1)))
  func winnerClearsItsOwnCooldown() async throws {
    let net = TwoGateways()
    await net.set(1, .ok)
    await net.set(2, .timeout)
    let transport = MarketRESTTransport(source: .okx, gateways: ["a.test", "b.test"], transport: net)
    let r1 = Task { try await transport.get(url, timeout: 10) }
    #expect(await waitUntil(5) { await net.first.arrived == 1 })
    let r2 = Task { try await transport.get(url, timeout: 10) }
    #expect(await waitUntil(5) { await net.second.arrived == 1 })
    await net.second.open()
    #expect((try? await r2.value)?.status != 200, "第二笔两台都不行")
    await net.first.open()
    #expect((try? await r1.value)?.status == 200, "第一笔赢在 a")
    let third = try? await transport.get(url, timeout: 10)
    let aCalls = await net.aCalls
    #expect(third?.status == 200, "a 刚赢过，不能还挂着那场失败留下的冷却")
    #expect(aCalls == 3)
  }

  /// 第一笔先发、后收尾且两台都失败；第二笔后发、先收尾并赢在 a。
  @Test("一场没有赢家的竞速途中 a 在另一场赢了：这场的失败不给 a 记冷却", .timeLimit(.minutes(1)))
  func staleFailureDoesNotCoolARecentWinner() async throws {
    let net = TwoGateways()
    await net.set(1, .timeout)
    await net.set(2, .ok)
    let transport = MarketRESTTransport(source: .okx, gateways: ["a.test", "b.test"], transport: net)
    let r1 = Task { try await transport.get(url, timeout: 10) }
    #expect(await waitUntil(5) { await net.first.arrived == 1 })
    let r2 = Task { try await transport.get(url, timeout: 10) }
    #expect(await waitUntil(5) { await net.second.arrived == 1 })
    await net.second.open()
    #expect((try? await r2.value)?.status == 200, "第二笔赢在 a")
    await net.first.open()
    #expect((try? await r1.value)?.status != 200, "第一笔两台都不行")
    let third = try? await transport.get(url, timeout: 10)
    let aCalls = await net.aCalls
    #expect(third?.status == 200, "a 在那场竞速途中赢过，那场的失败是旧消息")
    #expect(aCalls == 3)
  }
}
