import Foundation
import Testing
import KanpanCore
import ReviewDomain
import ReviewData
@testable import ReviewUI

/// 复盘本缩略图：画过的存盘，下次打开（新的一页、新的一次启动）先从盘上翻，不再请宿主画；
/// 打开复盘本时一次预热（体感优化 2026-10-07）。
@MainActor struct TradeThumbnailCacheTests {
  let hour: Int64 = 3_600_000
  let monday: Int64 = 1_789_948_800_000
  let thumb = CGSize(width: 72, height: 44)

  func round(_ n: Int, open: Bool = false) -> TradeRound {
    let opened = monday + Int64(n) * hour
    return TradeRound(id: String(format: "00000000-0000-8000-8000-%012d", n), venue: "binance", market: "usd_m",
               symbol: "BTCUSDT", accountTag: "primary", positionSide: .both, direction: .long,
               status: open ? .open : .closed, quoteAsset: "USDT", openedAt: opened, closedAt: open ? nil : opened + hour,
               holdingMs: open ? nil : hour, openAvgPrice: 100, closeAvgPrice: open ? nil : 101, openedQty: 1, closedQty: 1,
               maxQty: 1, peakNotional: 100, leverage: 5, realizedPnl: 1, commission: 0, commissionByAsset: [:],
               commissionUnpriced: false, funding: 0, netPnl: 1, fills: [], updatedAt: 1)
  }

  final class Painter {
    var calls = 0
  }

  func feature(root: URL, profile: URL, painter: Painter) -> TradeReviewFeature {
    let f = TradeReviewFeature()
    f.activate(directory: profile, client: nil)
    f.imageCacheRoot = root
    f.chartImage = { round, _, _ in painter.calls += 1; return Data(round.id.utf8) }
    return f
  }

  @Test func paintedThumbnailComesBackFromDiskWithoutRepainting() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString)")
    let profile = root.appendingPathComponent("profile")
    defer { try? FileManager.default.removeItem(at: root) }
    let painter = Painter()
    let first = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    let r = round(1)
    await first.loadImage(r, spec: nil, size: thumb)
    #expect(painter.calls == 1)
    #expect(first.image(r, size: thumb) == Data(r.id.utf8))

    // 新的一页（等同重启）：盘上有，就不再请宿主画。
    let second = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    await second.loadImage(r, spec: nil, size: thumb)
    #expect(painter.calls == 1)
    #expect(second.image(r, size: thumb) == Data(r.id.utf8))
  }

  @Test func openRoundsAndBigImagesAreNotStored() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString)")
    let profile = root.appendingPathComponent("profile")
    defer { try? FileManager.default.removeItem(at: root) }
    let painter = Painter()
    let first = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    await first.loadImage(round(1, open: true), spec: nil, size: thumb)
    await first.loadImage(round(2), spec: nil, size: CGSize(width: 360, height: 220))
    let second = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    await second.loadImage(round(1, open: true), spec: nil, size: thumb)
    await second.loadImage(round(2), spec: nil, size: CGSize(width: 360, height: 220))
    #expect(painter.calls == 4)
  }

  @Test func prewarmReadsDiskOnceThenPaintsTheFirstFew() async {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("tt-\(UUID().uuidString)")
    let profile = root.appendingPathComponent("profile")
    defer { try? FileManager.default.removeItem(at: root) }
    let painter = Painter()
    let rounds = (1...30).map { round($0) }
    let first = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    first.setLocalRounds(rounds)
    await first.prewarmThumbnails(size: thumb)
    #expect(painter.calls == TradeReviewFeature.prewarmCount)

    let second = feature(root: root.appendingPathComponent("images"), profile: profile, painter: painter)
    second.setLocalRounds(rounds)
    let before = second.imageVersion
    await second.prewarmThumbnails(size: thumb)
    #expect(painter.calls == TradeReviewFeature.prewarmCount)   // 全从盘上来
    #expect(second.imageVersion > before)
    #expect(second.items.prefix(TradeReviewFeature.prewarmCount).allSatisfy { second.image($0.round, size: thumb) != nil })
  }

  @Test func sameImageIsNotPaintedTwiceConcurrently() async {
    let painter = Painter()
    let f = TradeReviewFeature()
    f.chartImage = { round, _, _ in
      painter.calls += 1
      try? await Task.sleep(nanoseconds: 30_000_000)
      return Data(round.id.utf8)
    }
    let r = round(1)
    async let a: Void = f.loadImage(r, spec: nil, size: thumb)
    async let b: Void = f.loadImage(r, spec: nil, size: thumb)
    _ = await (a, b)
    #expect(painter.calls == 1)
  }
}
