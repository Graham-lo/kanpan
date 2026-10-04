import Foundation
import KanpanCore
import Testing
@testable import Kanpan

/// `Habits` 这只宿主对象：开关语义、开图周期、价格轴只覆盖不回写。规则本身在 `HabitInferenceTests`。
@MainActor
@Suite("按习惯学 · 开关与接线")
struct HabitsSwitchTests {
  private final class Clock { var t: Double = 1_790_000_000 }

  private func make() -> (Habits, PrefsStore, Clock, InMemoryPrefsStorage) {
    let clock = Clock()
    let logBox = InMemoryPrefsStorage()
    let habits = Habits(storage: logBox, now: { clock.t }, dwellScale: 1)
    let store = PrefsStore(storage: InMemoryPrefsStorage(), cache: UnavailableMarketCache())
    habits.bind(store)
    return (habits, store, clock, logBox)
  }

  private func focus(_ symbol: String, _ iv: Interval, _ mode: PriceMode = .log, visible: Bool = true) -> HabitFocus {
    HabitFocus(symbol: symbol, interval: iv, category: .crypto, priceMode: mode, visible: visible)
  }

  /// 在 BTC 4 小时上停 `seconds` 秒，然后切走（切到不可见）。
  private func dwell(_ habits: Habits, _ clock: Clock, _ symbol: String, _ iv: Interval, _ seconds: Double) {
    habits.setFocus(focus(symbol, iv))
    clock.t += seconds
    habits.setFocus(focus(symbol, iv, visible: false))
  }

  @Test("出厂开着；停够了学到这只的周期，回来按它开；和眼下一样就不换")
  func learnsOpeningInterval() {
    let (habits, store, clock, _) = make()
    #expect(store.prefs.habitLearning)
    #expect(store.prefs.learnedDefaults.isEmpty)
    dwell(habits, clock, "BTCUSDT", .h4, 300)
    #expect(store.prefs.learnedDefaults.interval(for: "binance/usd_m/BTCUSDT") == .h4)
    #expect(habits.opening(symbol: "BTCUSDT", info: nil, current: .h1) == .h4)
    #expect(habits.opening(symbol: "BTCUSDT", info: nil, current: .h4) == nil)
    #expect(habits.opening(symbol: "ETHUSDT", info: nil, current: .h1) == nil)
    // 钉住的周期条从来不碰。
    #expect(store.prefs.quickIntervals == Prefs.defaults.quickIntervals)
  }

  @Test("关掉：结论清空、日志删掉、不再记，开图回到原来的行为")
  func switchingOffClearsAndStops() throws {
    let (habits, store, clock, logBox) = make()
    dwell(habits, clock, "BTCUSDT", .h4, 300)
    #expect(!store.prefs.learnedDefaults.isEmpty)
    #expect(!HabitLogStore(storage: logBox).load(owner: store.stamp.owner).events.isEmpty)

    habits.setEnabled(false)
    #expect(!store.prefs.habitLearning)
    #expect(store.prefs.learnedDefaults.isEmpty)
    #expect(HabitLogStore(storage: logBox).load(owner: store.stamp.owner).events.isEmpty)
    #expect(habits.opening(symbol: "BTCUSDT", info: nil, current: .h1) == nil)

    dwell(habits, clock, "BTCUSDT", .h4, 600)
    habits.noteSectorWindow(market: .crypto, window: .d5)
    #expect(store.prefs.learnedDefaults.isEmpty)
    #expect(HabitLogStore(storage: logBox).load(owner: store.stamp.owner).events.isEmpty)

    habits.setEnabled(true)
    #expect(store.prefs.habitLearning)
    #expect(habits.opening(symbol: "BTCUSDT", info: nil, current: .h1) == nil)
  }

  @Test("清除已学到的：结论与日志清掉，开关不动，之后接着学")
  func clearKeepsSwitch() {
    let (habits, store, clock, logBox) = make()
    dwell(habits, clock, "BTCUSDT", .h4, 300)
    habits.clearLearned()
    #expect(store.prefs.habitLearning)
    #expect(store.prefs.learnedDefaults.isEmpty)
    #expect(HabitLogStore(storage: logBox).load(owner: store.stamp.owner).events.isEmpty)
    dwell(habits, clock, "BTCUSDT", .d1, 300)
    #expect(store.prefs.learnedDefaults.interval(for: "binance/usd_m/BTCUSDT") == .d1)
  }

  @Test("价格轴：学到的只盖在图的输入上，不写回设置；关掉当场回到设置那档；百分比不被盖")
  func priceAxisIsAnOverlay() {
    let (habits, store, clock, _) = make()
    store.update { $0.priceMode = .linear }
    habits.setFocus(focus("BTCUSDT", .h1, .linear))
    habits.notePriceAxisPicked(.log)
    #expect(store.prefs.learnedDefaults.priceMode(for: .crypto) == .log)
    clock.t += 10
    #expect(store.prefs.priceMode == .linear)
    #expect(habits.chartPrefs(store.prefs).priceMode == .log)
    #expect(habits.effectivePriceMode(store.prefs) == .log)

    store.update { $0.priceMode = .percent }
    #expect(habits.chartPrefs(store.prefs).priceMode == .percent)
    store.update { $0.priceMode = .linear }

    habits.setEnabled(false)
    #expect(habits.chartPrefs(store.prefs).priceMode == .linear)
  }

