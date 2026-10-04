import Foundation
import Testing
@testable import KanpanCore

// 「画出来一样」判据的代价（2026-10-04 深度审查 F 线，报告 docs/acceptance/深度审查-2026-10-04/F-性能压测/报告.md）。
//
// 图表 `ChartView.changed(from:to:)` 每次 state 一变就问一次 `OrderFlowSnapshot.sameRender`，甩动、拖动时每帧一次。
// 从前它逐单造 `renderKey`，`renderKey` 里的 `id` 是现拼的「venue|side|bucket|firstSeen」字符串——BTC 1m 两千四百单
// 每帧拼四千八百个字符串，16 Pro 模拟器上甩动采样里 `changed` 占主线程约 8%（4883 / 57725），快照明明没换。
// 这里卡两件事：结论和旧判据一模一样；快照没换时 O(1)，换了也不拼字符串。

@Suite("主力快照「画出来一样」的代价")
struct OrderFlowSameRenderCostTests {
  /// 旧判据原样（逐单 `renderKey ==`），只当参照。
  static func reference(_ a: OrderFlowSnapshot, _ b: OrderFlowSnapshot) -> Bool {
    guard a.symbol == b.symbol, a.phase == b.phase, a.thresholds == b.thresholds, a.defaults == b.defaults,
          a.venues == b.venues, a.orders.count == b.orders.count else { return false }
    return zip(a.orders, b.orders).allSatisfy { $0.renderKey == $1.renderKey }
  }

  static func orders(_ n: Int, seed: UInt64) -> [BigOrder] {
    var rng = StressRNG(seed: seed)
    let venues = ["binance-usdtPerp", "binance-spot", "okx-usdtPerp", "okx-coinPerp", "coinbase-spot"]
    return (0..<n).map { i in
      let threshold = [1_000_000.0, 5_000_000][rng.int(0...1)]
      let live = rng.chance(0.4)
      let first = 1_790_000_000_000 + Int64(i) * 60_000 + Int64(rng.int(0...59_999))
      return BigOrder(venueID: venues[rng.int(0...4)], exchange: "币安", product: .usdtPerp,
                      side: rng.chance(0.5) ? .bid : .ask, bucket: Int64(600_000 + rng.int(0...4000)),
                      price: 60_000 + rng.double(0, 4000), firstSeenMs: first,
                      endMs: live ? nil : first + Int64(rng.int(1...3_600_000)),
                      status: live ? .live : [.filled, .cancelled, .lost][rng.int(0...2)],
                      initialNotional: threshold * rng.double(1, 3), notional: threshold * rng.double(0.5, 20),
                      filledNotional: rng.chance(0.3) ? threshold * rng.double(0, 1) : 0, threshold: threshold)
    }
  }

  static func snapshot(_ orders: [BigOrder]) -> OrderFlowSnapshot {
    OrderFlowSnapshot(symbol: "BTCUSDT", phase: .ready, orders: orders, asOfMs: 1_790_000_000_000)
  }

  /// 同内容、另一块存储（逐单比的那条路）。
  static func detached(_ s: OrderFlowSnapshot) -> OrderFlowSnapshot {
    var c = s
    c.orders = s.orders.map { $0 }
    c.orders.reserveCapacity(c.orders.count + 1)
    return c
  }

