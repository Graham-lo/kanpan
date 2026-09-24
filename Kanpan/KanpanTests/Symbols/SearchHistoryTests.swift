import Foundation
import Testing
@testable import Kanpan

@Suite("历史搜索")
@MainActor
struct SearchHistoryTests {
  private func store() -> (SearchHistory, MemorySearchHistoryStorage) {
    let storage = MemorySearchHistoryStorage()
    return (SearchHistory(storage: storage, key: "t"), storage)
  }

  @Test("新的在前、重复只留一条（不分大小写）")
  func newestFirst() {
    let (h, _) = store()
    h.remember("btc")
    h.remember("eth")
    h.remember("BTC")
    #expect(h.terms == ["BTC", "eth"])
  }

  @Test("空白词不记，前后空格剃掉")
  func blanks() {
    let (h, _) = store()
    h.remember("   ")
    h.remember("\n\t")
    #expect(h.terms.isEmpty)
    h.remember("  sol  ")
    #expect(h.terms == ["sol"])
  }

  @Test("超长的词截到 24 个字符")
  func longTerm() {
    let (h, _) = store()
    h.remember(String(repeating: "A", count: 60))
    #expect(h.terms.first?.count == SearchHistory.maxTermLength)
  }

  @Test("最多 10 条，挤掉最旧的")
  func limit() {
    let (h, _) = store()
    for i in 0..<14 { h.remember("T\(i)") }
    #expect(h.terms.count == SearchHistory.limit)
    #expect(h.terms.first == "T13")
    #expect(h.terms.last == "T4")
  }

  @Test("删一条 / 清空都落盘，重开还是那样")
  func persistence() {
    let storage = MemorySearchHistoryStorage()
    let h = SearchHistory(storage: storage, key: "t")
    h.remember("btc")
    h.remember("eth")
    #expect(SearchHistory(storage: storage, key: "t").terms == ["eth", "btc"])

    h.remove("ETH")   // 大小写不敏感
    #expect(h.terms == ["btc"])
    #expect(SearchHistory(storage: storage, key: "t").terms == ["btc"])

    h.clear()
    #expect(h.terms.isEmpty)
    #expect(storage.searchHistory(forKey: "t") == nil)
    #expect(SearchHistory(storage: storage, key: "t").terms.isEmpty)
  }

  @Test("盘上那份脏了也读得回来：空串、重复、超量一并收拾")
  func cleanOnLoad() {
    let storage = MemorySearchHistoryStorage()
    var dirty = ["btc", "", "  ", "BTC", "eth"]
    dirty += (0..<12).map { "X\($0)" }
    storage.setSearchHistory(dirty, forKey: "t")
    let h = SearchHistory(storage: storage, key: "t")
    #expect(h.terms.count == SearchHistory.limit)
    #expect(Array(h.terms.prefix(3)) == ["btc", "eth", "X0"])
  }
}
