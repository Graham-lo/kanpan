import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// 体感优化 2026-10-07：品种表还没到时搜索不说「没有这个品种」；
/// 目录后台换新后已打开的页面自己重读。
@Suite("品种表载入中与后台换新")
@MainActor
struct CatalogLoadingTextTests {

  private func store() -> SymbolPrefsStore {
    SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t")
  }

  @Test("表空时空结果写「正在载入品种」，表到了才是「没有这个品种」")
  func loadingTextUntilCatalogArrives() {
    let m = SymbolPickerModel(store: store())
    #expect(m.emptyText == SymbolSections.loadingText)
    #expect(m.emptyText == "正在载入品种")
    m.setCatalog(SymbolFixtures.catalog)
    #expect(m.emptyText == SymbolSections.emptyText)
  }

  @Test("目录发 didRefresh 后，已经接了 loader 的模型重读到新表")
  func reloadsOnCatalogRefresh() async {
    final class Box: @unchecked Sendable {
      private let lock = NSLock()
      private var value: [SymbolInfo]
      init(_ v: [SymbolInfo]) { value = v }
      var list: [SymbolInfo] {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
      }
    }
    let first = Array(SymbolFixtures.catalog.prefix(2))
    let box = Box(first)
    let m = SymbolPickerModel(store: store())
    m.setLoader { box.list }
    for _ in 0..<100 where m.catalog.count != first.count { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(m.catalog.count == first.count)

    box.list = SymbolFixtures.catalog
    NotificationCenter.default.post(name: .symbolCatalogDidRefresh, object: "binance")
    for _ in 0..<200 where m.catalog.count != SymbolFixtures.catalog.count {
      try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(m.catalog.count == SymbolFixtures.catalog.count)
  }
}
