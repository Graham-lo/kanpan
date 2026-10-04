import Foundation
import KanpanCore
import Observation
import SwiftUI

/// 此刻屏幕上在看什么。宿主（`MainScreen`）按自己的状态拼好交进来，这里只管计时。
struct HabitFocus: Equatable {
  /// 品种规范键。
  var symbol: String
  var interval: Interval
  /// 这只的类别；品种表里还查不到就是 nil（这段不记价格轴）。
  var category: HabitCategory?
  /// 设置里的那一档价格轴（不是学到的那档），它一变就算换了一段。
  var priceMode: PriceMode
  /// 图真的在人眼前：行情页、前台、不在复盘 / 预览里。
  var visible: Bool
}

/// 「按我的习惯自动调整」：日志、推断、结论、开关，全在这一个模块里。
///
/// 图表、板块、提醒只通过这里几个方法读结论、报事件，不自己判断任何一条规则：
///
/// | 谁 | 读 | 报 |
/// |---|---|---|
/// | 换品种（`picker.onPick`） | `opening(symbol:info:)` → 这只该开的周期 | 同一个调用里记「点开了刚响过的那只」 |
/// | 图的输入 | `chartPrefs(_:)` → 价格轴换成这一类学到的那档 | `setFocus(_:)` 计停留 |
/// | 图表设置的价格轴 | `effectivePriceMode(_:)` | `notePriceAxisPicked(_:)` |
/// | 板块页 | `sectorWindowToApply(market:)` | `noteSectorWindow(market:window:)` |
/// | 自选波动提醒 | `watchMoveFactor(for:)` | `noteWatchMoveFired(_:)` |
///
/// 开关、结论都在 `Prefs` 里（`habitLearning` / `learnedDefaults`，随账号同步）；
/// 日志落在本机、一个档案一份（`HabitLogStore`）。
@MainActor
@Observable
final class Habits {
  /// 此刻图上那只的类别。图的价格轴要看它，所以单独成一项可观察的状态。
  private(set) var category: HabitCategory?

  @ObservationIgnored private weak var store: PrefsStore?
  @ObservationIgnored private var logStore: HabitLogStore
  @ObservationIgnored private var log = HabitLog()
  @ObservationIgnored private var loadedOwner: String?
  @ObservationIgnored private let now: () -> Double
  /// 停留秒数乘几。只有 UI 用例会改（`KANPAN_TEST_HABIT_SCALE`），真机恒为 1。
  @ObservationIgnored private let dwellScale: Double

  @ObservationIgnored private var focus: HabitFocus?
  /// 正在计时的那一段停留，连同它是**谁的**（`store.stamp.owner`）。换了档案，上一个人
  /// 那段停留不能记进下一个人的日志、推成他的结论（审查 D-02）。
  @ObservationIgnored private var segment: (focus: HabitFocus, mode: PriceMode, start: Double, owner: String)?
  /// 这次启动里已经按学到的值摆过「今日 / 5 日」的市场：一次启动只摆一次，之后人怎么点就怎么是。
  @ObservationIgnored private var sectorApplied: Set<SectorMarket> = []
  /// `sectorApplied` 是谁的。换了人就作废重来——不靠 `track()` 看见（两个号设置一模一样时
  /// `prefs` 没变，观察不一定通知），每次用之前直接对一下属主。
  @ObservationIgnored private var sectorOwner: String?
  /// 上一次看到的开关与结论（判断「是不是别处关掉 / 清掉了」）。
  @ObservationIgnored private var lastSeen: (owner: String, enabled: Bool, empty: Bool)?

  init(storage: any PrefsStorage = PrefsStore.deviceStorage(),
       now: @escaping () -> Double = { Date().timeIntervalSince1970 },
       dwellScale: Double = Habits.environmentScale()) {
    logStore = HabitLogStore(storage: storage)
    self.now = now
    self.dwellScale = dwellScale
  }

  /// 接上设置。之后开关、结论的任何一变都会被看见（`withObservationTracking`，和
  /// `WatchMoveMonitor.follow` 同一个做法）。
  func bind(_ store: PrefsStore) {
    self.store = store
    track()
  }

  private var enabled: Bool { store?.prefs.habitLearning ?? false }
  private var learned: LearnedDefaults { store?.prefs.learnedDefaults ?? .empty }

  // ---------------------------------------------------------------- 读结论

  /// 换到这只品种。返回这只该开的周期（学到了、开关开着、和现在的不一样才有）；
  /// 同时记下「刚响过提醒的那只被点开了」。**只在换品种那一下问一次**——
  /// 人在这一趟里自己切了周期，就不会再被改回去。
  func opening(symbol: String, info: SymbolInfo?, current: Interval) -> Interval? {
    let key = InstrumentID.canonical(symbol)
    if let info { setCategory(HabitCategory(info)) }
    guard enabled, !key.isEmpty else { return nil }
    noteOpened(key)
    guard let learned = learned.interval(for: key), learned != current else { return nil }
    return learned
  }

