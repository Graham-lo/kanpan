import Foundation
import Observation
import KanpanCore
import KanpanData

/// 存档落在哪儿。真机上是 `UserDefaults.standard`，单测里换成内存里的一份。
protocol PrefsStorage: AnyObject, Sendable {
  func prefsData(forKey key: String) -> Data?
  func setPrefsData(_ data: Data?, forKey key: String)
}

extension UserDefaults: PrefsStorage {
  func prefsData(forKey key: String) -> Data? { data(forKey: key) }
  func setPrefsData(_ data: Data?, forKey key: String) {
    if let data { set(data, forKey: key) } else { removeObject(forKey: key) }
  }
}

/// 单测与 `#Preview` 用：不碰真沙盒。
final class InMemoryPrefsStorage: PrefsStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var box: [String: Data]

  init(_ seed: [String: Data] = [:]) { box = seed }

  func prefsData(forKey key: String) -> Data? {
    lock.lock(); defer { lock.unlock() }
    return box[key]
  }

  func setPrefsData(_ data: Data?, forKey key: String) {
    lock.lock(); defer { lock.unlock() }
    box[key] = data
  }

  /// 断言用：现在盘上有哪些键。
  var keys: [String] {
    lock.lock(); defer { lock.unlock() }
    return box.keys.sorted()
  }
}

/// 四个面板共用的一份设置。主线程独占，`@Observable`，改一下就落盘。
///
/// 面板里没有「确定」也没有「取消」（§10.6）：任何一改都立刻生效、立刻存。
@MainActor
@Observable
final class PrefsStore {

  /// 当前设置。只能经 `update` 改，保证「改了必存」。
  private(set) var prefs: Prefs

  /// 最近一次要说的那句话（换下了哪个副图、参数越界、域名不对）。
  /// 面板拿它弹 toast，弹完调 `clearNotice()`。
  private(set) var notice: String?

  /// 这句话右边那颗「撤销」。nil 就是一条普通提示，不画按钮。
  ///
  /// 不参与 `@Observable` 追踪（闭包本身没法比较），但它永远和 `notice` 同一拍赋值，
  /// 视图因为读了 `notice` 就会重算，读得到最新的这一份。
  @ObservationIgnored private(set) var noticeUndo: (() -> Void)?

  /// 行情缓存占用（A6.11）。没量过是 nil，设置页进来量一次。
  private(set) var cacheUsage: MarketCacheUsage?

  @ObservationIgnored private var storage: any PrefsStorage
  @ObservationIgnored var onChange: ((Prefs) -> Void)?
  @ObservationIgnored private let cache: any MarketCacheStore

  /// 这台机器上这份设置该落在哪。
  ///
  /// 以前这段挑选埋在 `init` 里，而 `storage` 还带一个 `= UserDefaults.standard` 的
  /// 默认值——于是「不写参数」看着像「用默认的」，实际是「悄悄落到 UserDefaults」。
  /// `SymbolPrefsStore()` 就是这么把「上次看的那张图」读到另一个柜子里去的（R3-1）。
  /// 现在存哪儿必须在建store的地方写出来，这个函数只是把那句话写短一点。
  static func deviceStorage() -> any PrefsStorage {
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" else { return UserDefaults.standard }
    if let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"],
       UUID(uuidString: profile) != nil, let defaults = UserDefaults(suiteName: "kanpan.tests." + profile) {
      return defaults
    }
    return InMemoryPrefsStorage()
  }

  init(storage: any PrefsStorage,
       cache: any MarketCacheStore = MarketCacheFactory.make()) {
    let selectedStorage = storage
    self.storage = selectedStorage
    self.cache = cache
    self.prefs = PrefsStore.load(from: selectedStorage)
    // UI 测试沙盒里的常用行仍然按老的那七档铺。
    //
    // 出厂默认收成五档（5m 30m 1h 4h 1d）之后，`ChartFoundationUITests` 里
    // 直接按 `interval.chip.1m` 找 chip 的那几处就点不着了——那个文件是禁改的契约文件。
    // 那几条用例要验的是「点哪一档图就换到哪一档」，不是「出厂钉了哪几档」，所以
    // 沙盒里把 chip 铺全，真正的出厂默认交给 `PrefsDefaultsTests` 在单元层面守。
    // 只在测试沙盒、且这轮还没有任何存档时生效，用例自己钉过的照样按存档走。
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1",
       selectedStorage.prefsData(forKey: PrefsCodec.key) == nil {
      self.prefs.quickIntervals = PrefsStore.uiTestQuick
      // UI 用例要验网关那条线路（OKX 历史）时从这儿起步，不用在用例里去点设置。
      if let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_ROUTE_POLICY"],
         let policy = MarketRoutePolicy(rawValue: raw) {
        self.prefs.routePolicy = policy
      }
    }
    self.liveBarSpacing = self.prefs.barSpacing
    mirrorRoutePolicy()
  }

