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

  /// 最近一次被拒绝的动作要说的那句话（副图开满三个、参数越界、域名不对）。
  /// 面板拿它弹 toast，弹完调 `clearNotice()`。
  private(set) var notice: String?

  /// 行情缓存占用（A6.11）。没量过是 nil，设置页进来量一次。
  private(set) var cacheUsage: MarketCacheUsage?

  @ObservationIgnored private let storage: any PrefsStorage
  @ObservationIgnored private let cache: any MarketCacheStore

  init(storage: any PrefsStorage = UserDefaults.standard,
       cache: any MarketCacheStore = MarketCacheFactory.make()) {
    let selectedStorage: any PrefsStorage = ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1"
      ? InMemoryPrefsStorage() : storage
    self.storage = selectedStorage
    self.cache = cache
    self.prefs = PrefsStore.load(from: selectedStorage)
  }

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
    if let why { notice = why; return }
    guard next != prefs else { return }
    prefs = next
    persist()
  }

  func clearNotice() { notice = nil }

  /// 恢复出厂：把当前键抹掉，回到新默认。
  func resetToDefaults() {
    prefs = .defaults
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
  }

  private func persist() {
    storage.setPrefsData(PrefsCodec.encode(prefs), forKey: PrefsCodec.key)
  }

  // ---------------------------------------------------------------- 缓存

  func refreshCacheUsage() async {
    cacheUsage = await cache.usage()
  }

  /// 清缓存（A6.11）：清完顺手再量一次，数字当场归零。
  func clearCache() async {
    await cache.clear()
    cacheUsage = await cache.usage()
    notice = "已清掉启动快照与品种表缓存"
  }
}
