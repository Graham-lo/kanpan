import Foundation
import Testing
import KanpanCore
import ReviewDomain
import ReviewData

/// 审查 R11：另一台设备把同一个回合传上去过更新的一版，本机这份更旧——以前拉一次列表
/// `uploaded` 被抬成服务端那版，按「不同」判本机旧版就成了待传；传上去之后又把 `uploaded`
/// 记回本机这一版，下次再拉、再判不同、再传，永远停不下来。
@MainActor struct TradeUploadLoopTests {
  private func round(_ n: Int, updated: Int64) -> TradeRound {
    TradeRound(id: String(format: "00000000-0000-8000-8000-%012d", n), venue: "binance", market: "usd_m",
               symbol: "BTCUSDT", accountTag: "primary", positionSide: .both, direction: .long, status: .closed,
               quoteAsset: "USDT", openedAt: Int64(n) * 1_000, closedAt: Int64(n) * 1_000 + 500, holdingMs: 500,
               openAvgPrice: 100, closeAvgPrice: 101, openedQty: 1, closedQty: 1, maxQty: 1, peakNotional: 100,
               leverage: 5, realizedPnl: 1, commission: 0, commissionByAsset: [:],
               commissionUnpriced: false, funding: 0, netPnl: 1, fills: [], updatedAt: updated)
  }

  @Test func olderLocalRoundIsNotReuploadedAfterRefresh() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("trade-loop-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = TradeSyncTests.Server()
    let newer = round(1, updated: 20)
    await server.seed([TradeRecord(id: newer.id, revision: 3, submitted: 1, updated: 1, round: newer)])
    let client = ScorebookClient(transport: { path, method, body, key in try await server.handle(path, method, body, key) })
    let store = TradeReviewStore(directory: directory)
    try await TradeSync.refresh(store: store, client: client)
    #expect(store.archive.uploaded[newer.id] == 20)

    let outcome = await TradeSync.upload([round(1, updated: 15)], store: store, client: client)
    #expect(outcome == .done(0))
    let posts = await server.calls.filter { $0.method == "POST" }
    #expect(posts.isEmpty, "本机更旧的那一版不该再传")
  }

  /// 传成功时只往大里记：`markUploaded` 不会把 `merge` 刚记下的更新版本压回去。
  @Test func markUploadedNeverMovesBackwards() {
    var archive = TradeArchive()
    archive.uploaded["a"] = 30
    archive.rejected["a"] = 12
    var older = round(1, updated: 12); older.id = "a"
    archive.markUploaded(older)
    #expect(archive.uploaded["a"] == 30)
    #expect(archive.rejected["a"] == nil)
  }
}
