import Foundation
import Testing
import KanpanCore
@testable import Kanpan

/// 搜索页对比模式的判定（2026-10-05 顶栏加号）：行尾四态、点了之后做什么、满三只的那句提示。
@Suite("对比搜索模式")
struct CompareSearchModeTests {
  private let eth = "binance/usd_m/ETHUSDT"
  private let sol = "binance/usd_m/SOLUSDT"
  private let doge = "binance/usd_m/DOGEUSDT"
  private let xrp = "binance/usd_m/XRPUSDT"
  private let btc = "binance/usd_m/BTCUSDT"

  @Test("主图那只整行禁用，点了什么都不做")
  func mainRow() {
    let mode = CompareSearchMode(keys: [eth], current: btc)
    #expect(mode.state(for: btc) == .main)
    #expect(mode.action(for: btc) == .none)
  }

  @Test("主图那只按规范键认：传裸代号也算主图")
  func mainRowCanonical() {
    let mode = CompareSearchMode(keys: [], current: "BTCUSDT")
    #expect(mode.current == InstrumentID.canonical("BTCUSDT"))
    #expect(mode.state(for: InstrumentID.canonical("BTCUSDT")) == .main)
  }

  @Test("没满：没加的是 ＋，加了的是选中态，再点拿掉")
  func addAndRemove() {
    let mode = CompareSearchMode(keys: [eth], current: btc)
    #expect(mode.state(for: sol) == .add)
    #expect(mode.action(for: sol) == .add(sol))
    #expect(mode.state(for: eth) == .added)
    #expect(mode.action(for: eth) == .remove(eth))
    #expect(!mode.isFull)
  }

  @Test("满三只：别的行退成「已满」，点了只提示；已选的仍能拿掉；主图仍是主图")
  func full() {
    let mode = CompareSearchMode(keys: [eth, sol, doge], current: btc)
    #expect(mode.isFull)
    #expect(mode.state(for: xrp) == .full)
    #expect(mode.action(for: xrp) == .rejectFull)
    #expect(mode.action(for: sol) == .remove(sol))
    #expect(mode.state(for: btc) == .main)
  }

  @Test("提示文案跟上限走")
  func notice() {
    #expect(Prefs.maxCompareSymbols == 3)
    #expect(CompareSearchMode.fullNotice == "最多对比 3 个品种")
  }

  @Test("判定与落盘那条规则一致：判「加」的，`addCompareSymbol` 一定加得进去")
  func agreesWithPrefs() {
    var prefs = Prefs()
    for key in [eth, sol, doge, xrp] {
      let mode = CompareSearchMode(keys: prefs.compareSymbols, current: btc)
      let added = prefs.addCompareSymbol(key, current: mode.current)
      #expect(added == (mode.action(for: key) == .add(key)))
    }
    #expect(prefs.compareSymbols == [eth, sol, doge])
  }
}
