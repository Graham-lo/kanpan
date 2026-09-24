import Testing
import KanpanCore
@testable import Kanpan

/// 板块的名单只有两份真身：真板块在 `SectorCatalog`，兜底桶在 `SectorFeed.bucketOrder`。
/// 记号表（`SectorIcons`）只按 id 挂记号，这里对账——少一枚就是列表里一个没有记号的板块，
/// 多一枚就是一个已经撤掉的板块还留着画。
@Suite("板块记号表对账")
struct SectorIconTableTests {
  private var expectedIDs: [String] {
    SectorCatalog.sectors(.crypto).map(\.id) + SectorFeed.bucketOrder + SectorCatalog.sectors(.us).map(\.id)
  }

  /// 只比集合不比顺序：列表按涨跌幅排，记号表的先后不上界面（原来那份 `SectorIcons.order`
  /// 没人读，已经删了）。
  @Test("记号表的 id 就是分类表加兜底桶，一枚不多一枚不少，也没有重复")
  func idsMatchCatalogAndBuckets() {
    let ids = SectorIcons.all.map(\.id)
    #expect(ids.count == Set(ids).count)
    #expect(ids.sorted() == expectedIDs.sorted())
    for id in expectedIDs { #expect(SectorIcons.art(id) != nil, "\(id) 没有记号") }
  }

  @Test("记号所属族的市场和板块的市场一致，兜底桶走归集族")
  func familyMarketMatchesSector() {
    for def in SectorCatalog.all {
      guard let art = SectorIcons.art(def.id), let fam = SectorIcons.families[art.fam] else {
        Issue.record("\(def.id) 缺记号或族"); continue
      }
      #expect(fam.market == def.market, "\(def.id)")
    }
    for id in SectorFeed.bucketOrder {
      #expect(SectorIcons.art(id)?.fam == "bucket", "\(id)")
    }
  }

  @Test("兜底桶每个都有名字，名字只在 SectorFeed 一处")
  func bucketsHaveNames() {
    #expect(Set(SectorFeed.bucketNames.keys) == Set(SectorFeed.bucketOrder))
  }

  @Test("每枚记号的色相和族一致，档位只有 L / M / D")
  func hueFollowsFamily() {
    for art in SectorIcons.all {
      #expect(SectorIcons.families[art.fam]?.hue == art.hue, "\(art.id)")
      #expect(["L", "M", "D"].contains(art.tone), "\(art.id)")
      #expect(SectorIcons.palette[art.hue] != nil, "\(art.id)")
    }
  }
}
