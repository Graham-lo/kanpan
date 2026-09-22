import Foundation
import Testing
import KanpanCore
@testable import KanpanData

@Suite("行情缓存身份迁移") struct InstrumentMigrationTests {
  @Test func legacyFilesAndVenueIsolation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let series = BarSeries(symbol: "BTCUSDT", interval: .m1, bars: [.init(openTime: 60_000, open: 1, high: 2, low: 1, close: 2, volume: 3)])
    let legacy = root.appendingPathComponent("BTCUSDT@m1.kbar")
    try legacySnapshotFixture(series).write(to: legacy)
    let read = try #require(SeriesStore.read(symbol: "binance/usd_m/BTCUSDT", interval: .m1, in: root))
    #expect(read.symbol == "binance/usd_m/BTCUSDT" && read.count == 1)
    #expect(SeriesStore.read(symbol: "coinbase/spot/BTC-USD", interval: .m1, in: root) == nil)
    try SeriesStore.write(read, in: root)
    #expect(FileManager.default.fileExists(atPath: legacy.path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("binance/usd_m/BTCUSDT@m1.kbar").path))
    let opens = root.appendingPathComponent("opens.json")
    try Data(#"{"boundary":123,"opens":{"BTCUSDT":100}}"#.utf8).write(to: opens)
    #expect(BaselineSnapshot.read(opens, boundary: 123) == ["binance/usd_m/BTCUSDT": 100])
    let quotes = root.appendingPathComponent("quotes.json")
    try Data(#"[{"s":"BTCUSDT","l":100,"t":1000}]"#.utf8).write(to: quotes)
    #expect(QuoteSnapshot.read(quotes, now: 1000).first?.symbol == "binance/usd_m/BTCUSDT")
  }
  @Test func legacyOpenInterestIsRetained() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = Paths(root: root)
    let old = paths.oi.appendingPathComponent("BTCUSDT/2025-01-15.oi")
    try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
    let day = Aggregator.utcMs(year: 2025, month: 1, day: 15)
    let points = [OIPoint(time: day, value: 123)]
    try OIArchive.encodeSlice(points, dayStartMs: day).write(to: old)
    let store = OIStore(paths: paths)
    #expect(await store.load(symbol: "binance/usd_m/BTCUSDT", dayStart: day) == points)
    #expect(await store.load(symbol: "coinbase/spot/BTC-USD", dayStart: day) == nil)
    await store.save(symbol: "binance/usd_m/BTCUSDT", dayStart: day, points: points)
    #expect(FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: paths.oiDay(symbol: "binance/usd_m/BTCUSDT", day: "2025-01-15").path))
  }

}

// The v1 binary layout stores a UInt16-length symbol after its six-byte header.
// Recreate the old bare key without weakening BarSeries identity invariants.
func legacySnapshotFixture(_ series: BarSeries) -> Data {
  let encoded = Snapshot.encode(series)
  let raw = Data(InstrumentID(series.symbol).symbol.utf8)
  var result = Data(encoded.prefix(6))
  result.append(UInt8(raw.count & 255))
  result.append(UInt8(raw.count >> 8))
  result.append(raw)
  result.append(encoded.dropFirst(8 + series.symbol.utf8.count))
  return result
}
