import Foundation
import Testing
import KanpanCore

@testable import Kanpan

/// 搜索停手才搭、在后台搭、只认最后一次输入（压测收尾 2026-09-26，整机线移交第 3 项）。
///
/// 原来 `query` 的 didSet 当场 `rebuild()`：每敲一个字都在主线程上把整份目录拼音 / 别名匹配、
/// 按成交额排序、搭分区。这里用一份 2000 只的目录量「连敲三个字，主线程上花了多少」。
@Suite("搜索 · 去抖与后台搭建")
@MainActor
struct SymbolSearchSettleTests {

  private static let big: [SymbolInfo] = SymbolFixtures.catalog + (0..<2000).map { i in
    SymbolInfo(symbol: "binance/usd_m/E\(i)TUSDT", base: "E\(i)T", pricePrecision: 2, tickSize: 0.01)
  }
  private static let bigTickers: [Ticker] = big.enumerated().map { i, info in
    Ticker(symbol: info.symbol, last: 1 + Double(i), changePercent: 1, high: 2, low: 0.5,
           quoteVolume: Double(1_000 + i))
  }

  private func model(debounce: Duration = .milliseconds(80)) -> SymbolPickerModel {
    let m = SymbolPickerModel(catalog: Self.big, tickers: Self.bigTickers,
                              store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "settle"))
    m.searchDebounce = debounce
    return m
  }

  @Test("连敲三个字：主线程上一次都不搭，停手后只落定最后那个词")
  func typingSettlesOnLastInput() async {
    let m = model()
    let resting = m.sections
    let clock = ContinuousClock()
    var onMain = Duration.zero
    for q in ["e", "et", "eth"] {
      let t = clock.now
      m.query = q
      onMain += clock.now - t
    }
    #expect(m.sections == resting, "敲字的那一刻就当场搭了")
    #expect(m.settledQuery.isEmpty)
    await m.settleSearch()
    #expect(m.settledQuery == "eth")
    #expect(m.sections.map(\.kind) == [.search])
    #expect(m.sections.first?.rows.first?.id == "binance/usd_m/ETHUSDT")

    // 修前那条路：每一个字都在主线程上整表搭一遍。
    let t = clock.now
    for q in ["e", "et", "eth"] {
      _ = SymbolSections.build(catalog: Self.big, tickers: [:], prefs: m.prefs, query: q,
                               catalogKeys: Set(Self.big.map(\.symbol)))
    }
    let before = clock.now - t
    print("[压测收尾·搜索去抖] 目录 \(Self.big.count) 只、连敲 3 字：主线程上修前 \(before)（3 次整表搭建），修后 \(onMain)（0 次；停手后后台搭 1 次）")
    #expect(onMain < before)
  }

  @Test("清空当场回到没搜的那一页，还在路上的那一趟作废")
  func clearingIsImmediateAndCancelsInflight() async {
    let m = model(debounce: .milliseconds(200))
    let resting = m.sections
    m.query = "eth"
    m.query = ""
    #expect(m.settledQuery.isEmpty)
    #expect(m.sections == resting)
    await m.settleSearch()
    #expect(m.settledQuery.isEmpty, "作废的那一趟回来把结果盖上了")
    #expect(m.sections == resting)
  }

  @Test("后台搭的时候当场重搭过（比如点了星）：晚到的那一份不许盖回去")
  func syncRebuildSupersedesInflight() async {
    let m = model(debounce: .zero)
    m.query = "eth"
    #expect(m.toggleFavorite("binance/usd_m/ETHUSDT"))   // 当场按「eth」重搭一次
    await m.settleSearch()
    #expect(m.settledQuery == "eth")
    #expect(m.prefs.favorites == ["binance/usd_m/ETHUSDT"])
    #expect(m.sections.first?.rows.first?.id == "binance/usd_m/ETHUSDT")
  }

  @Test("页面不在时敲字不搭，露面时当场补")
  func inactivePageDefersToAppear() async {
    let m = model(debounce: .zero)
    m.setSectionsActive(false)
    m.query = "eth"
    await m.settleSearch()
    #expect(m.settledQuery.isEmpty)
    m.setSectionsActive(true)
    #expect(m.settledQuery == "eth")
    #expect(m.sections.map(\.kind) == [.search])
  }
}
