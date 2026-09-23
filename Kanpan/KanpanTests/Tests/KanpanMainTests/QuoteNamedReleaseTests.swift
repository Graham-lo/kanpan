import Foundation
import Testing
import KanpanCore
@testable import KanpanMain

// 新建价格提醒页点名要的那一只（`quoteNow`）：页面开着时一直算在报价簿的范围里，
// 页面关了（`releaseNamed`）就放掉；图上那只、自选里的不跟着走。
// 不进前台，报价簿不开连接，只看它交给宿主的订阅范围（`onScopeChange`）。
@MainActor
@Suite("新建提醒页点名的那一只用完即放")
struct QuoteNamedReleaseTests {

  private let chart = InstrumentID.canonical("BTCUSDT")
  private let favorite = InstrumentID.canonical("SOLUSDT")
  private let eth = InstrumentID.canonical("ETHUSDT")
  private let doge = InstrumentID.canonical("DOGEUSDT")

  /// 一本挂着图上那只和一只自选的报价簿，外加它最后一次交出来的范围。
  private func book() -> (QuoteBook, () -> Set<String>) {
    let book = QuoteBook()
    var last = Set<String>()
    book.onScopeChange = { last = $0 }
    book.setChartSymbol(chart)
    book.setFavorites([favorite])
    return (book, { last })
  }

  @Test("页面开着时别的变动裁不掉它，关了就放掉，图上那只和自选照旧")
  func releasedWhenPageCloses() {
    let (book, scope) = book()
    book.quoteNow("ETHUSDT")
    book.setFavorites([favorite])            // 页面开着时来一次别的范围变动
    #expect(scope().contains(eth), "新建页还开着，点名的那只就被裁掉了")

    book.releaseNamed()
    #expect(!scope().contains(eth), "新建页关了，点名的那只还留在报价簿的范围里")
    #expect(scope().contains(chart), "放掉点名的那只时把图上那只也放了")
    #expect(scope().contains(favorite))

    book.setFavorites([favorite])
    #expect(!scope().contains(eth), "放掉之后下一次范围变动又把它带回来了")
    book.shutdown()
  }

  @Test("换点名一只，前一只当场放掉")
  func switchingDropsThePrevious() {
    let (book, scope) = book()
    book.quoteNow("ETHUSDT")
    book.quoteNow("DOGEUSDT")
    #expect(!scope().contains(eth), "换了一只，前一只还挂着")
    book.setFavorites([favorite])
    #expect(scope().contains(doge))
    #expect(!scope().contains(eth))
    book.shutdown()
  }

  @Test("点名的就是图上那只：放掉之后图上那只还在")
  func namingTheChartSymbolKeepsIt() {
    let (book, scope) = book()
    book.quoteNow("BTCUSDT")
    book.releaseNamed()
    #expect(scope().contains(chart))
    book.releaseNamed()                      // 重复放是空操作
    #expect(scope().contains(chart))
    book.shutdown()
  }
}
