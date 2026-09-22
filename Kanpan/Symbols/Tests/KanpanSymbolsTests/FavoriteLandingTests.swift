import Foundation
import Testing
import KanpanCore

@testable import KanpanSymbols

/// 方案第 3 节第五件 b：从某一类里点搜索加进来的品种，落在**他此刻站着的那一类**。
@Suite("加自选的落点")
@MainActor
struct FavoriteLandingTests {
  private func model() -> SymbolPickerModel {
    SymbolPickerModel(catalog: SymbolFixtures.catalog,
                      store: SymbolPrefsStore(storage: MemoryPrefsStorage(), key: "t"))
  }

  @Test("站在「短线」里加 BTC，它就留在「短线」，不会自己跳去「加密」")
  func landsInCurrentGroup() throws {
    let m = model()
    let short = try #require(m.createGroup("短线"))
    let long = try #require(m.createGroup("长线"))
    m.selectedGroupSource = { short }
    m.addFavorite("binance/usd_m/BTCUSDT")
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == short)
    #expect(m.prefs.groups.map(\.name) == ["短线", "长线"])   // 没有多出一个「加密」

    m.selectedGroupSource = { long }
    m.addFavorite("binance/usd_m/ETHUSDT")
    #expect(m.prefs.groupForSymbol["binance/usd_m/ETHUSDT"] == long)
    #expect(m.prefs.favorites(in: short) == ["binance/usd_m/BTCUSDT"])
  }

  @Test("停在「全部」（没挑过分类）时落在默认的第一类")
  func landsInDefaultGroup() throws {
    let m = model()
    let first = try #require(m.createGroup("自选"))
    _ = m.createGroup("备选")
    m.selectedGroupSource = { nil }
    m.addFavorite("binance/usd_m/SOLUSDT")
    #expect(m.prefs.groupForSymbol["binance/usd_m/SOLUSDT"] == first)
  }

  @Test("一个分类都还没有的新用户：按资产类型开第一类")
  func firstEverFavorite() {
    let m = model()
    m.addFavorite("binance/usd_m/BTCUSDT")
    #expect(m.prefs.groups.map(\.name) == ["加密"])
    #expect(m.prefs.groupForSymbol["binance/usd_m/BTCUSDT"] == m.prefs.groups.first?.id)
  }

  @Test("点星星之后搜索词还在，页面上的东西一个不动")
  func starDoesNotDisturbTheList() throws {
    let m = model()
    m.query = "eth"
    let before = m.sections.flatMap { $0.rows.map(\.id) }
    #expect(m.toggleFavorite("binance/usd_m/ETHUSDT"))
    #expect(m.query == "eth")                                   // 不清词
    let after = m.sections.flatMap { $0.rows.map(\.id) }
    #expect(after == before)                                    // 搜索结果这一列还是原样
    #expect(m.prefs.favorites == ["binance/usd_m/ETHUSDT"])
    #expect(m.prefs.recents.isEmpty)                            // 加星不算「看过」，不换图
  }
}
