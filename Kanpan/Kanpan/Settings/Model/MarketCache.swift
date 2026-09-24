import Foundation

/// 行情缓存占了多少（A6.11：设置页要显示，且有上限）。
///
/// 分开报，因为它们的性质不一样：启动快照按 (品种, 周期) 存在 `series/` 下
/// （上限 2000 对 / 512 MB，见 `SeriesStore`），exchangeInfo 是一份品种表（约 150 KB），
/// OI 归档切片是 §4.3 里唯一被放行的历史缓存（上限 20 MB、LRU），
/// `profiles/` 与板块历史是几十 KB 的小零碎。
///
/// A6.11 原来写的是「恒 < 1 MB」。那条已经作废：当时只存一对快照，现在存上千对，
/// 为的是换品种、换周期也能第一帧就有图。上限改成看得见的三个数各自封顶，
/// 合计不超过 ~540 MB——在一台 256 G、还空着 160 G 的机器上占千分之几，
/// 而且在 `Caches/` 下，系统缺空间随时能清。用磁盘换等待是划算的。
struct MarketCacheUsage: Sendable, Equatable {
  /// 数据层没接上时是 false，界面就直说「数据层未接入」，不报一个假的 0。
  var available: Bool = false
  /// `series/` 下按 (品种, 周期) 存的启动快照，条数与字节都封顶。
  var snapshotBytes: Int = 0
  /// `exchangeInfo.json`，品种表。换过行情源的人还有 `sources/<行情源>/` 那一棵
  /// （那个源自己的品种表与快照），一起算在这一笔里——分笔只为报数，不是给漏算留口子。
  var catalogBytes: Int = 0
  /// `oi/` 下按天存的归档切片。
  var oiBytes: Int = 0
  /// `profiles/<档案>/` 下那两份（报价、当日开盘价）加上 `sector-history.json`。
  /// 都是**没了还能原样取回来**的数据，所以都归清缓存管。
  var derivedBytes: Int = 0

  /// 设置页「行情缓存」那一行报的数。
  var marketBytes: Int { snapshotBytes + catalogBytes + derivedBytes }
  var totalBytes: Int { marketBytes + oiBytes }

  static let unavailable = MarketCacheUsage()

  /// 「312 KB」这种。0 就是「0 KB」，不写「无」——用户要看见它确实是 0。
  static func display(_ bytes: Int) -> String {
    if bytes >= 1024 * 1024 {
      return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
    return "\(Int((Double(bytes) / 1024).rounded())) KB"
  }
}

/// 清缓存（A6.11）。设置模型只认这一份协议，不认磁盘上的哪棵目录（审查 24）：
/// 真家伙是数据层的 `KanpanData.DiskMarketCache`，路径一律走 `KanpanData.Paths`；
/// 两者在 `Settings/MarketCacheWiring.swift` 接上，这个文件不 `import KanpanData`。
protocol MarketCacheStore: Sendable {
  func usage() async -> MarketCacheUsage
  func clear() async
}
