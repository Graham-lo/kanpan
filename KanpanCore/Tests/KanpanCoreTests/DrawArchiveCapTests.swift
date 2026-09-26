import Foundation
import Testing

@testable import KanpanCore

/// 进门的上限（压测收尾 2026-09-26 第 10 项）：同步 / 收件箱带进来的线按每品种上限裁，丢最老的。
@Suite("画线 · 进门上限")
struct DrawArchiveCapTests {
  private func lines(_ count: Int, prefix: String) -> [Drawing] {
    (0..<count).map { Drawing(id: "\(prefix)\($0)", kind: .hline, points: [DrawPoint(t: 1, p: Double($0))]) }
  }

  @Test("300 条的桶裁到 50 条，留数组尾上最新的；不满的桶一根不动；返回每只丢了几条")
  func capKeepsNewest() {
    var archive = DrawArchive()
    archive["binance/usd_m/BTCUSDT"] = lines(300, prefix: "b")
    archive["binance/usd_m/ETHUSDT"] = lines(50, prefix: "e")
    archive["binance/usd_m/SOLUSDT"] = lines(3, prefix: "s")
    let before = archive.bySymbol.values.reduce(0) { $0 + $1.count }
    let dropped = archive.capToLimit()
    let after = archive.bySymbol.values.reduce(0) { $0 + $1.count }
    print("[压测收尾·画线进门上限] BTC 桶 300 → \(archive["binance/usd_m/BTCUSDT"].count)；全档 \(before) → \(after)")
    #expect(dropped == [InstrumentID.canonical("binance/usd_m/BTCUSDT"): 250])
    #expect(archive["binance/usd_m/BTCUSDT"].map(\.id) == (250..<300).map { "b\($0)" })
    #expect(archive["binance/usd_m/ETHUSDT"].count == 50)
    #expect(archive["binance/usd_m/SOLUSDT"].count == 3)
    // 裁完再裁不再动。
    #expect(archive.capToLimit().isEmpty)
  }

  @Test("一串线的最新 50 条")
  func newestSuffix() {
    #expect(DrawArchive.newest(lines(51, prefix: "x")).map(\.id) == (1..<51).map { "x\($0)" })
    #expect(DrawArchive.newest(lines(7, prefix: "x")).count == 7)
  }
}

@Suite("画线 · 进门上限按年龄")
struct DrawArchiveCapAgeTests {
  @Test("有年龄的按年龄丢最老、没年龄的算最新；留下的保持桶里先后；重复裁不换批")
  func capByAge() {
    let lines = (0..<80).map { Drawing(id: "x\($0)", kind: .hline, points: [DrawPoint(t: 1, p: Double($0))]) }
    // 年龄和数组位置反着来：头上的最新。最后 5 条没年龄（本机刚画、云端没确认）。
    func age(_ d: Drawing) -> DrawArchive.Age? {
      let n = Int(d.id.dropFirst())!
      return n >= 75 ? nil : DrawArchive.Age(timestamp: Int64(1_000 - n), logical: 0)
    }
    var a = DrawArchive(); a["BTCUSDT"] = lines
    #expect(a.capToLimit(age: age) == [InstrumentID.canonical("BTCUSDT"): 30])
    #expect(a["BTCUSDT"].map(\.id) == (0..<45).map { "x\($0)" } + (75..<80).map { "x\($0)" })
    // 裁过的桶后面再追加被裁掉的那几条（同步下一次应用就是这样），再裁：还是同一批。
    let kept = a["BTCUSDT"]
    a["BTCUSDT"] += lines.filter { !kept.contains($0) }.reversed()
    a.capToLimit(age: age)
    #expect(a["BTCUSDT"] == kept)
  }
}
