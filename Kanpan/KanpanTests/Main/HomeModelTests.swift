import Foundation
import Testing
import KanpanCore
@testable import Kanpan

// 首页「异动」：打开时定序，之后拉到的就地换数不换位，新来的只计数；点药丸 / 换自选才重排。

@Suite("首页：异动定序与合并")
@MainActor struct HomeModelTests {
  private let wall = HighlightLevel(id: "lv-1", low: 82_609, high: 82_940, side: .bid, distPct: 0.08,
                                    wallUsd: 463_000_000, wallHeldMs: 8 * 3_600_000, tests: 27)

  private func row(_ base: String, at: Int64, price: Double = 1, cat: HighlightsBoard.Category = .book) -> HighlightsBoard.Row {
    HighlightsBoard.Row(base: base, favorite: false, count: 1, cat: cat, tier: 2, top: .level(wall),
                        price: price, changePct: 0.5, atMs: at)
  }

  private func board(_ rows: [HighlightsBoard.Row]) -> HighlightsBoard {
    HighlightsBoard(generatedAtMs: 1_791_606_780_000, rows: rows)
  }

  @Test func mergeKeepsOrderUpdatesInPlaceAndCountsFresh() {
    let shown = [row("BTC", at: 10), row("ETH", at: 20), row("SOL", at: 30)]
    // 服务端新顺序：DOGE 新来、ETH 更新了、BTC 只换价、SOL 没了。
    let latest = [row("DOGE", at: 50), row("ETH", at: 40), row("BTC", at: 10, price: 2)]
    let merged = HomeModel.merge(shown: shown, latest: latest)
    #expect(merged.rows.map(\.base) == ["BTC", "ETH", "SOL"])
    #expect(merged.rows[0].price == 2)
    #expect(merged.rows[1].atMs == 40)
    #expect(merged.rows[2].atMs == 30)
    #expect(merged.fresh == 2)
  }

  @Test func pollMergesThenPillReorders() async {
    let model = HomeModel(defaults: UserDefaults(suiteName: "home.tests.\(UUID())")!)
    await model.load(bases: [], reorder: false) { _ in board([row("BTC", at: 10), row("ETH", at: 20)]) }
    #expect(model.visibleRows.map(\.base) == ["BTC", "ETH"])
    let token = model.reorderToken
    await model.load(bases: [], reorder: false) { _ in board([row("SOL", at: 30), row("ETH", at: 20), row("BTC", at: 10)]) }
    #expect(model.visibleRows.map(\.base) == ["BTC", "ETH"])
    #expect(model.fresh == 1)
    #expect(model.reorderToken == token)
    model.reorderNow()
    #expect(model.visibleRows.map(\.base) == ["SOL", "ETH", "BTC"])
    #expect(model.fresh == 0)
    #expect(model.reorderToken == token + 1)
  }

  @Test func changedFavoritesReorderAndFailureKeepsRows() async {
    let model = HomeModel(defaults: UserDefaults(suiteName: "home.tests.\(UUID())")!)
    await model.load(bases: ["BTC"], reorder: false) { _ in board([row("BTC", at: 10)]) }
    await model.load(bases: ["BTC", "ETH"], reorder: false) { _ in board([row("ETH", at: 20), row("BTC", at: 10)]) }
    #expect(model.visibleRows.map(\.base) == ["ETH", "BTC"])
    await model.load(bases: ["BTC", "ETH"], reorder: false) { _ in nil }
    #expect(model.failed)
    #expect(model.visibleRows.count == 2)
  }

  @Test func chipFilters() async {
    let model = HomeModel(defaults: UserDefaults(suiteName: "home.tests.\(UUID())")!)
    await model.load(bases: [], reorder: true) { _ in
      board([row("BTC", at: 1, cat: .book), row("ETH", at: 2, cat: .oi), row("SOL", at: 3, cat: .book)])
    }
    model.chip = .cat(.book)
    #expect(model.visibleRows.map(\.base) == ["BTC", "SOL"])
    model.chip = .cat(.funding)
    #expect(model.visibleRows.isEmpty)
    model.chip = .cat(.oi)
    #expect(model.visibleRows.map(\.base) == ["ETH"])
  }

