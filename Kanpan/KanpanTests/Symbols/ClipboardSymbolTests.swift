import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// 方案第 3 节第二件：剪贴板里那段文字认成哪个合约。
///
/// 界面那一半（系统的粘贴按钮、什么时候摆）在 `SymbolSearchView` 里，
/// 为什么不是「打开 SOL」那一行写在 `ClipboardSymbol` 文件头。这儿只钉
/// **认不认得出来**：认得出来才有那一下直接开图，认错了比不认更烦。
@Suite("剪贴板认品种")
struct ClipboardSymbolTests {
  private let catalog = SymbolFixtures.catalog

  @Test("群里、网页上、推特上那几种写法都认")
  func shapes() {
    for text in ["SOLUSDT", "SOL/USDT", "SOL-USDT", "sol usdt", "$SOL", "sol", " SOL\t"] {
      #expect(ClipboardSymbol.resolve(text, catalog: catalog)?.symbol == "binance/usd_m/SOLUSDT", "\(text) 没认出来")
    }
  }

  @Test("中文名和全拼也认")
  func chinese() {
    #expect(ClipboardSymbol.resolve("比特币", catalog: catalog)?.symbol == "binance/usd_m/BTCUSDT")
    #expect(ClipboardSymbol.resolve("bitebi", catalog: catalog)?.symbol == "binance/usd_m/BTCUSDT")
  }

  @Test("首字母缩写不认：搜索页列出来可以，直接替他开图太自作主张")
  func initialsAreNotEnough() {
    #expect(SymbolQuery.match(catalog, query: "btb").first?.id == "binance/usd_m/BTCUSDT")
    #expect(ClipboardSymbol.resolve("btb", catalog: catalog) == nil)
  }

  @Test("整段文章、空的、换行的都不认")
  func junk() {
    #expect(ClipboardSymbol.resolve("", catalog: catalog) == nil)
    #expect(ClipboardSymbol.resolve("   ", catalog: catalog) == nil)
    #expect(ClipboardSymbol.resolve("SOL\nUSDT", catalog: catalog) == nil)
    #expect(ClipboardSymbol.resolve(String(repeating: "SOL", count: 20), catalog: catalog) == nil)
    #expect(ClipboardSymbol.resolve("今天大盘怎么样", catalog: catalog) == nil)
  }

  @Test("一个词同档撞上两个就不猜")
  func ambiguous() {
    let a = SymbolInfo(symbol: "binance/usd_m/AAAUSDT", base: "AAA", pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    let b = SymbolInfo(symbol: "binance/usd_m/AAAUSDC", base: "AAA", pricePrecision: 2, tickSize: 0.01, underlyingType: "COIN")
    #expect(ClipboardSymbol.resolve("AAA", catalog: [a, b]) == nil)
  }
}
