import Foundation
import KanpanData

/// 设置模型的 `MarketCacheStore` 接到数据层的 `DiskMarketCache` 上（审查 24）。
///
/// 模型层（`Settings/Model/MarketCache.swift`）只认协议；认磁盘、认 `Paths` 的是数据层。
/// 两边在这一个装配文件里握手，模型层就不再反向依赖数据层。
extension DiskMarketCache: MarketCacheStore {
  func usage() async -> MarketCacheUsage {
    let f = await footprint()
    return MarketCacheUsage(available: true, snapshotBytes: f.snapshotBytes, catalogBytes: f.catalogBytes,
                            oiBytes: f.oiBytes, derivedBytes: f.derivedBytes)
  }
}

/// app 里用的那一份：真的 `DiskMarketCache`。
/// 单测里的占位 `UnavailableMarketCache` 在 `KanpanTests/Settings/UnavailableMarketCache.swift`。
enum MarketCacheFactory {
  static func make() -> any MarketCacheStore {
    DiskMarketCache()
  }
}
