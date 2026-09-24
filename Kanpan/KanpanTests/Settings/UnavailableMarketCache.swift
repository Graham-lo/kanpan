@testable import Kanpan

/// 单测用的行情缓存占位：如实说没接上，清也不清。
///
/// 以前它留在 app 源码里，给没链数据层的 `Kanpan/Settings` 测试壳包当 `#else` 那一支；
/// 壳包并进 KanpanTests 之后 app 永远链着 `KanpanData`，这一份只剩单测要用。
struct UnavailableMarketCache: MarketCacheStore {
  func usage() async -> MarketCacheUsage { .unavailable }
  func clear() async {}
}
