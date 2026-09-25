import Foundation
import Testing

@testable import Kanpan

/// 长按预览卡的缓存（审查 P2-3）：最近用过的留着，超过容量扔最旧的；
/// 按过但一直取不到数的品种也算进容量，「最近」表不会无限长。
@Suite("预览卡缓存")
@MainActor
struct SymbolPreviewCacheTests {
  @Test("超过容量从最旧的扔，重新用过的挪到最新")
  func evictsLeastRecentlyUsed() {
    var lru = PreviewRecentKeys(capacity: 3)
    var evicted: [[String]] = []
    for key in ["A", "B", "C", "A"] { evicted.append(lru.touch(key)) }
    let nothingDropped = evicted.joined().isEmpty
    #expect(nothingDropped, "没满之前谁也不扔；A 已在表里，只是挪到最新")
    let dropped = lru.touch("D")
    #expect(dropped == ["B"], "最久没用的是 B")
    #expect(lru.keys == ["C", "A", "D"])
  }

  @Test("一直按新品种，表长永远不超过容量")
  func neverGrowsPastCapacity() {
    var lru = PreviewRecentKeys(capacity: SymbolPreviewStore.capacity)
    var evicted = 0
    for i in 0..<200 { evicted += lru.touch("S\(i)").count }
    #expect(lru.keys.count == SymbolPreviewStore.capacity)
    #expect(evicted == 200 - SymbolPreviewStore.capacity)
    #expect(lru.keys.last == "S199")
  }
}
