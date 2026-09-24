import Foundation
import Testing
import KanpanCore
import KanpanData
@testable import Kanpan

/// 审查 17：`.damaged` / `.wiped` 要真的驱动恢复，而不是算出来摆着。
@MainActor
@Suite("设置档案坏了 / 没了怎么恢复")
struct SettingsRecoveryTests {
  private var edited: Prefs { var p = Prefs.defaults; p.barSpacing = 9; return p }

  @Test("完好 / 首次：照旧以盘上那份为准，可以记操作、可以认领访客那份")
  func trustedPassesThrough() {
    for verdict in [SettingsCacheVerdict.intact, .firstRun] {
      let plan = SettingsRecovery.plan(verdict, onDisk: edited, baseline: .defaults)
      #expect(plan == .init(prefs: edited, mayCapture: true, keepsDirtyMarks: true, mayAdoptGuest: true))
    }
  }

  @Test("坏了 / 被清了、同步存档里有本机上一次那份：用它，脏标识照留，不记新操作")
  func unreliableRestoresFromArchive() {
    for verdict in [SettingsCacheVerdict.damaged, .wiped(unpushed: true), .wiped(unpushed: false)] {
      let plan = SettingsRecovery.plan(verdict, onDisk: .defaults, baseline: edited)
      #expect(plan.prefs == edited, "\(verdict)：用户的设置被出厂值顶掉了")
      #expect(!plan.mayCapture, "\(verdict)：不许把恢复出来的这份再当成新改动推上去")
      #expect(plan.keepsDirtyMarks)
      #expect(!plan.mayAdoptGuest)
    }
  }

  @Test("坏了、存档里也没有：绝不把出厂值当成「本机刚改的」推上云端，脏标识作废让云端那份落地")
  func unreliableWithoutArchiveWaitsForCloud() {
    let plan = SettingsRecovery.plan(.wiped(unpushed: true), onDisk: .defaults, baseline: nil)
    #expect(plan == .init(prefs: .defaults, mayCapture: false, keepsDirtyMarks: false, mayAdoptGuest: false))
  }

  @Test("脏标识作废之后，云端那份能落在用户改过的那几个字段上")
  func droppedMarksLetCloudLand() {
    let archive = InMemoryPrefsStorage(), sentinel = InMemoryPrefsStorage()
    let store = PrefsStore(storage: archive, cache: UnavailableMarketCache(), sentinel: sentinel)
    store.useStorage(archive, prefs: .defaults, arrival: .ownerSwitched, owner: "A")
    store.update { $0.barSpacing = 2 }
    #expect(store.dirtyFields == ["barSpacing"])

    // prefs.json 被写坏了；本机那一半找不回来。
    archive.setPrefsData(Data("{".utf8), forKey: PrefsCodec.key)
    let verdict = store.diagnose(archive, owner: "A")
    #expect(verdict == .damaged)
    let plan = SettingsRecovery.plan(verdict, onDisk: .defaults, baseline: nil)
    store.useStorage(archive, prefs: plan.prefs, arrival: .sameProfile, owner: "A",
                     verdict: verdict, keepsDirtyMarks: plan.keepsDirtyMarks)
    #expect(store.verdict == .damaged, "结论要记的是写盘之前那一次体检")
    #expect(store.dirtyFields.isEmpty)

    var cloud = Prefs.defaults; cloud.barSpacing = 6
    store.applySynced(cloud)
    #expect(store.prefs.barSpacing == 6)
  }
}