  /// 图上真正用的价格轴：设置里是线性 / 对数时，换成这一类学到的那档；百分比、没学到、
  /// 开关关着都照设置。**不写回 `Prefs`**——`priceMode` 是指标布局的一部分，一人一份、
  /// 所有周期与所有设备共用（2026-10-03 起）；学到的是「这一类品种」的那档，写回去就把
  /// 他亲手设的那档在所有品种、所有设备上一起改掉了。
  func effectivePriceMode(_ prefs: Prefs) -> PriceMode {
    guard prefs.habitLearning, prefs.priceMode != .percent, let category,
          let mode = prefs.learnedDefaults.priceMode(for: category) else { return prefs.priceMode }
    return mode
  }

  /// 喂给图的那份设置。
  func chartPrefs(_ prefs: Prefs) -> Prefs {
    let mode = effectivePriceMode(prefs)
    guard mode != prefs.priceMode else { return prefs }
    var out = prefs
    out.priceMode = mode
    return out
  }

  /// 板块页出现时问一次：这个市场这次启动还没摆过、学到了、和现在的不一样，才返回。
  func sectorWindowToApply(market: SectorMarket, current: SectorWindow) -> SectorWindow? {
    guard enabled else { return nil }
    resetSectorAppliedIfOwnerChanged()
    guard !sectorApplied.contains(market) else { return nil }
    sectorApplied.insert(market)
    guard let window = learned.window(for: market), window != current else { return nil }
    return window
  }

  /// 自选波动提醒幅度要乘的倍数。
  func watchMoveFactor(for symbol: String) -> Double {
    guard enabled else { return 1 }
    return learned.watchMoveFactor(for: symbol)
  }

  // ---------------------------------------------------------------- 报事件

  /// 屏幕上在看的东西变了（换品种、换周期、切价格轴、进出后台、切走行情页）。
  func setFocus(_ next: HabitFocus) {
    if let c = next.category { setCategory(c) }
    guard next != focus else { return }
    closeSegment()
    focus = next
    startSegment()
  }

  /// 屏上看得见、开关开着，就从此刻起给眼前这一屏计时。`mode` 不给就按此刻图上用的那档。
  private func startSegment(mode: PriceMode? = nil) {
    guard let focus, focus.visible, enabled else { return }
    segment = (focus, mode ?? effectivePriceMode(for: focus), now(), store?.stamp.owner ?? "")
  }

  /// 在图表设置里亲手切了价格轴。
  func notePriceAxisPicked(_ mode: PriceMode) {
    guard enabled, let category, LearnedDefaults.axisValues.contains(mode.rawValue) else { return }
    // 切之前那段按旧的那档记完。
    closeSegment()
    record(.init(t: now(), kind: .axisPick, key: category.rawValue, value: mode.rawValue))
    startSegment(mode: mode)
  }

  /// 板块页选了一档。
  func noteSectorWindow(market: SectorMarket, window: SectorWindow) {
    guard enabled, LearnedDefaults.sectorValues.contains(window.rawValue) else { return }
    resetSectorAppliedIfOwnerChanged()
    sectorApplied.insert(market)
    record(.init(t: now(), kind: .sectorWindow, key: market.rawValue, value: window.rawValue))
  }

  /// 自选波动提醒响了。
  func noteWatchMoveFired(_ symbol: String) {
    let key = InstrumentID.canonical(symbol)
    guard enabled, !key.isEmpty else { return }
    record(.init(t: now(), kind: .moveFired, key: key))
  }

  // ---------------------------------------------------------------- 开关

  /// 设置里那颗开关。关掉：结论立刻清空（图的价格轴当场回到设置那档）、日志删掉、不再记。
  func setEnabled(_ on: Bool) {
    guard let store else { return }
    if on {
      store.updateByHand { $0.habitLearning = true }
    } else {
      segment = nil
      withLog { $0.removeAll() }
      store.updateByHand { $0.habitLearning = false; $0.learnedDefaults = .empty }
    }
  }

  /// 「清除已学到的」：结论与日志都清掉，开关不动。
  func clearLearned() {
    segment = nil
    withLog { $0.removeAll() }
    store?.update { $0.learnedDefaults = .empty }
    startSegment()
  }

  // ---------------------------------------------------------------- 内部

  private func resetSectorAppliedIfOwnerChanged() {
    let owner = store?.stamp.owner ?? ""
    guard sectorOwner != owner else { return }
    sectorOwner = owner
    sectorApplied = []
  }

