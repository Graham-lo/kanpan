import Foundation

#if canImport(KanpanData)
import KanpanData
#endif

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

/// 清缓存（A6.11）。**路径一律走 `KanpanData.Paths`**，这里不自己拼目录。
protocol MarketCacheStore: Sendable {
  func usage() async -> MarketCacheUsage
  func clear() async
}

/// 数据层还没链进 app target 时的占位：如实说没接上。
struct UnavailableMarketCache: MarketCacheStore {
  func usage() async -> MarketCacheUsage { .unavailable }
  func clear() async {}
}

#if canImport(KanpanData)
/// 真家伙：`Library/Caches/kanpan` 下那三样，位置全部问 `Paths` 要。
struct DiskMarketCache: MarketCacheStore {
  var paths: Paths

  init(paths: Paths = .caches()) { self.paths = paths }

  func usage() async -> MarketCacheUsage {
    let p = paths
    return await Task.detached(priority: .utility) {
      MarketCacheUsage(
        available: true,
        snapshotBytes: DiskMarketCache.size(of: p.series) + DiskMarketCache.size(of: p.snapshot),
        catalogBytes: DiskMarketCache.size(of: p.exchangeInfo) + DiskMarketCache.size(of: p.sources),
        oiBytes: DiskMarketCache.size(of: p.oi),
        derivedBytes: DiskMarketCache.size(of: p.profiles) + DiskMarketCache.size(of: p.sectorHistory))
    }.value
  }

  /// 清的是**这几处**，不是「把缓存根目录整棵删」。
  ///
  /// 逐个点名而不是删根，是因为判据只有一句：**没了还能原样重新取回来的才准清**。
  /// 删根那种写法迟早会把某个不该清的东西一起带走——真正随人走的那些
  /// （偏好、图表布局、自选与分类、画线、搜索历史）压根不在这棵树下，
  /// 但下一个往 `Paths` 里加路径的人不该靠运气。
  ///
  /// `profiles` 是按身份分的那一层，整棵删：报价和开盘价是取得回来的数据，
  /// 分目录只为了不串号，不是把它们升格成随人走的状态。
  ///
  /// `sources` 同理，是按行情源分的那一层（那个源自己的品种表与快照）。它以前没被点到名，
  /// 于是换过一次行情源之后那棵树就永远躺在盘上：清缓存清不掉，用量也不算它。
  func clear() async {
    let p = paths
    await Task.detached(priority: .utility) {
      let fm = FileManager.default
      for url in [p.series, p.snapshot, p.exchangeInfo, p.sources, p.oi, p.profiles, p.sectorHistory] {
        try? fm.removeItem(at: url)
      }
    }.value
  }

  /// 单个文件或整棵目录占的字节。算的是**实际分配**，跟系统「储存空间」对得上。
  static func size(of url: URL) -> Int {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue { return allocated(url) }
    guard let walker = fm.enumerator(at: url,
                                     includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey],
                                     options: [.skipsHiddenFiles]) else { return 0 }
    var total = 0
    for case let child as URL in walker {
      let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
      guard values?.isRegularFile == true else { continue }
      total += allocated(child)
    }
    return total
  }

  private static func allocated(_ url: URL) -> Int {
    let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
    let values = try? url.resourceValues(forKeys: keys)
    return values?.totalFileAllocatedSize ?? values?.fileSize ?? 0
  }
}
#endif

/// 按当前工程接没接上数据层挑一个实现。
/// app target 已经链上 `KanpanData`（`Kanpan.xcodeproj` 里既在
/// `packageProductDependencies`，也在 `PBXFrameworksBuildPhase` 的
/// 「KanpanData in Frameworks」），所以 `#if canImport(KanpanData)` 成立、
/// 跑的是真的 `DiskMarketCache`——设置页的「清缓存」是能用的。
/// `#else` 那支只留给没链数据层的跑道（见 `Kanpan/Settings/Package.swift`）。
enum MarketCacheFactory {
  static func make() -> any MarketCacheStore {
    #if canImport(KanpanData)
    DiskMarketCache()
    #else
    UnavailableMarketCache()
    #endif
  }
}
