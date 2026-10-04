import Foundation
import Testing
import ReviewDomain
import ReviewData
@testable import ReviewUI

/// 详情页去服务端补图：断网 / 超时这类暂时性失败不能把这条记成「服务端没有」，
/// 回到有网的地方再点开要能补回来；服务端明确说没有（404）才这一程不再问。
@MainActor struct ReviewShotRetryTests {
  @MainActor final class Gate {
    var failure: (any Error)?
    var shotRequests = 0
  }

  private func validDraft() -> ReviewDraft {
    let step: Int64 = 3_600_000
    let end = (ReviewClock.now / step) * step
    let range = ReviewRange(symbol: "BTCUSDT", interval: "1h", start: end - step * 48, end: end, bars: 48)
    return ReviewDraft(range: range, reference: 100, high: 110, low: 90, now: ReviewClock.now)
  }

  private func settle(_ feature: ReviewFeature) async {
    for _ in 0..<600 {
      await Task.yield()
      if !feature.syncing { return }
      try? await Task.sleep(for: .milliseconds(5))
    }
  }

  @Test func transientShotFailureIsRetriedNextTime() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shot-retry-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let server = FakeReviewServer()
    let first = ReviewFeature()
    first.activate(store: try ReviewStore(directory: directory.appendingPathComponent("account")),
                   client: ScorebookClient(transport: server.transport))
    let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 7, 8, 9])
    first.captureShot = { bytes }
    let draft = validDraft()
    first.begin(draft)
    #expect(first.saveRecord())
    await settle(first)
    #expect(server.shots[draft.id] == bytes)

    // 换一台设备，要图那一下先断网。
    let gate = Gate()
    gate.failure = URLError(.notConnectedToInternet)
    let transport = server.transport
    let second = ReviewFeature()
    second.activate(store: try ReviewStore(directory: directory.appendingPathComponent("other")),
                    client: ScorebookClient(transport: { path, method, body, key in
                      if path.hasSuffix("/shot") {
                        let failure = await MainActor.run { () -> (any Error)? in gate.shotRequests += 1; return gate.failure }
                        if let failure { throw failure }
                      }
                      return try await transport(path, method, body, key)
                    }))
    await second.loadHistory()
    await second.loadShot(draft.id)
    #expect(second.shot(draft.id) == nil)
    #expect(gate.shotRequests == 1)

    // 网回来了，再点开同一条：得真的再去要，而且要到。
    gate.failure = nil
    await second.loadShot(draft.id)
    #expect(gate.shotRequests == 2, "暂时性失败不能把这张图记成「服务端没有」")
    #expect(second.shot(draft.id) == bytes)
  }

  @Test func onlyServerRefusalCountsAsGone() {
    #expect(!ReviewFeature.shotIsGone(after: URLError(.timedOut)))
    #expect(!ReviewFeature.shotIsGone(after: ScorebookError.http(503, "")))
    #expect(ReviewFeature.shotIsGone(after: ScorebookError.http(404, "not_found")))
  }
}
