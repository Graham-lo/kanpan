import Testing
@testable import KanpanSymbols

/// 搜索页 ⇄ 品种整页（审查 16.4）。两张呈现之间的换页一律等上一张退完：
/// 同一拍里一关一开，UIKit 会把第二张吞掉。
@Suite("搜索页与品种整页的换页")
struct SymbolSearchFlowTests {
  @Test("查看全部：先收搜索页，退完才开整页")
  func allWaitsForSearchToLeave() {
    var flow = SymbolSearchFlow()
    flow.openSearch()
    #expect(flow.searchShown && !flow.allShown)
    flow.showAllFromSearch()
    #expect(!flow.searchShown && !flow.allShown, "同一拍里不许一关一开")
    #expect(flow.isActive, "换页间隙里仍算开着，图表别趁机恢复渲染")
    flow.searchDismissed()
    #expect(flow.allShown && flow.allFromSearch)
  }

  @Test("整页返回：原路退回搜索页，词留着；也要等整页退完")
  func backGoesToSearchAfterAllLeaves() {
    var flow = SymbolSearchFlow()
    flow.openSearch(); flow.showAllFromSearch(); flow.searchDismissed()
    let clearQuery = flow.closeAll()
    #expect(!clearQuery)
    #expect(!flow.allShown && !flow.searchShown)
    flow.allDismissed()
    #expect(flow.searchShown && !flow.allFromSearch)
  }

  @Test("系统下滑关掉整页：没有原路退回这回事")
  func swipeDownClosesForGood() {
    var flow = SymbolSearchFlow()
    flow.openSearch(); flow.showAllFromSearch(); flow.searchDismissed()
    flow.allShown = false   // 呈现写回的
    flow.allDismissed()
    #expect(!flow.isActive && !flow.allFromSearch)
  }

  @Test("直接关搜索页不会接着开整页")
  func plainCloseOpensNothing() {
    var flow = SymbolSearchFlow()
    flow.openSearch()
    flow.searchShown = false
    flow.searchDismissed()
    #expect(!flow.isActive)
  }

  @Test("挑中品种：两张都收、后路作废")
  func resetDropsTheWayBack() {
    var flow = SymbolSearchFlow()
    flow.openSearch(); flow.showAllFromSearch(); flow.searchDismissed()
    flow.reset()
    flow.allDismissed(); flow.searchDismissed()
    #expect(!flow.isActive && !flow.allFromSearch)
  }

  @Test("搜索页已开着再点一次放大镜（外链叫搜索）：不重开、不动别的")
  func openSearchIsIdempotent() {
    var flow = SymbolSearchFlow()
    flow.openSearch()
    let before = flow
    flow.openSearch()
    #expect(flow == before)
  }
}
