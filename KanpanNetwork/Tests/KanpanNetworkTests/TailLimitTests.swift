import Foundation
import Testing
@testable import KanpanNetwork
import KanpanNetworkTestSupport
import KanpanCore

@Suite("补缺按需：一根就别拉一千五")
struct TailLimitTests {
  private let t0: Int64 = 1_700_000_000_000

  @Test("还在同一根上：拉下限 5 根，不是 1500")
  func sameCandle() {
    // 末根开在 t0，现在才过了 10 秒（1m 周期还没换根）：只需要刷新这一根。
    let n = BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 10_000)
    #expect(n == 5)
    #expect(n < BinanceREST.maxKlines)
  }

  @Test("缺几十根就拉几十根，带 2 根余量")
  func dozens() {
    // 走开了 40 分钟，1m 周期欠 41 根（含末根自己），余量 2 → 43。
    #expect(BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 40 * 60_000) == 43)
    // 同样 40 分钟，5m 周期只欠 9 根 → 11。
    #expect(BinanceREST.tailLimit(interval: .m5, from: t0, now: t0 + 40 * 60_000) == 11)
  }

  @Test("断了很久还是顶到一页 1500，翻页逻辑不受影响")
  func longGap() {
    let n = BinanceREST.tailLimit(interval: .m1, from: t0, now: t0 + 5 * 86_400_000)
    #expect(n == BinanceREST.maxKlines)
  }

  @Test("时钟倒挂也不会算出负数")
  func skew() {
    #expect(BinanceREST.tailLimit(interval: .h1, from: t0, now: t0 - 86_400_000) == 5)
  }
}
