import Foundation
import Observation
import KanpanCore

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

  init(storage: any PrefsStorage = UserDefaults.standard,
       cache: any MarketCacheStore = MarketCacheFactory.make()) {
    let selectedStorage: any PrefsStorage
    if ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" {
      if let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"],
         UUID(uuidString: profile) != nil, let defaults = UserDefaults(suiteName: "kanpan.tests." + profile) {
        selectedStorage = defaults
      } else { selectedStorage = InMemoryPrefsStorage() }
    } else { selectedStorage = storage }
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
    }
  }

  /// 见上：UI 测试沙盒专用的常用行。
  static let uiTestQuick: [Interval] = [.m1, .m5, .m15, .m30, .h1, .h4, .d1]

  // ---------------------------------------------------------------- 读

  static func load(from storage: any PrefsStorage, key: String = PrefsCodec.key) -> Prefs {
    PrefsCodec.decode(storage.prefsData(forKey: key))
  }

  // ---------------------------------------------------------------- 写

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
    persist()
  }

  /// 恢复出厂：把当前键抹掉，回到新默认。
  func resetToDefaults() {
    prefs = .defaults
    persist()
  }

  private func persist() {
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
    onChange?(prefs)
  }

  func useStorage(_ storage: any PrefsStorage, prefs: Prefs) {
    self.storage = storage; self.prefs = prefs
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
  }
  func applySynced(_ value: Prefs) {
    guard value != prefs else { return }
    prefs = value; storage.setPrefsData(PrefsCodec.encode(value), forKey: PrefsCodec.key)
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