  /// 行情线路的真身在 `prefs.routePolicy`（随账号同步 / 访客档案），而
  /// `KanpanData` 那边的 `RoutedMarketFeed` 只认 `MarketRoutePolicyStore`。
  /// 设置每变一次就镜像过去；没变的话 `set` 自己会跳过，不会把行情重开。
  private func mirrorRoutePolicy() {
    MarketRoutePolicyStore.set(prefs.routePolicy)
  }

  /// 见上：UI 测试沙盒专用的常用行。
  static let uiTestQuick: [Interval] = [.m1, .m5, .m15, .m30, .h1, .h4, .d1]

  // ---------------------------------------------------------------- 读

  static func load(from storage: any PrefsStorage, key: String = PrefsCodec.key) -> Prefs {
    PrefsCodec.decode(storage.prefsData(forKey: key))
  }

  // ---------------------------------------------------------------- 写
  //
  // 这一层有一条通用规矩，改任何偏好之前先读一遍：
  //
  //   **内存即时，落盘节流。**
  //
  // 「体验类设置」——皮肤、根宽、副图高度、指标选择、翻转、周期……凡是属于
  // 「我习惯怎么用」的那一类，都跟着人走：所有品种、所有周期、所有页面共用一份，
  // 跨 app 重启保留。而且**一旦改动必须实时跟随**：用户改完立刻换品种、换周期、
  // 开另一张图，那一下读到的必须已经是新值。
  //
  // 所以：
  //
  // 1. **内存里那一份当场就改**，读取方一律读内存（`prefs`，或某些每帧都在变的项
  //    专门开的那个 `@ObservationIgnored` 字段，如 `liveBarSpacing`）。
  //    **任何读取路径都不许回头去读 `UserDefaults`** —— 盘上那份可能还没跟上，
  //    而且那是冷启动才需要的东西。
  // 2. **写盘可以节流**，但只在「这个值会每帧变一次」时才需要（双指缩放的根宽是
  //    唯一一例）。离散动作（点一下、双击一下、手势松手那一下）直接走 `update`，
  //    它自己会挡住没真改动的那些回调。节流只影响下次冷启动，永远不参与本程内的读取；
  //    切后台前记得把欠的那一次 flush 掉（见 `flushBarSpacing`）。
  //
  // 看到某处「手势改完了内存值却要等一会儿才更新」，那是 bug，不是设计。

  /// 唯一的改法。没真改动就不落盘，免得每次滑动都写一遍。
  func update(_ change: (inout Prefs) -> Void) {
    var next = prefs
    change(&next)
    guard next != prefs else { return }
    prefs = next
    persist()
  }

  /// 带提示的改法：`change` 返回一句话就说明这次没改成（原型的 toast）。
  func attempt(_ change: (inout Prefs) -> String?) {
    var next = prefs
    let why = change(&next)
    if let why { note(why); return }
    guard next != prefs else { return }
    prefs = next
    persist()
  }

  /// 开 / 关一个指标。
  ///
  /// 单独开一个口子而不是走 `attempt`：副图满三个时 `toggle` 是**改成了**并且带一句话
  /// （「已换下 VOL」），`attempt` 把「有话说」一律当成没改成，会把这一改吞掉。
  /// 顺手把改动前的整份 `Prefs` 扣在闭包里，toast 上那颗「撤销」按下就整份还原。
  func toggleIndicator(_ id: IndicatorID) {
    let before = prefs
    var next = prefs
    let why = next.toggle(id)
    guard next != prefs else { return }
    prefs = next
    persist()
    if let why { note(why, undo: { [weak self] in self?.restore(before) }) }
  }

  // ---------------------------------------------------------------- 图上量出来的习惯

  /// 用户此刻缩放到的根间距，**内存里的那一份**。
  ///
  /// 和 `prefs.barSpacing` 分工：这一份手一动就变，谁来读都是最新的；`prefs.barSpacing`
  /// 是落到盘上的那一份，节流之后才跟上，只管下次冷启动。用户捏完**立刻**换周期、
  /// 换品种、开另一张图，新图要按刚刚那个宽度开，读的就是这儿——不能等定时器。
  ///
  /// `@ObservationIgnored` 是有意的：它每帧都在变，不该把所有读过设置的视图每帧重算
  /// 一遍。换品种 / 换周期本来就会让 `MainScreen` 重算一次 body，那一下顺手读到的
  /// 就是新值，正好是需要它的时刻。
  @ObservationIgnored private(set) var liveBarSpacing: Double = AICoinBehavior.initialSpacing

