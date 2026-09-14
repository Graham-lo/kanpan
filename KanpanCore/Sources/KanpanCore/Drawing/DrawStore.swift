import Foundation

/// 画线的落盘（A7.7：按品种持久化，杀 app 重开仍在，每品种上限 50 条）。
///
/// 放在 KanpanCore 而不是任务书 §4.2 写的 `KanpanData/Store`：这一轮 `KanpanData/`
/// 有别人在改，不能碰。画线存的是纯值（时间 + 价格），不依赖网络层的任何东西，
/// 放 Core 反而能被 `make core-test` 直接盖住磁盘往返——见 `docs/acceptance/M7.md`。
///
/// 和 K 线不一样：**画线是用户的东西，必须永久留着**，所以走 Application Support
/// （会进 iCloud 备份、系统不会自己清），不是放 K 线快照那个 `Caches/`（§4.2 的
/// 表里「设置 / 自选 / 画线 / 常用周期：JSON + Codable 放 Application Support」）。

// MARK: - 归档

/// 全部品种的画线。键是品种代码（`BTCUSDT`）。
public struct DrawArchive: Sendable, Equatable, Codable {
  /// 存档版本。字段有增删时 +1，老档按「缺的取默认」合并，不整体丢弃（A6.13 的规矩）。
  public static let currentVersion = 1
  /// 每个品种的条数上限（A7.7）。
  public static let perSymbolLimit = 50

  public var version: Int
  public var bySymbol: [String: [Drawing]]

  public init(version: Int = DrawArchive.currentVersion, bySymbol: [String: [Drawing]] = [:]) {
    self.version = version
    self.bySymbol = bySymbol
  }

  /// 取 / 存某个品种的线。存进去时超出上限的部分从**最早**的一头砍掉。
  public subscript(symbol: String) -> [Drawing] {
    get { bySymbol[symbol] ?? [] }
    set {
      if newValue.isEmpty {
        bySymbol.removeValue(forKey: symbol)   // 空的不占位，省得存档里一堆空数组
      } else {
        bySymbol[symbol] = Self.capped(newValue)
      }
    }
  }

  /// 只留最后 50 条。顺序就是画的顺序，也是叠放顺序（后画的在上面）。
  public static func capped(_ ds: [Drawing]) -> [Drawing] {
    ds.count <= perSymbolLimit ? ds : Array(ds.suffix(perSymbolLimit))
  }

  /// 还能不能再画一条。满了由调用方提示，而不是默默把最早那条挤掉——
  /// 用户画满 50 条时挤掉第一条他多半根本没看见。
  public func hasRoom(for symbol: String) -> Bool {
    self[symbol].count < Self.perSymbolLimit
  }

  // 键名短是故意的：这份文件会跟着 app 一起备份，没必要为可读性多占字节。
  private enum CodingKeys: String, CodingKey {
    case version = "v"
    case bySymbol = "d"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    let raw = try c.decodeIfPresent([String: [Drawing]].self, forKey: .bySymbol) ?? [:]
    bySymbol = raw.compactMapValues { $0.isEmpty ? nil : Self.capped($0) }
  }
}

// MARK: - 磁盘

/// 一份 JSON 文件，整存整取。
///
/// 不做增量：画线全部加起来也就几 KB，一次写完最省事，也不会写到一半断电留下半份。
public struct DrawStore: Sendable {
  public var url: URL

  public init(url: URL) { self.url = url }

  /// 默认位置：`Application Support/kanpan/draws.json`。
  public static func applicationSupport() -> DrawStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return DrawStore(
      url: base.appendingPathComponent("kanpan", isDirectory: true)
        .appendingPathComponent("draws.json"))
  }

  /// 读。读不出来一律当空档，**不抛**：画线丢了是可惜，因为它开不了图是不可接受的。
  public func load() -> DrawArchive {
    guard let data = try? Data(contentsOf: url) else { return DrawArchive() }
    guard var a = try? JSONDecoder().decode(DrawArchive.self, from: data) else {
      return DrawArchive()
    }
    // 比自己新的存档看不懂（降级安装、从别人机器拷过来）：当空的，但不动磁盘上那份，
    // 用户升回去还在。
    guard a.version <= DrawArchive.currentVersion else { return DrawArchive() }
    a.version = DrawArchive.currentVersion
    return a
  }

  /// 写。先写临时文件再原子替换，中途被杀不会留下半份坏 JSON。
  public func save(_ archive: DrawArchive) throws {
    var a = archive
    a.version = DrawArchive.currentVersion
    let data = try JSONEncoder().encode(a)
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