  private func setCategory(_ value: HabitCategory) {
    if category != value { category = value }
  }

  private func effectivePriceMode(for focus: HabitFocus) -> PriceMode {
    guard let store else { return focus.priceMode }
    var prefs = store.prefs
    prefs.priceMode = focus.priceMode
    return effectivePriceMode(prefs)
  }

  /// 刚响过提醒（15 分钟内、还没点开过）的那只被打开了，记一笔「点开」。
  private func noteOpened(_ key: String) {
    let t = now()
    let events = withLog { $0 }.events
    guard let fired = events.last(where: { $0.kind == .moveFired && $0.key == key }),
          t - fired.t <= HabitInference.moveOpenWindow,
          !events.contains(where: { $0.kind == .moveOpened && $0.key == key && $0.t >= fired.t }) else { return }
    record(.init(t: t, kind: .moveOpened, key: key))
  }

  private func closeSegment() {
    guard let segment else { return }
    self.segment = nil
    // 计时的时候是另一个人的档案（换号 / 退登之后 `track()` 还没轮到）：这段不算谁的。
    guard enabled, segment.owner == (store?.stamp.owner ?? "") else { return }
    let seconds = min(HabitInference.maxDwell, (now() - segment.start) * dwellScale)
    guard seconds >= HabitInference.minDwell else { return }
    let focus = segment.focus
    let key = InstrumentID.canonical(focus.symbol)
    guard !key.isEmpty else { return }
    let t = now()
    var batch = [HabitEvent(t: t, kind: .interval, key: key, value: focus.interval.rawValue, w: seconds)]
    if let category = focus.category, LearnedDefaults.axisValues.contains(segment.mode.rawValue) {
      batch.append(.init(t: t, kind: .axisDwell, key: category.rawValue, value: segment.mode.rawValue, w: seconds))
    }
    record(batch)
  }

  private func record(_ event: HabitEvent) { record([event]) }

  /// 记下、落盘、重推结论；结论变了才写回设置（写回走 `update`，随账号同步）。
  private func record(_ events: [HabitEvent]) {
    guard enabled, let store else { return }
    let t = now()
    let log = withLog { log in
      for event in events { log.append(event, now: t) }
    }
    let local = HabitInference.learn(from: log, now: t)
    let next = LearnedDefaults.merged(synced: store.prefs.learnedDefaults, local: local, now: t)
    if next != store.prefs.learnedDefaults { store.update { $0.learnedDefaults = next } }
  }

  /// 读 / 改这个档案的日志。档案换人了先换一份日志。
  @discardableResult
  private func withLog(_ change: (inout HabitLog) -> Void = { _ in }) -> HabitLog {
    let owner = store?.stamp.owner ?? ""
    if owner != loadedOwner {
      log = logStore.load(owner: owner)
      loadedOwner = owner
      log.prune(now: now())
    }
    let before = log
    change(&log)
    if log != before { logStore.save(log, owner: owner) }
    return log
  }

  /// 盯着开关与结论：别的设备关掉了 / 清掉了（或者「恢复默认」把结论清空了），
  /// 本机的日志也跟着删——不然下一段停留又把旧依据推回去、再同步上去。
  private func track() {
    guard let store else { return }
    let seen = withObservationTracking {
      (store.stamp.owner, store.prefs.habitLearning, store.prefs.learnedDefaults.isEmpty)
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.track() }
    }
    defer { lastSeen = (seen.0, seen.1, seen.2) }
    guard let last = lastSeen else { return }
    guard last.owner == seen.0 else {
      // 换了人：上一个人那段停留作废（`closeSegment` 也按属主挡着），「这次启动摆过的板块窗口」
      // 也是上一个人的——新档案里学到的值照样要摆一次。眼前这一屏从现在起算新人的。
      segment = nil
      resetSectorAppliedIfOwnerChanged()
      startSegment()
      return
    }
    let turnedOff = last.enabled && !seen.1
    let cleared = !last.empty && seen.2
    if turnedOff || cleared {
      segment = nil
      withLog { $0.removeAll() }
    }
    if !seen.1 { segment = nil }
  }

  static func environmentScale() -> Double {
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let raw = env["KANPAN_TEST_HABIT_SCALE"], let v = Double(raw), v > 0 { return v }
    #endif
    return 1
  }
}

private struct HabitsKey: EnvironmentKey { static let defaultValue: Habits? = nil }
extension EnvironmentValues {
  /// 没注入（预览、单测里的面板）就是 nil：读结论照设置、报事件什么都不做。
  var habits: Habits? {
    get { self[HabitsKey.self] }
    set { self[HabitsKey.self] = newValue }
  }
}
