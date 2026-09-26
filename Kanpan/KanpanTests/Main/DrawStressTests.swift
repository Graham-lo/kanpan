import Foundation
import Testing
import KanpanCore
import KanpanAccount
@testable import Kanpan

/// 画线存档压测：几千条、每一种工具、极端坐标、并同步并出来超过「每品种 50 条」的桶，
/// 落盘读回、线上往返、坏条目只丢自己。判据全是结构上的（一条不少、一条不多、逐位相等），
/// 耗时只打印进报告，不做断言。
@Suite("画线存档压测：几千条、每种工具、极端坐标、坏条目只丢自己", .serialized)
struct DrawStressTests {
  /// 极端但合法的坐标：远古到远未来的时刻，1e-12 到 1e300 的价位，负价（价差类品种）。
  private static let times: [Double] = [0, 1, 1_700_000_000_000, 4_102_444_800_000, 9.0e15, -62_135_596_800_000]
  private static let prices: [Double] = [1e-12, 0.000_001_23, 64_321.5, 1e300, -3.5, 0]
  private static let captions = ["", "顶背离", String(repeating: "长", count: 60), String(repeating: "👨‍👩‍👧‍👦", count: 60), "a\"b\\c\n\t"]

  private func drawing(_ n: Int) -> Drawing {
    let kind = Drawing.Kind.allCases[n % Drawing.Kind.allCases.count]
    let points = (0..<kind.pointCount).map { i in
      DrawPoint(t: Self.times[(n + i) % Self.times.count], p: Self.prices[(n * 7 + i) % Self.prices.count])
    }
    var item = Drawing(id: "d\(n)-" + UUID().uuidString, kind: kind, points: points)
    item.lineWidth = [0.5, 1.3, 6][n % 3]
    item.dash = Drawing.Dash.allCases[n % Drawing.Dash.allCases.count]
    item.locked = n % 5 == 0; item.hidden = n % 7 == 0; item.filled = n % 2 == 0
    if kind.usesLevels { item.levels = (0..<24).map { Double($0 - 12) * 10 / 12 } }
    if kind.usesText { item.text = Self.captions[n % Self.captions.count] }
    precondition(item.isValid, "造出来的夹具自己得是合法的：\(kind)")
    return item
  }

  /// 200 个品种各 15 条，外加一只 600 条的大桶。存档模型、落盘、`SyncOverlay.drawings` 叠对象这几层
  /// 本身都不裁（老版本会留下这样的盘）；上限在进门那一步由调用方裁（`SyncOverlay.capDrawings`，
  /// 压测收尾第 10 项，见 `SyncOverlayTests`）。
  private func archive() -> DrawArchive {
    var a = DrawArchive()
    var n = 0
    for s in 0..<200 {
      a["S\(s)USDT"] = (0..<15).map { _ in defer { n += 1 }; return drawing(n) }
    }
    a["BTCUSDT"] = (0..<600).map { _ in defer { n += 1 }; return drawing(n) }
    a.preferences.magnet = false
    a.preferences.variants = ["trend": .extended]
    return a
  }