  @Test func favoriteBasesStripScaleAndDedupe() {
    let bases = HomeModel.favoriteBases(["BTCUSDT", "1000PEPEUSDT", "BTCUSDC", "ETHUSDT"])
    #expect(bases == ["BTC", "PEPE", "ETH"])
  }

  @Test func boardWindowIsLocalAndDefaultsTo4h() {
    let defaults = UserDefaults(suiteName: "home.tests.\(UUID())")!
    let model = HomeModel(defaults: defaults)
    #expect(model.window(for: .change) == .h4)
    model.setWindow(.h24, for: .change)
    // 只记在本机：写进本机 UserDefaults，下次打开照旧。
    #expect(defaults.string(forKey: HomeModel.windowKey) == MarketBoard.Window.h24.rawValue)
    #expect(HomeModel(defaults: defaults).window(for: .change) == .h24)
  }

  @Test func changeAndOiWindowsAreIndependent() {
    let defaults = UserDefaults(suiteName: "home.tests.\(UUID())")!
    let model = HomeModel(defaults: defaults)
    model.setWindow(.h1, for: .change)
    model.setWindow(.h24, for: .oi)
    #expect(model.window(for: .change) == .h1)
    #expect(model.window(for: .oi) == .h24)
    let reopened = HomeModel(defaults: defaults)
    #expect(reopened.window(for: .change) == .h1)
    #expect(reopened.window(for: .oi) == .h24)
    #expect(HomeModel.Segment.change.windowKey != HomeModel.Segment.oi.windowKey)
    #expect(HomeModel.Segment.moves.windowKey == nil)
  }

  @Test func segmentsRouteToTheirOwnBoards() async {
    #expect(HomeModel.Segment.allCases == [.moves, .change, .oi, .sectors])
    #expect(HomeModel.Segment.sectors.kinds.isEmpty)
    #expect(HomeModel.Segment.sectors.windowKey == nil)
    #expect(HomeModel.Segment.change.kinds == [.gainers, .losers])
    #expect(HomeModel.Segment.oi.kinds == [.oi, .oidown])
    #expect(HomeModel.Segment.moves.kinds.isEmpty)
    let model = HomeModel(defaults: UserDefaults(suiteName: "home.tests.\(UUID())")!)
    model.setWindow(.h1, for: .oi)
    let asked = Asked()
    await model.loadBoards(segment: .oi) { kind, window in
      asked.list.append("\(kind.rawValue)@\(window.rawValue)")
      // 服务端还没上 oidown：那一张失败，另一张照常。
      guard kind == .oi else { return nil }
      return MarketBoard(generatedAtMs: 1, rows: [MarketBoard.Row(base: "BTC", changePct: 3, oiUsd: 1e9, price: 1)])
    }
    #expect(asked.list.sorted() == ["oi@1h", "oidown@1h"])
    #expect(model.boards[.oi]?.rows.map(\.base) == ["BTC"])
    #expect(model.boards[.oidown] == nil)
    #expect(model.boardFailed.contains(.oidown))
    #expect(model.boards[.gainers] == nil)
  }

  @Test func moveRowsOpenTheChartWithoutTheSheet() {
    var move = row("WIF", at: 1, cat: .move)
    move.top = .move(HighlightMove(up: true, window: .m1, pct: 2.4, volUsd: 3_200_000, price: 1, atMs: 1))
    #expect(!HomeModel.opensSheet(move))
    #expect(HomeModel.opensSheet(row("BTC", at: 1, cat: .book)))
    #expect(HomeModel.opensSheet(row("ETH", at: 1, cat: .oi)))
    #expect(HomeModel.opensSheet(row("SOL", at: 1, cat: .funding)))
  }
}

@MainActor private final class Asked { var list: [String] = [] }
