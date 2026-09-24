import Foundation

/// 行情缓存的真家伙（A6.11）：`Library/Caches/kanpan` 下能清的那几样，位置全部问 `Paths` 要，
/// 这里不自己拼目录。
///
/// 放在数据层（审查 24）：它认的是 `Paths` 那棵树，是数据层的事。app 的设置模型只认一份
/// 「量出来多少、清一下」的协议（`Kanpan/Kanpan/Settings/Model/MarketCache.swift`），
/// 两者在 app 的装配处（`Settings/MarketCacheWiring.swift`）接上——模型层不再 `import KanpanData`。
public struct DiskMarketCache: Sendable {
  public var paths: Paths

  public init(paths: Paths = .caches()) { self.paths = paths }

  /// 分开量的四笔，口径见 app 里的 `MarketCacheUsage`。
  public struct Footprint: Sendable, Equatable {
    /// `series/` 下按 (品种, 周期) 存的启动快照，加上旧版单份快照。
    public var snapshotBytes: Int
    /// 品种表，加上换过行情源的人那棵 `sources/<行情源>/`。
    public var catalogBytes: Int
    /// `oi/` 下按天存的归档切片。
    public var oiBytes: Int
    /// `profiles/<档案>/` 下的报价与当日开盘价，加上板块历史与板块行情。
    public var derivedBytes: Int
  }

  public func footprint() async -> Footprint {
    let p = paths
    return await Task.detached(priority: .utility) {
      Footprint(
        snapshotBytes: DiskMarketCache.size(of: p.series) + DiskMarketCache.size(of: p.snapshot),
        catalogBytes: DiskMarketCache.size(of: p.exchangeInfo) + DiskMarketCache.size(of: p.sources),
        oiBytes: DiskMarketCache.size(of: p.oi),
        derivedBytes: DiskMarketCache.size(of: p.profiles) + DiskMarketCache.size(of: p.sectorHistory)
          + DiskMarketCache.size(of: p.sectorQuotes))
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
  public func clear() async {
    let p = paths
    await Task.detached(priority: .utility) {
      let fm = FileManager.default
      for url in [p.series, p.snapshot, p.exchangeInfo, p.sources, p.oi, p.profiles, p.sectorHistory, p.sectorQuotes] {
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
