import Foundation
import Testing
import KanpanCore
import KanpanNetwork
@testable import KanpanMain

// P2.3：报价快照的后台写盘在开写之前先看一眼「自己被撤了没有」。
//
// `persistQuotes` 每来一次都把上一笔写盘任务 cancel 掉再起新的——那一笔拿着的是旧报价，
// 被撤了还照写，就会在新的那笔之后把旧数据盖回盘上（两个 detached 任务谁先跑没人保证）。
@Suite("P2.3 报价快照写盘认取消")
struct QuoteBookPersistTests {
  private static func tempURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("quotes-\(UUID().uuidString).json")
  }

  private static let ticker = Ticker(symbol: "BTCUSDT", last: 100_000, changePercent: 1.5,
                                     high: 101_000, low: 99_000, quoteVolume: 1e9,
                                     timeMs: Int64(Date().timeIntervalSince1970 * 1000))

  @Test("被撤掉的写盘任务一个字节都不落")
  func cancelledWriteLeavesNoFile() async {
    let url = Self.tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let task = Task.detached(priority: .utility) {
      withUnsafeCurrentTask { $0?.cancel() }
      QuoteBook.writeSnapshot([Self.ticker], to: url, log: .silent)
    }
    await task.value
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("没被撤的照常写，读得回来")
  func liveWriteLands() async {
    let url = Self.tempURL()
    defer { try? FileManager.default.removeItem(at: url) }
    let task = Task.detached(priority: .utility) {
      QuoteBook.writeSnapshot([Self.ticker], to: url, log: .silent)
    }
    await task.value
    let data = FileManager.default.contents(atPath: url.path) ?? Data()
    #expect(String(decoding: data, as: UTF8.self).contains("BTCUSDT"), "没被撤的那一笔应当照常落盘")
  }
}
