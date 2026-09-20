import Testing
import KanpanCore
@testable import KanpanSector

// C-01：人已经钻进一个板块，中间来了一帧算不出它的快照——这不是「他按了返回」。
//
// 从前 `SectorPage.listLayer` 找不到统计就 `pop()`，于是冷启动第一帧、刚换窗口、
// 网络抖一下都会把人送回球场，而且回不去。这一套钉住的是「退栈要有证据」。

@Suite("C-01 板块下钻的去留")
struct SectorDrillDecisionTests {
  private func stat(_ id: String) -> SectorStat {
    SectorStat(id: id, name: id, market: .crypto, pct: 1, memberCount: 5,
               quoteVolume: 1_000, isFallback: false)
  }
  /// 分类表里真实存在的一个 id，用它来证明「静态表说有」这条证据。
  private var knownID: String { SectorCatalog.sectors(.crypto)[0].id }

  @Test("这一帧有它就照常画")
  func showsWhenTheStatIsThere() {
    let id = knownID
    #expect(SectorDrillDecision.decide(id: id, stats: [stat(id)], buckets: []) == .show)
  }

  @Test("别的板块算出来了、唯独这一帧没它，只要分类表还认就留在原地")
  func waitsWhenTheCatalogStillKnowsIt() {
    let id = knownID
    // 这正是报告里那条最短复现：注入一次不含 id 的临时快照。
    #expect(SectorDrillDecision.decide(id: id, stats: [stat("other")], buckets: []) == .wait)
  }

  @Test("整帧都是空的时候谁也别信，不退栈")
  func waitsWhenTheWholeSnapshotIsEmpty() {
    #expect(SectorDrillDecision.decide(id: "fb-whatever", stats: [], buckets: []) == .wait)
  }

  @Test("兜底桶只作正面证据：它说有就留下")
  func waitsWhenOnlyTheBucketKnowsIt() {
    let bucket = SectorFallbackBucket(id: "fb-x", name: "其它", members: ["AAA"])
    #expect(SectorDrillDecision.decide(id: "fb-x", stats: [stat("other")], buckets: [bucket]) == .wait)
  }

  @Test("分类表和兜底桶都不认、而这一帧确实有别的板块，才算它真的没了")
  func popsOnlyWhenNobodyKnowsIt() {
    #expect(SectorDrillDecision.decide(id: "fb-gone", stats: [stat("other")], buckets: []) == .pop)
  }

  @Test("等的时候那张空壳带着板块名和成员数，人不会看见一块空白")
  func placeholderKeepsTheNameAndTheWayBack() {
    let def = SectorCatalog.sectors(.crypto)[0]
    let shell = SectorDrillDecision.placeholder(id: def.id, market: .crypto, buckets: [])
    #expect(shell.name == def.name)
    #expect(shell.staticCount == def.members.count)
    #expect(shell.memberCount == 0, "没数据就是没数据，不许编一个中位数出来")
    #expect(!shell.eligible)
  }
}
