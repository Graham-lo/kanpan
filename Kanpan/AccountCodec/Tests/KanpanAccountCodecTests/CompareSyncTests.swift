import Foundation
import Testing
import KanpanAccount
@testable import KanpanAccountCodec

@Suite("对比集合同步") struct CompareSyncTests {
  @Test func anotherProfileReceivesCollectionAndClear() throws {
    var first = Prefs.defaults
    first.compareSymbols = ["binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT", "binance/usd_m/DOGEUSDT"]
    let upload = try PersonalSyncCodec.settings(first)
    #expect(upload.body["compareSymbols"] == .array(first.compareSymbols.map { .string($0) }))
    let restored = try PersonalSyncCodec.apply(upload, to: .defaults)
    #expect(restored.compareSymbols == first.compareSymbols)
    #expect(PersonalSyncCodec.ownedKeys["settings"]?.contains("compareSymbols") == true)
    first.compareSymbols = []
    #expect(try PersonalSyncCodec.apply(PersonalSyncCodec.settings(first), to: restored).compareSymbols.isEmpty)
    var accountB = Prefs.defaults
    PersonalSyncCodec.keepDeviceFields(restored, in: &accountB)
    #expect(accountB.compareSymbols.isEmpty)
  }
  @Test func reviewSnapshotsExcludeTheComparisonCollection() throws {
    var prefs = Prefs.defaults
    prefs.compareSymbols = ["binance/usd_m/ETHUSDT"]
    let snapshot = try PersonalSyncCodec.snapshot(prefs)
    let fields = try JSONDecoder().decode(PersonalSyncCodec.ChartSnapshot.self, from: snapshot).fields
    #expect(fields["compareSymbols"] == nil)
    #expect(try PersonalSyncCodec.snapshotPrefs(snapshot, base: prefs).compareSymbols.isEmpty)
    // 老版本或外部快照夹带这个键，也不能把对比带入复盘。
    var old = PersonalSyncCodec.ChartSnapshot(version: 1, fields: fields)
    old.fields["compareSymbols"] = .array([.string("binance/usd_m/SOLUSDT")])
    #expect(try PersonalSyncCodec.snapshotPrefs(JSONEncoder().encode(old), base: prefs).compareSymbols.isEmpty)
  }
}
