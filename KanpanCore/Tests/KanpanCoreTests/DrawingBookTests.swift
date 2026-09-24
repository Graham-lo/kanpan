import Foundation
import Testing

@testable import KanpanCore

/// 画线真值（审查 23.2）：按品种的线、撤销栈、每品种上限、谁该听到哪一次变化。
@MainActor
@Suite("画线真值")
struct DrawingBookTests {
  private final class Listener {
    var changes: [DrawingBook.Change] = []
  }

  private func line(_ id: String, _ p: Double = 100) -> Drawing {
    Drawing(id: id, kind: .hline, points: [DrawPoint(t: 1_000, p: p)])
  }

  @Test("本地编辑：进撤销栈、发 .edited，没变就什么都不发")
  func commitRecordsHistory() {
    let book = DrawingBook()
    let ear = Listener()
    book.observe(ear) { ear.changes.append($0) }
    #expect(book.commit([line("a")], for: "BTCUSDT"))
    #expect(!book.commit([line("a")], for: "BTCUSDT"))
    #expect(ear.changes == [.edited(InstrumentID.canonical("BTCUSDT"))])
    #expect(book.history("BTCUSDT").canUndo)
    #expect(book.undo("BTCUSDT"))
    #expect(book.items("BTCUSDT").isEmpty)
    #expect(book.redo("BTCUSDT"))
    #expect(book.items("BTCUSDT") == [line("a")])
    #expect(ear.changes.count == 3)
  }

  @Test("一次收下整批：一步撤销，已有的 id 跳过；放不下就整批不写")
  func addIsOneStepAndRespectsLimit() {
    let book = DrawingBook()
    #expect(book.add([line("a"), line("b")], to: "BTCUSDT"))
    #expect(book.add([line("a")], to: "BTCUSDT"), "全是已有的也算成功")
    #expect(book.items("BTCUSDT").count == 2)
    #expect(book.undo("BTCUSDT") && book.items("BTCUSDT").isEmpty)
    let many = (0..<DrawArchive.perSymbolLimit).map { line("l\($0)", Double($0)) }
    #expect(book.add(many, to: "ETHUSDT"))
    #expect(!book.hasRoom("ETHUSDT"))
    #expect(!book.add([line("extra")], to: "ETHUSDT"))
    #expect(book.items("ETHUSDT").count == DrawArchive.perSymbolLimit)
  }

  @Test("整份替换：只有真变了的桶清撤销、在 .replaced 里列出来")
  func replaceReportsOnlyChangedBuckets() {
    let book = DrawingBook()
    book.commit([line("btc")], for: "BTCUSDT")
    book.commit([line("eth")], for: "ETHUSDT")
    let ear = Listener()
    book.observe(ear) { ear.changes.append($0) }
    var next = book.archive
    next["ETHUSDT"] = [line("eth", 200)]
    book.replace(next)
    let eth = InstrumentID.canonical("ETHUSDT")
    #expect(ear.changes == [.replaced([eth])])
    #expect(book.history("BTCUSDT").canUndo, "别的桶变了，这只的撤销不该丢")
    #expect(!book.history("ETHUSDT").canUndo)
    book.replace(next)
    #expect(ear.changes.count == 1, "一模一样的一份不该吵醒谁")
    book.replace(next, resetAllHistory: true)
    #expect(!book.history("BTCUSDT").canUndo, "换账号要把所有撤销栈一起丢掉")
  }

  @Test("镜像不进撤销、不发通知；偏好改了也不发")
  func mirrorIsSilent() {
    let book = DrawingBook()
    let ear = Listener()
    book.observe(ear) { ear.changes.append($0) }
    book.mirror([line("snap")], for: "BTCUSDT")
    book.preferences.magnet.toggle()
    #expect(book.items("BTCUSDT") == [line("snap")])
    #expect(!book.history("BTCUSDT").canUndo)
    #expect(ear.changes.isEmpty)
  }

  @Test("观察者按登记顺序听，主人走了自动摘掉；空撤销栈不占格子")
  func observersAreOrderedAndWeak() {
    let book = DrawingBook()
    var order: [String] = []
    let first = Listener()
    var second: Listener? = Listener()
    book.observe(first) { _ in order.append("first") }
    book.observe(second!) { _ in order.append("second") }
    book.commit([line("a")], for: "BTCUSDT")
    #expect(order == ["first", "second"])
    second = nil
    book.commit([], for: "BTCUSDT")
    #expect(order == ["first", "second", "first"])
    book.setHistory(DrawHistory(), for: "BTCUSDT")
    #expect(!book.history("BTCUSDT").canUndo)
  }
}
