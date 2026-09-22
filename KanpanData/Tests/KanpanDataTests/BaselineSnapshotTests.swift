import Foundation
import Testing
@testable import KanpanData
import KanpanNetworkTestSupport

@Suite("当日开盘价快照")
struct BaselineSnapshotTests {

  private func tempPaths() -> Paths {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("kanpan-opens-\(UUID().uuidString)")
    let p = Paths(root: dir)
    try? p.ensureRoot()
    return p
  }

  @Test("同一档边界读得回来，涨跌幅第一帧就能算")
  func roundTrip() {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let boundary: Int64 = 1_700_000_000_000
    BaselineSnapshot.write(boundary: boundary, opens: ["BTCUSDT": 78_000, "ETHUSDT": 4_100], to: p.opens)

    let back = BaselineSnapshot.read(p.opens, boundary: boundary)
    #expect(back.count == 2)
    #expect(back["binance/usd_m/BTCUSDT"] == 78_000)
    #expect(back["binance/usd_m/ETHUSDT"] == 4_100)
  }

  @Test("跨到下一天就整份作废，不拿昨天的开盘价算今天")
  func staleBoundaryIsDropped() {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let boundary: Int64 = 1_700_000_000_000
    BaselineSnapshot.write(boundary: boundary, opens: ["BTCUSDT": 78_000], to: p.opens)
    #expect(BaselineSnapshot.read(p.opens, boundary: boundary + 86_400_000).isEmpty)
  }

  @Test("非法值不落盘；一个都不剩时文件删掉")
  func rejectsGarbage() {
    let p = tempPaths()
    defer { try? FileManager.default.removeItem(at: p.root) }

    let boundary: Int64 = 1_700_000_000_000
    BaselineSnapshot.write(boundary: boundary, opens: ["BTCUSDT": 78_000, "BADUSDT": 0, "NANUSDT": .nan], to: p.opens)
    let back = BaselineSnapshot.read(p.opens, boundary: boundary)
    #expect(back.count == 1)
    #expect(back["binance/usd_m/BTCUSDT"] == 78_000)

    BaselineSnapshot.write(boundary: boundary, opens: ["BADUSDT": -1], to: p.opens)
    #expect(BaselineSnapshot.read(p.opens, boundary: boundary).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: p.opens.path))
  }
}
