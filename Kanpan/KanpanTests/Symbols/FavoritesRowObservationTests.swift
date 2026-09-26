import Foundation
import Observation
import Testing
import KanpanCore

@testable import Kanpan

/// 观察回调是 `@Sendable` 的，不能直接改外面的 `var`；拿一个带锁的小盒子记谁被叫醒。
private final class Tally: @unchecked Sendable {
  private let lock = NSLock()
  private var hits = Set<Int>()
  func hit(_ i: Int) { lock.lock(); hits.insert(i); lock.unlock() }
  var seen: Set<Int> { lock.lock(); defer { lock.unlock() }; return hits }
}

/// 自选页按行订阅（压测收尾 2026-09-26，整机线移交第 2 项）。
///
/// 原来整页 body 在 `row(_:first:)` 里读 `model.ticker(for:)`、`historyBars`，
/// 于是任何一只跳一下，整页连同每一行一起重算，每一行还要再算一遍 `symbols`（O(自选数)）。
/// 现在整页只读名单与目录，报价由每一行的 `QuoteCell` 自己读。
///
/// 判据是观察登记（`withObservationTracking`），不是墙钟：一批报价之后整页有没有被叫醒、
/// 叫醒了几行。
@Suite("自选 · 按行订阅")
@MainActor
struct FavoritesRowObservationTests {

  private static func symbol(_ i: Int) -> String { "binance/usd_m/C\(i)USDT" }
  private static func ticker(_ i: Int, last: Double) -> Ticker {
    Ticker(symbol: symbol(i), last: last, changePercent: 1, high: last * 1.1, low: last * 0.9, quoteVolume: 1_000)
  }

  private func model(count: Int) -> SymbolPickerModel {
    let storage = MemoryPrefsStorage()
    let store = SymbolPrefsStore(storage: storage, key: "rows")
    store.save(SymbolPrefs(favorites: (0..<count).map(Self.symbol)))
    return SymbolPickerModel(tickers: (0..<count).map { Self.ticker($0, last: 100) }, store: store)
  }

  /// 整页 body 读的那一份（`FavoritesView.body` → `symbols` / `row(_:first:)` / `previewable`）：
  /// 名单、目录、报价表空不空、每一行的格子引用。
  private func readPage(_ m: SymbolPickerModel) -> [QuoteCell] {
    let order = m.prefs.favorites(in: nil)
    _ = m.hasQuotes
    return order.map { symbol in
      _ = m.info(for: symbol)
      _ = m.listing(of: symbol)
      return m.quoteCell(symbol)
    }
  }

  /// 挂一次观察，跑 `mutate`，回答挂着的那段读有没有被叫醒。
  private func fires(_ read: () -> Void, after mutate: () -> Void) -> Bool {
    let fired = Tally()
    withObservationTracking(read) { fired.hit(0) }
    mutate()
    return !fired.seen.isEmpty
  }

  @Test("300 只自选、100 批报价每批变 3 只：整页一次都不被叫醒，每批只叫醒变了的 3 行")
  func quoteBatchWakesOnlyChangedRows() {
    let count = 300, batches = 100, perBatch = 3
    let m = model(count: count)
    let cells = readPage(m)   // 第一趟把格子都建出来（建格子本身不许把整页登记到报价表上）
    var pageWakes = 0, rowWakes = 0
    for b in 0..<batches {
      let changed = (0..<perBatch).map { (b * perBatch + $0 * 97) % count }
      var batch = changed.map { Self.ticker($0, last: 100 + Double(b + 1)) }
      // 再夹一只值没变的：它不该叫醒谁。
      var still = (b * 7 + 1) % count
      while changed.contains(still) { still = (still + 1) % count }
      if let same = m.ticker(for: Self.symbol(still)) { batch.append(same) }
      let tally = Tally()
      for (i, cell) in cells.enumerated() {
        withObservationTracking({ _ = cell.ticker; _ = cell.bars }) { tally.hit(i) }
      }
      if fires({ _ = readPage(m) }, after: { m.updateQuotes(batch) }) { pageWakes += 1 }
      let woke = tally.seen
      rowWakes += woke.count
      #expect(woke == Set(changed), "第 \(b) 批叫醒的行：\(woke.sorted())，应当只有 \(changed.sorted())")
    }
    print("[压测收尾·自选按行订阅] \(count) 只 × \(batches) 批：整页被叫醒 \(pageWakes) 次、行被叫醒 \(rowWakes) 次（修前按机制：整页 \(batches) 次、行 \(count * batches) 次）")
    #expect(pageWakes == 0)
    #expect(rowWakes == batches * perBatch)
  }