  /// 还没落盘的那个根间距。同样不进 `@Observable` 的追踪。
  @ObservationIgnored private var pendingSpacing: Double?
  @ObservationIgnored private var spacingTask: Task<Void, Never>?

  /// 记下用户缩放到的根间距（`ChartHost` 每次视野变化都会报一次）。
  ///
  /// 分两层，缺一不可：
  ///
  /// **① 内存里立刻生效。** `liveBarSpacing` 当场就改。用户捏完立刻切周期、切品种，
  /// 新图按的必须是刚刚那个宽度——「等手停下来才算数」在这条路径上是错的。
  ///
  /// **② 写盘才节流。** 双指缩放时这个数每帧都在变，每帧写一次 `UserDefaults` 是白耗；
  /// 更要紧的是 `prefs` 是整份结构体，`@Observable` 认的是「`prefs` 这个属性被读过」，
  /// 不是里面的哪一项——每帧改一次，所有读过设置的视图每帧都要重算一遍。所以落盘等
  /// 手指停下来（400ms 内没有新值）再写一次；中途来的新值把上一轮定时器顶掉，
  /// 惯性滑行和回弹那一串也就只写最后一次。落盘只影响下次冷启动，不参与本程内的读取。
  func noteBarSpacing(_ value: Double) {
    let want = Prefs.clampSpacing(value)
    guard abs(want - liveBarSpacing) > 0.001 else { return }
    liveBarSpacing = want                       // ① 立刻
    pendingSpacing = want                       // ② 待会儿
    spacingTask?.cancel()
    spacingTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      self?.flushBarSpacing()
    }
  }

  /// 把欠着的那一次立刻落盘。切后台时叫一下——最后一次缩放刚好落在定时器里的话，
  /// 用户直接杀 app 就丢了。
  func flushBarSpacing() {
    spacingTask?.cancel(); spacingTask = nil
    guard let want = pendingSpacing else { return }
    pendingSpacing = nil
    update { $0.barSpacing = want }
  }

  /// 整份设置被换掉了（恢复出厂 / 撤销 / 换账号 / 同步下来一份）：内存里那份根间距
  /// 也得认新主人，顺手把还欠着的那一次作废——它属于上一份档案。
  private func adoptSpacing() {
    spacingTask?.cancel(); spacingTask = nil; pendingSpacing = nil
    liveBarSpacing = prefs.barSpacing
  }

  /// 记下主图 / 副图的上下翻转。
  ///
  /// 这个不节流：它是一次双击就翻一下的离散动作，一次写一次；`update` 自己会挡住
  /// 没真改动的那些回调（图每改一次状态都会报一遍）。
  func noteInversion(main: Bool, subs: Set<IndicatorID>) {
    update { $0.mainInverted = main; $0.subInverted = subs }
  }

  /// 说一句话。`undo` 给了就在 toast 右边画一颗「撤销」。
  func note(_ text: String, undo: (() -> Void)? = nil) {
    noticeUndo = undo
    notice = text
  }

  func clearNotice() { notice = nil; noticeUndo = nil }

  /// 把整份设置还原成某个时刻的样子（「撤销」走这条路）。
  func restore(_ value: Prefs) {
    clearNotice()
    guard value != prefs else { return }
    prefs = value
    adoptSpacing()
    persist()
  }

  /// 恢复出厂：把当前键抹掉，回到新默认。
  func resetToDefaults() {
    prefs = .defaults
    adoptSpacing()
    persist()
  }

  private func persist() {
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
    mirrorRoutePolicy()
    onChange?(prefs)
  }

  /// 换档案（登录 / 退登）：线路跟着档案走，登录后用的是账号里记的那条。
  func useStorage(_ storage: any PrefsStorage, prefs: Prefs) {
    self.storage = storage; self.prefs = prefs
    adoptSpacing()
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
    mirrorRoutePolicy()
  }
  func applySynced(_ value: Prefs) {
    guard value != prefs else { return }
    prefs = value; adoptSpacing()
    storage.setPrefsData(PrefsCodec.encode(value), forKey: PrefsCodec.key)
    mirrorRoutePolicy()
  }

  // ---------------------------------------------------------------- 缓存

  func refreshCacheUsage() async {
    cacheUsage = await cache.usage()
  }

  /// 清缓存（A6.11）：清完顺手再量一次，数字当场归零。
  func clearCache() async {
    await cache.clear()
    cacheUsage = await cache.usage()
    note("已清缓存")
  }
}