  @Test("板块：学到的那档每次启动每个市场只落一次")
  func sectorAppliedOncePerLaunch() {
    let (habits, store, _, _) = make()
    for _ in 0..<3 { habits.noteSectorWindow(market: .us, window: .d5) }
    #expect(store.prefs.learnedDefaults.window(for: .us) == .d5)
    // 选过了（这一趟已经算落过）就不再替他改。
    #expect(habits.sectorWindowToApply(market: .us, current: .today) == nil)
    let (fresh, freshStore, _, _) = make()
    freshStore.update { $0.learnedDefaults = store.prefs.learnedDefaults }
    #expect(fresh.sectorWindowToApply(market: .us, current: .today) == .d5)
    #expect(fresh.sectorWindowToApply(market: .us, current: .today) == nil)
    #expect(fresh.sectorWindowToApply(market: .crypto, current: .today) == nil)
  }

  @Test("波动提醒：连着两次没点开升一档，点开降回来；关掉一律 1 倍")
  func watchMoveFactor() {
    let (habits, store, clock, _) = make()
    let key = "binance/usd_m/SOLUSDT"
    for _ in 0..<2 {
      habits.noteWatchMoveFired("SOLUSDT")
      clock.t += 1_000
    }
    habits.noteWatchMoveFired("SOLUSDT")   // 让前两次结算
    #expect(habits.watchMoveFactor(for: key) > 1)
    let raised = habits.watchMoveFactor(for: key)
    clock.t += 60
    _ = habits.opening(symbol: "SOLUSDT", info: nil, current: .h1)
    #expect(habits.watchMoveFactor(for: key) < raised)
    #expect(LearnedDefaults.factorRange.contains(habits.watchMoveFactor(for: key)))
    habits.setEnabled(false)
    #expect(habits.watchMoveFactor(for: key) == 1)
    #expect(store.prefs.learnedDefaults.watchMove.isEmpty)
  }

  // MARK: - 审查 D-02：计时中换了人

  @Test("计时中换了人、track 还没轮到：上一个人那段停留谁的日志都不进")
  func dwellDoesNotCrossAnOwnerSwitch() async {
    let (habits, store, clock, logBox) = make()
    store.useStorage(InMemoryPrefsStorage(), prefs: .defaults, arrival: .ownerSwitched, owner: "acct:A")
    for _ in 0..<5 { await Task.yield() }
    habits.setFocus(focus("BTCUSDT", .h4))
    clock.t += 600
    // 换号：档案先换（`prepare` 的提交段），`track()` 要等下一跳；这中间切走那一下不能把 A 的
    // 十分钟记成 B 的。
    store.useStorage(InMemoryPrefsStorage(), prefs: .defaults, arrival: .ownerSwitched, owner: "acct:B")
    habits.setFocus(focus("BTCUSDT", .h4, visible: false))
    #expect(store.prefs.learnedDefaults.isEmpty)
    #expect(HabitLogStore(storage: logBox).load(owner: "acct:B").events.isEmpty)
    #expect(HabitLogStore(storage: logBox).load(owner: "acct:A").events.isEmpty)
  }

  @Test("换了人（两个号设置一模一样也算）：新人的停留照常记，板块窗口按新人学到的再摆一次")
  func newOwnerStartsClean() async {
    let (habits, store, clock, logBox) = make()
    store.useStorage(InMemoryPrefsStorage(), prefs: .defaults, arrival: .ownerSwitched, owner: "acct:A")
    for _ in 0..<5 { await Task.yield() }
    habits.noteSectorWindow(market: .crypto, window: .d5)  // A 这次启动在板块页亲手选过
    store.useStorage(InMemoryPrefsStorage(), prefs: .defaults, arrival: .ownerSwitched, owner: "acct:B")
    for _ in 0..<5 { await Task.yield() }
    dwell(habits, clock, "BTCUSDT", .h4, 300)
    #expect(store.prefs.learnedDefaults.interval(for: "binance/usd_m/BTCUSDT") == .h4)
    #expect(!HabitLogStore(storage: logBox).load(owner: "acct:B").events.isEmpty)
    #expect(!HabitLogStore(storage: logBox).load(owner: "acct:B").events.contains { $0.kind == .sectorWindow })
    // B 学到「5 日」：这次启动对 B 还没摆过，要摆。
    store.update { $0.learnedDefaults.sectorWindow[SectorMarket.crypto.rawValue] = .init(v: "d5", n: 3, at: clock.t) }
    #expect(habits.sectorWindowToApply(market: .crypto, current: .today) == .d5)
  }
}