  @Test("各种单项变化下结论与旧判据逐条一致")
  func sameVerdictAsRenderKey() {
    let base = Self.orders(600, seed: 41)
    let a = Self.snapshot(base)
    var rng = StressRNG(seed: 97)
    var checked = 0, differing = 0
    for round in 0..<3000 {
      var o = base
      let i = rng.int(0...(o.count - 1))
      switch round % 12 {
      case 0: o[i].notional *= 1.0001  // 同一个四分之一格里抖：画出来一样
      case 1: o[i].notional = o[i].threshold * Double(rng.int(1...80)) / 4  // 换格
      case 2: o[i].filledNotional = o[i].filledNotional > 0 ? 0 : 1
      case 3: o[i].status = o[i].status == .live ? .filled : .live
      case 4: o[i].endMs = (o[i].endMs ?? 0) + 1
      case 5: o[i].price += 0.5
      case 6: o[i].threshold *= 2
      case 7: o[i].firstSeenMs += 1  // id 的组成项
      case 8: o[i].bucket += 1
      case 9: o[i].side = o[i].side == .bid ? .ask : .bid
      case 10: o[i].venueID += "x"
      default: o[i].exchange = "欧易"; o[i].initialNotional += 7  // 不进判据
      }
      let b = Self.snapshot(o)
      let want = Self.reference(a, b)
      #expect(a.sameRender(as: b) == want, "第 \(round) 轮（变化类 \(round % 12)）")
      checked += 1
      if !want { differing += 1 }
    }
    #expect(checked == 3000)
    #expect(differing > 1500)  // 大部分变化类确实是「画出来变了」，判据没有被测成永远 true
    #expect(a.sameRender(as: Self.snapshot(Array(base.dropLast()))) == false)
    #expect(Self.snapshot([]).sameRender(as: Self.snapshot([])))
  }

  @Test("快照没换（同一块存储）时不逐单走：比逐单比快二十倍以上，sameContent 同理")
  func sharedStorageIsConstantTime() {
    let a = Self.snapshot(Self.orders(2430, seed: 7))
    let same = a  // ChartState 拷贝出来的就是这样：值相等、存储同一块
    let other = Self.detached(a)
    #expect(a.sameRender(as: same) && a.sameRender(as: other))
    #expect(a.sameContent(as: same) && a.sameContent(as: other))
    func clock(_ body: () -> Bool) -> Double {
      let t0 = DispatchTime.now().uptimeNanoseconds
      var ok = true
      for _ in 0..<200 { ok = body() && ok }
      #expect(ok)
      return Double(DispatchTime.now().uptimeNanoseconds - t0) / 200
    }
    var shared: [Double] = [], walked: [Double] = [], sharedC: [Double] = [], walkedC: [Double] = []
    for _ in 0..<5 {
      shared.append(clock { a.sameRender(as: same) })
      walked.append(clock { a.sameRender(as: other) })
      sharedC.append(clock { a.sameContent(as: same) })
      walkedC.append(clock { a.sameContent(as: other) })
    }
    let r = shared.min()! / walked.min()!, rc = sharedC.min()! / walkedC.min()!
    print("【F 线】sameRender 2430 单：同存储 \(Int(shared.min()!)) ns / 逐单 \(Int(walked.min()!)) ns（比 \(r)）；sameContent \(Int(sharedC.min()!)) / \(Int(walkedC.min()!)) ns")
    #expect(r < 0.05)
    #expect(rc < 0.05)
  }

  @Test("快照换了逐单比时也不拼字符串：比旧判据快一倍以上")
  func walkingIsCheaperThanRenderKey() {
    let a = Self.snapshot(Self.orders(2430, seed: 11))
    let b = Self.detached(a)
    func clock(_ body: () -> Bool) -> Double {
      let t0 = DispatchTime.now().uptimeNanoseconds
      var ok = true
      for _ in 0..<20 { ok = body() && ok }
      #expect(ok)
      return Double(DispatchTime.now().uptimeNanoseconds - t0) / 20
    }
    var new: [Double] = [], old: [Double] = []
    for _ in 0..<7 {  // 交替量，机器忙闲两边一起受
      new.append(clock { a.sameRender(as: b) })
      old.append(clock { Self.reference(a, b) })
    }
    let r = new.min()! / old.min()!
    print("【F 线】sameRender 2430 单逐单：新 \(Int(new.min()! / 1000)) µs / 旧 \(Int(old.min()! / 1000)) µs（比 \(r)）")
    #expect(r < 0.5)
  }
}
