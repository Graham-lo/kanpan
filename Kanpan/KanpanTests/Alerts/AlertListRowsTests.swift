import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// 提醒总表：排序缓存、摊平成行、写一次只动受影响的行（压测收尾 2026-09-26，整机线移交第 5 项）。
///
/// 原来总表 body 每跑一趟都现排 `AlertRecordText.sections(store.all)`，`ScrollView { VStack }`
/// 一次把所有行建出来；`AlertStore` 任何一次写都叫醒整页、每一行都重跑。
/// 判据是次数与「哪几行的输入变了」，不是墙钟。
@Suite("提醒 · 总表按行")
@MainActor
struct AlertListRowsTests {
  private func fresh() -> AlertStore {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("alerts-rows-\(UUID().uuidString).json")
    return AlertStore(store: AlertFileStore(url: url))
  }

  /// 180 条价格提醒摊在 12 只品种上、10 条画线提醒。
  private func loaded() throws -> AlertStore {
    let store = fresh()
    for i in 0..<180 {
      let symbol = "C\(i % 12)USDT"
      try #require(store.addPrice(symbol: symbol, target: Double(1_000 + i), current: 900,
                                  label: "\(1_000 + i)", now: Double(i + 1)) != nil)
    }
    for i in 0..<10 {
      let drawing = Drawing(id: "d\(i)", kind: .hline, points: [DrawPoint(t: 1_000, p: Double(100 + i))])
      try #require(store.add(drawing: drawing, symbol: "C\(i)USDT", now: Double(500 + i)) != nil)
    }
    return store
  }

  /// 两版行按 id 对，数「输入变了（含新出现、消失）」的行——`AlertListRecord` 是 Equatable，
  /// SwiftUI 只重画这几行。
  private func changed(_ a: [AlertListItem], _ b: [AlertListItem]) -> Set<String> {
    let old = Dictionary(uniqueKeysWithValues: a.map { ($0.id, $0) })
    let new = Dictionary(uniqueKeysWithValues: b.map { ($0.id, $0) })
    return Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
  }

  @Test("排序只在存档变了之后排一趟：读 100 遍排 1 趟，notice 变了不排，删一条再排 1 趟")
  func sortIsCached() throws {
    let store = try loaded()
    let base = store.listRowBuilds
    for _ in 0..<100 { _ = store.listRows }
    #expect(store.listRowBuilds == base + 1)
    store.notice = "随便说一句"
    _ = store.listRows
    #expect(store.listRowBuilds == base + 1, "notice 变了也重排")
    let victim = try #require(store.all.first)
    store.remove(id: victim.id)
    for _ in 0..<100 { _ = store.listRows }
    #expect(store.listRowBuilds == base + 2)
    #expect(store.listRows == AlertListItem.rows(AlertRecordText.sections(store.all)), "缓存和现排的不一样")
    print("[压测收尾·提醒总表] 190 条、读 100 遍：排 \(store.listRowBuilds - base - 1) 趟（修前 100 趟）")
  }

  @Test("删组中间一条：只有它、它的段头、段标题三行变；删卡片最后一条：再加上接班的那一行")
  func deleteTouchesOnlyAffectedRows() throws {
    let store = try loaded()
    let before = store.listRows
    let records = before.filter { if case .record = $0 { true } else { false } }.count
    // 价格段第一组（C11，最新的一组）里的第二条。
    guard case let .record(middle, _, _, _, _) = before[3] else { Issue.record("第 4 行不是记录：\(before[3])"); return }
    store.remove(id: middle.id)
    let afterMiddle = store.listRows
    let touched = changed(before, afterMiddle)
    #expect(touched == ["alert/" + middle.id, "head/price/binance/usd_m/C11USDT", "title/price"],
            "删组中间一条动到的行：\(touched.sorted())")

    // 价格段卡片的最后一条（最老那组的最后一条）。
    let priceLast = try #require(afterMiddle.lastIndex {
      if case let .record(a, _, _, _, bottom) = $0 { a.kind == .price && bottom } else { false }
    })
    guard case let .record(last, _, _, _, _) = afterMiddle[priceLast],
          case let .record(prev, _, _, _, _) = afterMiddle[priceLast - 1] else {
      Issue.record("价格段末两行不是记录"); return
    }
    store.remove(id: last.id)
    let afterLast = store.listRows
    let touched2 = changed(afterMiddle, afterLast)
    #expect(touched2.contains("alert/" + prev.id), "接班的那一行没拿到下圆角")
    #expect(touched2.count == 4, "删卡片最后一条动到的行：\(touched2.sorted())")
    if case let .record(_, _, divider, _, bottom) = afterLast.first(where: { $0.id == "alert/" + prev.id }) {
      #expect(!divider && bottom)
    }
    print("[压测收尾·提醒总表] \(records) 条记录，删一条要重画的行：\(touched.count) / \(touched2.count)（修前整页 \(records) 行 + 段头段标题全部重跑）")
  }

  @Test("摊平的首尾圆角与分隔线口径和原来整张卡片一致；复盘到点那段不出段头")
  func slicesMatchTheCard() throws {
    let store = fresh()
    _ = try #require(store.addPrice(symbol: "BTCUSDT", target: 90_000, current: 84_500, label: "a", now: 1))
    _ = try #require(store.addPrice(symbol: "ETHUSDT", target: 5_000, current: 4_000, label: "e", now: 2))
    _ = try #require(store.addPrice(symbol: "BTCUSDT", target: 91_000, current: 84_500, label: "b", now: 3))
    var due = KanpanCore.Alert(id: "r1", kind: .reviewDue, symbol: "BTCUSDT", armedAt: 1, dueAt: 2,
                               title: "BTC 到点了", created: 1)
    due.status = .fired
    store.settleReviewDue(ReviewDueAlerts.Plan(upsert: [due], remove: []))
    let shape: [String] = store.listRows.map {
      switch $0 {
      case let .title(kind, text, first): "T \(kind.rawValue) \(text) \(first)"
      case let .header(_, symbol, count, top): "H \(InstrumentID(symbol).symbol) \(count) \(top)"
      case let .record(_, withSymbol, divider, top, bottom): "R \(withSymbol) \(divider) \(top) \(bottom)"
      }
    }
    #expect(shape == [
      "T price 价格提醒 3 true",
      "H BTCUSDT 2 true",
      "R false true false false",
      "R false true false false",   // 组里最后一条但不是卡片最后一组：照原来画线
      "H ETHUSDT 1 false",
      "R false false false true",   // 卡片最后一条：不画线、下圆角
      "T reviewDue 复盘到点 1 false",
      "R true false true true",     // 复盘到点那段没有段头：第一条就是卡片的第一片
    ])
  }
}