  @Test("格子的口径和 ticker(for:) 一字不差：真价、退订退回种子、清空、分钟线进出")
  func cellMirrorsTickerFor() {
    let m = model(count: 4)
    let seed = Self.ticker(1, last: 7)
    m.seedTickers = { [Self.symbol(1): seed] }
    let c0 = m.quoteCell(Self.symbol(0)), c1 = m.quoteCell(Self.symbol(1)), c9 = m.quoteCell(Self.symbol(9))
    #expect(c0.ticker == m.ticker(for: Self.symbol(0)) && c0.ticker != nil)
    #expect(c9.ticker == nil)
    #expect(m.quoteCell(Self.symbol(0)) === c0, "同一只要回同一个格子")

    m.apply([Self.ticker(9, last: 3)])
    #expect(c9.ticker?.last == 3)

    m.retainQuotes(for: [Self.symbol(0)])
    #expect(c0.ticker == m.ticker(for: Self.symbol(0)) && c0.ticker != nil)
    #expect(c1.ticker == seed, "退订之后没退回种子（ticker(for:) 会回种子）")
    #expect(c9.ticker == nil)

    #expect(m.hasQuotes)
    m.clearQuotes()
    #expect(!m.hasQuotes)
    #expect(c0.ticker == nil && c1.ticker == seed)

    let bars = (0..<10).map { Bar(openTime: Int64($0) * 60_000, open: 1, high: 2, low: 0.5, close: 1.5, volume: 1) }
    m.setHistory(Self.symbol(0), bars)
    #expect(c0.bars == bars)
    // 分钟线满了挤掉最老的那一份，格子跟着清。
    for i in 100..<(100 + SymbolPickerModel.historyCapacity) { m.setHistory(Self.symbol(i), bars) }
    #expect(m.historyBars[Self.symbol(0)] == nil ? c0.bars == nil : c0.bars == bars)
  }

  @Test("报价表空 ↔ 不空只在翻的那一下通知")
  func hasQuotesOnlyNotifiesOnFlip() {
    let m = model(count: 3)
    #expect(m.hasQuotes)
    #expect(!fires({ _ = m.hasQuotes }, after: { m.apply([Self.ticker(0, last: 5)]) }))
    #expect(fires({ _ = m.hasQuotes }, after: { m.clearQuotes() }))
    #expect(fires({ _ = m.hasQuotes }, after: { m.apply([Self.ticker(0, last: 5)]) }))
  }
}

/// 自选行断线灰显的计时（整机线移交第 1 项）：口径和顶栏 bfc1c816 同一条。
@Suite("自选 · 断线计时")
@MainActor
struct LinkGraceTests {

  @Test("闪断看不见；真断满 5 秒算断；中途换档不重新起算；接上 / 不该连着就当场复原")
  func graceWindow() {
    var link = LinkGrace()
    let t0 = Date(timeIntervalSince1970: 1_000)
    #expect(LinkGrace.seconds == 5)
    #expect(MarketModel.linkGrace == LinkGrace.seconds, "顶栏和自选表的宽限不是同一个数")

    // 闪断 1 秒又接上。
    let started = link.track(waiting: true, now: t0)
    #expect(started, "起算那一刻要告诉持有者挂一拍")
    #expect(!link.isDown(now: t0.addingTimeInterval(1)))
    link.track(waiting: false, now: t0.addingTimeInterval(1))
    #expect(!link.isDown(now: t0.addingTimeInterval(60)))

    // 真断：offline → reconnecting 中途换档不重新起算。
    let t1 = t0.addingTimeInterval(100)
    let restarted = link.track(waiting: true, now: t1)
    #expect(restarted)
    let again = link.track(waiting: true, now: t1.addingTimeInterval(4))
    #expect(!again, "换档重新起算了")
    #expect(!link.isDown(now: t1.addingTimeInterval(4.9)))
    #expect(link.isDown(now: t1.addingTimeInterval(5)))
    // 一接上立刻复原。
    link.track(waiting: false, now: t1.addingTimeInterval(9))
    #expect(!link.isDown(now: t1.addingTimeInterval(9)))

    // 进后台（不该连着）也当场停表；回前台从回来那一刻重新起算。
    let t2 = t1.addingTimeInterval(100)
    link.track(waiting: true, now: t2)
    link.track(waiting: false, now: t2.addingTimeInterval(2))
    let back = t2.addingTimeInterval(600)
    let resumed = link.track(waiting: true, now: back)
    #expect(resumed)
    #expect(!link.isDown(now: back.addingTimeInterval(1)), "后台那段时长被算了进来")
    #expect(link.isDown(now: back.addingTimeInterval(5.1)))
  }
}