  private func temp() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kanpan-draw-stress-\(UUID().uuidString)", isDirectory: true)
  }

  @Test("3600 条落盘读回逐位相等；再存一次还是同一份字节")
  func thousandsRoundTripThroughDisk() throws {
    let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = DrawStore(url: dir.appendingPathComponent("draws.json"))
    let a = archive()
    #expect(a.bySymbol.values.map(\.count).reduce(0, +) == 3600)
    let t0 = Date()
    try store.save(a)
    let t1 = Date()
    let back = try store.read()
    let t2 = Date()
    #expect(back == a)
    let first = try Data(contentsOf: store.url)
    try store.save(back)                                   // 已有文件：先读一遍守门再写
    let t3 = Date()
    #expect(try Data(contentsOf: store.url).count == first.count)
    #expect(try store.read() == a)
    print(String(format: "DRAW-STRESS bytes=%d firstSave=%.0fms read=%.0fms guardedSave=%.0fms",
                 first.count, t1.timeIntervalSince(t0) * 1000, t2.timeIntervalSince(t1) * 1000, t3.timeIntervalSince(t2) * 1000))
  }

  @Test("每只桶里掺认不出的工具、点数不对、越界、缺字段的条目：只丢那几条，别的一条不少")
  func unknownAndBrokenEntriesDropOnlyThemselves() throws {
    let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = DrawStore(url: dir.appendingPathComponent("draws.json"))
    let a = archive()
    try store.save(a)
    var root = try JSONSerialization.jsonObject(with: Data(contentsOf: store.url)) as! [String: Any]
    var buckets = root["d"] as! [String: [Any]]
    let poison: [[String: Any]] = [
      ["id": "x1", "kind": "telekinesis", "points": [["t": 1, "p": 1]]],          // 以后的版本才有的工具
      ["id": "x2", "kind": "trend", "points": [["t": 1, "p": 1]]],                 // 点数对不上
      ["id": "x3", "kind": "hline", "points": [["t": 1, "p": 1]], "lineWidth": 99], // 线宽越界
      ["id": "x4", "kind": "hline"],                                                // 一个点都没有
      ["id": "x5", "kind": "fibonacci", "points": [["t": 1, "p": 1], ["t": 2, "p": 2]], "levels": Array(repeating: 0.5, count: 25)],
      ["kind": "hline", "points": [["t": 1, "p": 1]]],                              // 没有 id
      ["id": "x7", "kind": "note", "points": [["t": 1, "p": 1]], "text": String(repeating: "字", count: 61)],
    ]
    for key in buckets.keys { buckets[key]!.insert(contentsOf: poison, at: buckets[key]!.count / 2) }
    buckets["ONLYJUNKUSDT"] = poison                                                // 整只桶都是坏的：桶不留
    root["d"] = buckets
    try JSONSerialization.data(withJSONObject: root).write(to: store.url)
    let back = try store.read()
    #expect(back == a, "丢了好的或留了坏的：\(back.bySymbol.values.map(\.count).reduce(0, +)) 条")
    #expect(back[ "ONLYJUNKUSDT"].isEmpty)
    // 读回来的这一份能照常再存（不因为「曾经有坏条目」就再也存不上）。
    try store.save(back)
    #expect(try store.read() == a)
  }

  @Test("比自己新的存档：读抛出、写不覆盖，盘上那份一个字节不动")
  func newerArchiveIsNeverOverwritten() throws {
    let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
    let store = DrawStore(url: dir.appendingPathComponent("draws.json"))
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let future = Data(#"{"v":99,"d":{"binance/usd_m/BTCUSDT":[{"id":"z","kind":"warp","points":[]}]}}"#.utf8)
    try future.write(to: store.url)
    #expect(throws: DrawStore.StoreError.self) { try store.read() }
    #expect(throws: (any Error).self) { try store.save(archive()) }
    #expect(try Data(contentsOf: store.url) == future)
  }

  @Test("3600 条编成同步对象、再从对象铺回空档：逐位还原；乱序、重复、删除都照规矩落")
  func syncCodecRoundTripAtScale() throws {
    let a = archive()
    let objects = try PersonalSyncCodec.drawings(a)
    #expect(objects.count == 3601)                                                   // 3600 条 + 工具偏好一份
    var rebuilt = DrawArchive()
    let t0 = Date()
    SyncOverlay.drawings(objects, onto: &rebuilt)
    let t1 = Date()
    #expect(rebuilt == a)
    // 同一批再铺一遍：就地替换，不追加出重复。
    SyncOverlay.drawings(objects.reversed(), onto: &rebuilt)
    #expect(rebuilt.bySymbol.values.map(\.count).reduce(0, +) == 3600)
    // 删掉 BTC 那只大桶的一半。
    let doomed = objects.filter { $0.id.hasPrefix(InstrumentID.canonical("BTCUSDT") + "/") }.prefix(300).map { object -> SyncObject in
      var gone = object; gone.deleted = true; return gone
    }
    let t2 = Date()
    SyncOverlay.drawings(doomed, onto: &rebuilt)
    let t3 = Date()
    #expect(rebuilt["BTCUSDT"].count == 300)
    #expect(Set(rebuilt["BTCUSDT"].map(\.id)).isDisjoint(with: doomed.map { String($0.id.split(separator: "/").last!) }))
    print(String(format: "DRAW-OVERLAY apply3601=%.0fms delete300=%.0fms", t1.timeIntervalSince(t0) * 1000, t3.timeIntervalSince(t2) * 1000))
  }
}
