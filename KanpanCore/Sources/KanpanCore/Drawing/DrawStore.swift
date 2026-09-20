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
/// Tool defaults contain style only, never deleted objects' anchor coordinates.
public struct DrawingStyle: Sendable, Equatable, Codable {
  public var color: Hex?
  public var lineWidth: Double
  public var dash: Drawing.Dash
  public var filled: Bool
  public var levels: [Double]
  public init(_ drawing: Drawing) {
    color = drawing.color; lineWidth = drawing.lineWidth; dash = drawing.dash
    filled = drawing.filled; levels = drawing.levels
  }
}

public struct DrawingPreferences: Sendable, Equatable, Codable {
  public var favorites: [Drawing.Kind] = [.trend, .hline, .rectangle, .fibonacci, .measure]
  public var magnet = true
  public var continuous = false
  public var styles: [String: DrawingStyle] = [:]
  public init() {}

  /// 缺的键取默认，别整份抛掉——和 `DrawArchive` 是同一条规矩（A6.13）。
  ///
  /// 这儿不是为老存档留的活口，是云端那份**一定**缺键：往上推的时候
  /// `PersonalSyncCodec.flatten` 把 `styles` 拍成 `styles/<工具>` 一串子键，
  /// 用户没改过任何一把工具的样式时 `styles` 是空的，一个子键都拍不出来，
  /// 于是线上那份 `drawingPreferences:tools` 里**根本没有 `styles` 这个键**。
  /// 合成的 `init(from:)` 认死每个键都得在，拉回来就抛「数据缺失」——而它是在
  /// `AppAccountBridge.applyPending()` 的开头抛的，后面的自选、分类、设置一份都落不了地。
  /// 用户看到的是：换台设备登同一个账号，自选页空空如也，偏好也一个都没跟过来。
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let fallback = DrawingPreferences()
    favorites = try c.decodeIfPresent([Drawing.Kind].self, forKey: .favorites) ?? fallback.favorites
    magnet = try c.decodeIfPresent(Bool.self, forKey: .magnet) ?? fallback.magnet
    continuous = try c.decodeIfPresent(Bool.self, forKey: .continuous) ?? fallback.continuous
    styles = try c.decodeIfPresent([String: DrawingStyle].self, forKey: .styles) ?? fallback.styles
  }
}

public struct DrawArchive: Sendable, Equatable, Codable {
  /// 存档版本。字段有增删时 +1，老档按「缺的取默认」合并，不整体丢弃（A6.13 的规矩）。
  public static let currentVersion = 2
  /// 每个品种的条数上限（A7.7）。
  public static let perSymbolLimit = 50

  public var preferences = DrawingPreferences()
  public var version: Int
  /// 画线**只按品种分桶，不按周期分**（第五轮审查 A.4 的裁决，保持不变）。
  ///
  /// 端点存的是「时间 + 价格」（见 `DrawPoint`），不是「第几根」——同一条趋势线在
  /// 1 分钟和日线上落在同一个时刻、同一个价位，本来就该是同一条。真按周期再分一层桶，
  /// 用户在 15 分钟上画的那条线切到 1 小时就消失，得在每个周期上重画一遍；
  /// 撤销栈也跟着按周期碎成好几份，「撤销」撤掉的是哪一条要先想想现在是什么周期。
  /// 这两样都和产品基线相反。周期只改看见多长的时间，不改这张图上画了什么。
  public var bySymbol: [String: [Drawing]]

  public init(version: Int = DrawArchive.currentVersion, bySymbol: [String: [Drawing]] = [:]) {
    self.version = version
    self.bySymbol = bySymbol
  }

  /// 存档保留全部对象；交互创建限制不能裁掉同步合并的数据。
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

  /// 保留顺序和所有对象；旧调用点仍可使用此兼容方法。
  public static func capped(_ ds: [Drawing]) -> [Drawing] {
    ds
  }

  /// 眼下这个品种的那一桶，跟另一份存档比有没有变。
  ///
  /// 存档是**整份**在同步的：别人在另一台设备上给 ETH 加了一条线，推回来的是一份新的
  /// `DrawArchive`，整份不相等。可 BTC 那一桶一个字都没动，图上那条线也就没有任何
  /// 理由被「整批外部替换」一次——而整批替换要清空撤销栈和选中态（见
  /// `ChartView.setDrawings`）。于是「别人改了别的品种」会把我这边画到一半的撤销栈
  /// 抹掉，这是 A-07 报的那件事。发布同步结果之前先拿这个问一句。
  public func bucketChanged(from old: DrawArchive, symbol: String) -> Bool {
    self[symbol] != old[symbol]
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
    case preferences
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    preferences = try c.decodeIfPresent(DrawingPreferences.self, forKey: .preferences) ?? DrawingPreferences()
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
  ///
  /// UI 用例要的是「这一轮跑的画线别落到用户自己那份档案里」，于是有一道
  /// `KANPAN_TEST_PROFILE=1` + `KANPAN_PERSISTENCE_PROFILE=<UUID>` 的岔路。
  /// 那道岔路**只在 DEBUG 构建里存在**（审查 C-02）：UI 测试跑的就是 Debug 包，
  /// 行为一点没变；而 Release 包里连那个分支都编不出来，不存在「设对了环境变量
  /// 就能把正式档案挪走」这回事。
  public static func applicationSupport() -> DrawStore {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    return DrawStore(url: folder(under: base).appendingPathComponent("draws.json"))
  }

  /// 画线档案所在的目录。Release 下只有 `kanpan/` 这一个答案，没有第二条岔路。
  private static func folder(under base: URL) -> URL {
    let normal = base.appendingPathComponent("kanpan", isDirectory: true)
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_TEST_PROFILE"] == "1" else { return normal }
    let profile = ProcessInfo.processInfo.environment["KANPAN_PERSISTENCE_PROFILE"].flatMap { UUID(uuidString: $0)?.uuidString } ?? "default"
    return base.appendingPathComponent("kanpan-drawing-tests", isDirectory: true)
      .appendingPathComponent(profile, isDirectory: true)
    #else
    return normal
    #endif
  }

  /// 读。读不出来一律当空档，**不抛**：画线丢了是可惜，因为它开不了图是不可接受的。
  public enum StoreError: Error { case newerVersion, invalidArchive }
  public func read() throws -> DrawArchive {
    guard FileManager.default.fileExists(atPath: url.path) else { return DrawArchive() }
    let data = try Data(contentsOf: url)
    // Read the envelope before decoding tools unknown to this version.
    if let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       let version = raw["v"] as? Int, version > DrawArchive.currentVersion { throw StoreError.newerVersion }
    var archive = try JSONDecoder().decode(DrawArchive.self, from: data)
    archive.version = DrawArchive.currentVersion
    return archive
  }
  public func load() -> DrawArchive { (try? read()) ?? DrawArchive() }

  /// 写。先写临时文件再原子替换，中途被杀不会留下半份坏 JSON。
  public func save(_ archive: DrawArchive) throws {
    // Never replace an unreadable/newer file with an empty in-memory fallback.
    if FileManager.default.fileExists(atPath: url.path) { _ = try read() }
    guard archive.bySymbol.values.allSatisfy({ $0.allSatisfy(\.isValid) }) else { throw StoreError.invalidArchive }
    if FileManager.default.fileExists(atPath: url.path) {
      let backup = url.appendingPathExtension("backup")
      if !FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.copyItem(at: url, to: backup) }
    }
    var a = archive
    a.version = DrawArchive.currentVersion
    let data = try JSONEncoder().encode(a)
    let dir = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
  }
}
