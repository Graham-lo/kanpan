import Foundation
import KanpanCore
import Testing
import UIKit

@testable import Kanpan

/// 体感整改（2026-10-07）· 列表行上的「先去拉」：按下就拉、搜索结果稳定拉前三、
/// 自选 / 搜索行露面攒一屏拉。
@MainActor
@Suite("列表行预热")
struct SymbolWarmupTests {
  @Test("搜索结果只拉前三只，重复的不算")
  func hitsAreTopThreeDistinct() {
    #expect(SymbolWarmup.hitsToWarm(["A", "B", "A", "C", "D"]) == ["A", "B", "C"])
    #expect(SymbolWarmup.hitsToWarm(["A"]) == ["A"])
    #expect(SymbolWarmup.hitsToWarm([]) == [])
  }

  @Test("露面行一批拉最后露面的那一屏，正开着的那只不拉")
  func rowBatchIsLastScreenWithoutCurrent() {
    let rows = (0..<30).map { InstrumentID.canonical("S\($0)USDT") }
    let pending = MarketModel.enqueueListStats([], rows)
    let batch = MarketModel.rowWarmBatch(pending, current: "S29USDT")
    #expect(batch.count == MarketModel.rowWarmLimit)
    #expect(!batch.contains(InstrumentID.canonical("S29USDT")))
    #expect(batch.last == InstrumentID.canonical("S28USDT"))
  }

  @Test("自选行露面：顶栏统计与 K 线快照两摊都排上；进后台一起收")
  func prefetchRowsQueuesAndCancelsInBackground() {
    let model = MarketModel(symbol: "BTCUSDT", interval: .h1, endpoints: .default)
    model.prefetchRows(["ETHUSDT"])
    #expect(model.prefetchInFlight)
    model.enterBackground()
    #expect(!model.prefetchInFlight)
    model.stop()
  }

  @Test("按下识别器：按下那一刻报一声，不挡点按与拖动")
  func touchDownFiresAndFails() {
    let recognizer = TouchDownRecognizer()
    // 挂在一块视图上：没有宿主视图的识别器不接受状态变化。
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))
    host.addGestureRecognizer(recognizer)
    var fired = 0
    recognizer.onDown = { fired += 1 }
    recognizer.touchesBegan([], with: UIEvent())
    #expect(fired == 1)
    // 「随即作废」那一下只在真的触摸投递里生效（脱离事件循环时 UIKit 不收状态变化），
    // 由模拟器上点行照常进图来验；这里守的是它不挡任何别的识别器。
    #expect(!recognizer.canPrevent(UITapGestureRecognizer()))
    #expect(!recognizer.canBePrevented(by: UIPanGestureRecognizer()))
  }
}
