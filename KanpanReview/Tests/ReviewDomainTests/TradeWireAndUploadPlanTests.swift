import Foundation
import Testing
import KanpanCore
import ReviewDomain

/// 审查 R11 / R18：上传计划只传「比服务端那份新」的回合；服务端回写的数字形态十进制不丢精度。
struct TradeWireAndUploadPlanTests {
  private func round(_ n: Int, updated: Int64) -> TradeRound {
    TradeReviewModelsTests.round(n, opened: Int64(n) * 1_000, closed: Int64(n) * 1_000 + 500, updated: updated)
  }

  /// 另一台设备传上去的版本更新：拉列表把 `uploaded` 抬到了 20，本机这份还是 15。
  /// 以前按「不同」判就永远是待传，每次进复盘都重传一遍旧的。
  @Test func olderLocalRoundNotPending() {
    let stale = round(1, updated: 15), same = round(2, updated: 20), fresh = round(3, updated: 25)
    let todo = TradeUploadPlan.pending([stale, same, fresh], uploaded: [stale.id: 20, same.id: 20, fresh.id: 20])
    #expect(todo.map(\.id) == [fresh.id])
  }

  /// 被拒过更新的一版，本机更旧的那一版也不再试；本机有了比被拒那版还新的才再试。
  @Test func rejectedNewerVersionBlocksOlderLocal() {
    let older = round(1, updated: 5), newer = round(2, updated: 9)
    let todo = TradeUploadPlan.pending([older, newer], uploaded: [:], rejected: [older.id: 7, newer.id: 7])
    #expect(todo.map(\.id) == [newer.id])
  }

  /// 服务端回写给的是数字（不是字符串）时，`0.1` 要读成十进制的 0.1，不是先过一道 Double 的
  /// `0.1000000000000000512`。
  @Test func numericDecimalsDecodeLosslessly() throws {
    let json = #"{"at":1,"price":0.1,"changePct":-0.012345678901234567}"#
    let point = try JSONDecoder().decode(TradeAfterPoint.self, from: Data(json.utf8))
    #expect(point.price == Decimal(string: "0.1"))
    #expect(point.changePct == Decimal(string: "-0.012345678901234567"))
    let excursion = #"{"maxFavorable":64123.37,"maxFavorablePct":0.3,"maxFavorableAt":null,"maxAdverse":-0.07,"maxAdversePct":-0.0001,"maxAdverseAt":null,"rewardRisk":null}"#
    let value = try JSONDecoder().decode(TradeExcursion.self, from: Data(excursion.utf8))
    #expect(value.maxFavorable == Decimal(string: "64123.37"))
    #expect(value.maxAdverse == Decimal(string: "-0.07"))
    #expect(value.rewardRisk == nil)
  }
}
