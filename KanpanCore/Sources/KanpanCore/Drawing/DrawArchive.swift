import Foundation

/// 画线的存档模型（A7.7：按品种分桶，每品种上限 50 条）——纯值，不碰磁盘。
///
/// 落盘那一层（`DrawStore`：哪个目录、原子写、备份、比自己新的版本不乱读）在 app 的
/// `Kanpan/Kanpan/Drawing/DrawStore.swift`（审查 24：Core 只放纯模型与算法，文件 IO 出去）。
///
/// 和 K 线不一样：**画线是用户的东西，必须永久留着**，所以那一层走 Application Support
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
  // 「收藏的那几把工具」（`favorites`）2026-10-10 删掉：收藏是 41 把工具时代的解法，工具砍到 12 把
  // （`Drawing.Kind.palette`）之后 2026-09-22 起界面上就没有入口了，只剩兼容。服务端同一天把它挪进
  // `RETIRED_DRAWING_PREFERENCE_FIELDS`：老客户端发上来丢掉、云端老 body 合并时洗掉。老存档里的这个键
  // 解码时忽略（`init(from:)` 只认下面这几项），删除前的代码在 tag `sync-fields-before-retire-2026-10-10`。
  public var magnet = true
  public var continuous = false
  public var styles: [String: DrawingStyle] = [:]
  /// 每一族「换画法」上次选的是哪一种。键是面板上那一格（`trend` / `hline` / `vline`，
  /// 见 `Drawing.Kind.paletteHead`），值是同族里的一种（`extended`、`hray`……）。
  ///
  /// 用户在样式表里把一条趋势线换成「两端延伸」，是他明确说了「我要的趋势线是这样的」；
  /// 从前新线永远按面板那一格的 kind 生成，于是下一条又是线段，他得每画一条换一次。
  /// 现在换一次就记住，之后面板上点「趋势线」落下来的就是两端延伸，直到他再换。
  /// 面板那一格的名字和图标不变——入口还是一个，变的只是它落下来的画法。
  ///
  /// 和 `styles` 一样跟着账号走：拍平成 `variants/<面板那一格>` 一串子键同步。
  public var variants: [String: Drawing.Kind] = [:]
  public init() {}

  /// 面板上点的是 `tool`，这一笔落下来该是哪一种。
  ///
  /// 只认同一族里的记忆：值不在这一族（坏数据、以后改了族的划分）就当没记过，退回 `tool`
  /// 本身——换错了族，点数可能对不上，`Drawing.isValid` 会把整条线丢掉。
  public func kind(for tool: Drawing.Kind) -> Drawing.Kind {
    Self.kind(for: tool, variants: variants)
  }
  public static func kind(for tool: Drawing.Kind, variants: [String: Drawing.Kind]) -> Drawing.Kind {
    guard tool.paletteHead == tool, let chosen = variants[tool.rawValue], chosen.paletteHead == tool else { return tool }
    return chosen
  }

  /// 样式表里把一条线从 `old` 换成了 `new`：同一族就把它记成这一族以后的画法。
  /// 返回有没有真的改动（没变就不必落盘、不必发同步）。
  @discardableResult
  public mutating func rememberSwap(from old: Drawing.Kind, to new: Drawing.Kind) -> Bool {
    guard old != new, let head = new.paletteHead, old.paletteHead == head,
          variants[head.rawValue] != new else { return false }
    variants[head.rawValue] = new
    return true
  }

  /// 面板上的 `tool` 落下一条新线：kind 换成这一族记住的画法，样式铺这类工具记住的默认。
  public func newDrawing(tool: Drawing.Kind, points: [DrawPoint]) -> Drawing {
    Self.newDrawing(tool: tool, points: points, styles: styles, variants: variants)
  }
  /// 图表那一侧只持有 `styles` 与 `variants` 两份值（`ChartView.drawingStyles` / `drawingVariants`），
  /// 落笔和这里走同一份算式，单测盖住的就是图上真的落下来的那条。
  ///
  /// 样式先找换过之后那一种自己的（用户给两端延伸单独调过颜色，就用那一份），
  /// 没有再退到面板那一格的（他给趋势线调过颜色、再换成两端延伸，颜色不该跟着丢）。
  /// 两份各存各的，谁也不覆盖谁——写入的规矩还是 `DrawingController.update` 那一条。
  public static func newDrawing(tool: Drawing.Kind, points: [DrawPoint],
                                styles: [String: DrawingStyle], variants: [String: Drawing.Kind]) -> Drawing {
    let kind = kind(for: tool, variants: variants)
    var item = Drawing(kind: kind, points: points)
    if let style = styles[kind.rawValue] ?? styles[tool.rawValue] {
      // 线型与填充 2026-09-28 起不再给选（收设置项 F）：记住的样式里就算存着虚线 / 不填充
      // （老版本提上来的默认），新线也按默认的实线、填充落——用户已经没有地方把它改回来了。
      item.color = style.color; item.lineWidth = style.lineWidth; item.levels = style.levels
    }
    return item
  }

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
    // 样式同 `variants`：逐条解、解不开的那一条丢掉，别整份抛。整份抛的代价很大——
    // 本机存档里它会连累 `DrawArchive` 整份解不开（所有品种的画线一起没了），云端那份
    // 则在 `SyncOverlay` 里被整份跳过，磁吸、画法记忆、别的工具样式从此一个都同步不过来。
    // 以后的版本多一种线型、多一把工具，老版本读到的就是这种「只有一条认不出」的数据。
    magnet = try c.decodeIfPresent(Bool.self, forKey: .magnet) ?? fallback.magnet
    continuous = try c.decodeIfPresent(Bool.self, forKey: .continuous) ?? fallback.continuous
    let rawStyles = (try? c.decodeIfPresent([String: TolerantStyle].self, forKey: .styles)) ?? nil
    styles = rawStyles.map { $0.compactMapValues(\.style) } ?? fallback.styles
    // 按字符串解、认不出的丢掉，别整份抛：以后的版本多了一种画法，老版本读到它
    // 不该连自选、设置一起落不了地（理由同上面那段）。
    let raw = (try? c.decodeIfPresent([String: String].self, forKey: .variants)) ?? nil
    variants = (raw ?? [:]).compactMapValues(Drawing.Kind.init(rawValue:))
  }
}

public struct DrawArchive: Sendable, Equatable, Codable {
  /// 存档版本。字段有增删时 +1，老档按「缺的取默认」合并，不整体丢弃（A6.13 的规矩）。
  public static let currentVersion = 3
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
  /// 每条线是在哪个周期上画的：线 id → `Interval.rawValue`（画线列表里那一行的「15分」）。
  ///
  /// **只在本机，不进同步、也不是 `Drawing` 的字段。** 线的同步是逐条、逐字段走的
  /// （`PersonalSyncCodec`），服务端对画线对象的字段是白名单（`sync_validation.rs`），
  /// 多一个它不认识的键整条操作就被拒、整批卡住；这一项又只是给人看的一行小字，
  /// 不值得为它改协议。别的设备同步来的线这儿没有记录，列表上就不写周期。
  /// 云端那批装进来是叠在本机这份存档上改的（`SyncOverlay.drawings(_:onto:)`），这张表跟着留下。
  public var intervals: [String: String] = [:]

  public init(version: Int = DrawArchive.currentVersion, bySymbol: [String: [Drawing]] = [:]) {
    self.version = version
    self.bySymbol = Self.migrate(bySymbol)
  }

  /// 这条线是在哪个周期上画的；没记过（老线、别的设备画的）是 `nil`。
  public func interval(of id: String) -> Interval? { intervals[id].flatMap(Interval.init(rawValue:)) }

  /// 给 `symbol` 那一桶里还没记过周期的线记上 `interval`（刚画下的那几条），
  /// 顺手把已经不在任何一桶里的记录清掉。真改了返回 `true`。
  @discardableResult
  public mutating func noteIntervals(_ interval: Interval, for symbol: String) -> Bool {
    var next = intervals
    for d in self[symbol] where next[d.id] == nil { next[d.id] = interval.rawValue }
    if next.count > intervals.count {
      let alive = Set(bySymbol.values.joined().map(\.id))
      next = next.filter { alive.contains($0.key) }
    }
    guard next != intervals else { return false }
    intervals = next
    return true
  }

  private static func migrate(_ values: [String: [Drawing]]) -> [String: [Drawing]] {
    var output: [String: [Drawing]] = [:]
    for key in values.keys.sorted() {
      let canonical = InstrumentID.canonical(key)
      for drawing in values[key] ?? [] {
        if let i = output[canonical, default: []].firstIndex(where: { $0.id == drawing.id }) {
          if key == canonical { output[canonical]?[i] = drawing }
        } else { output[canonical, default: []].append(drawing) }
      }
    }
    return output
  }

  /// 下标本身不裁：交互上「满了就不让画」由 `hasRoom(for:)` 管，外面进来的由 `capToLimit()` 在
  /// 进门那一刻管（见下）。
  public subscript(symbol: String) -> [Drawing] {
    get { bySymbol[InstrumentID.canonical(symbol)] ?? [] }
    set {
      if newValue.isEmpty {
        bySymbol.removeValue(forKey: InstrumentID.canonical(symbol))   // 空的不占位，省得存档里一堆空数组
      } else {
        bySymbol[InstrumentID.canonical(symbol)] = newValue
      }
    }
  }

  /// 眼下这个品种的那一桶，跟另一份存档比有没有变。
  ///
  /// 存档是**整份**在同步的：别人在另一台设备上给 ETH 加了一条线，推回来的是一份新的
  /// `DrawArchive`，整份不相等。可 BTC 那一桶一个字都没动，图上那条线也就没有任何
  /// 理由被「整批外部替换」一次——而整批替换要清空撤销栈和选中态（见
  /// `ChartView.setDrawings`）。于是「别人改了别的品种」会把我这边画到一半的撤销栈
  /// 抹掉，这是 A-07 报的那件事。发布同步结果之前先拿这个问一句。
  func bucketChanged(from old: DrawArchive, symbol: String) -> Bool {
    self[symbol] != old[symbol]
  }

  /// 还能不能再画一条。满了由调用方提示，而不是默默把最早那条挤掉——
  /// 用户画满 50 条时挤掉第一条他多半根本没看见。
  public func hasRoom(for symbol: String) -> Bool {
    self[symbol].count < Self.perSymbolLimit
  }

  /// 一条线「多老」：它在同步里第一次被写下的那一刻（服务端每个字段都记着写入时的
  /// 客户端时间戳与逻辑钟，取最早那个字段的就是这条线诞生的那一笔）。大的新。
  public struct Age: Sendable, Comparable, Hashable {
    public var timestamp: Int64
    public var logical: UInt64
    public init(timestamp: Int64, logical: UInt64) { self.timestamp = timestamp; self.logical = logical }
    public static func < (a: Age, b: Age) -> Bool { (a.timestamp, a.logical) < (b.timestamp, b.logical) }
  }

  /// 进门的上限：同步拉下来的、访客档案并进来的、启动前向对账补回来的，每一桶最多
  /// `perSymbolLimit` 条，多出来的**从最老的丢起**。留下的那几条保持原来在桶里的先后。
  /// 返回每个品种丢了几条（没丢的不列），调用方拿去记日志。
  ///
  /// 为什么在进门时裁，而不是在渲染里特判（压测收尾 2026-09-26 第 10 项）：交互上一只品种画满
  /// 50 条就不让再画，可同步合并和访客合并从来不看这个数——别的设备、老版本带来的几百条原样
  /// 落进存档，图上每一帧都要把它们全部过一遍（300 条约 20 ms 一帧）。渲染里特判等于在最热的
  /// 那条路上每帧多做一次裁剪，还会出现「存档里有、图上没有」的两套口径；进门裁一次，
  /// 存档、同步、图上看到的就是同一份。
  ///
  /// ## 「最老」怎么排
  ///
  /// - 有 `age` 的（云端见过的）按 `Age` 排，同龄按 id——**每台设备、每一次应用排出来都一样**。
  ///   不能按数组位置：同步那一路每次应用时，上次留下的 50 条在桶头、没留下的又被追加到桶尾，
  ///   按位置「留尾巴」就会每应用一次换一批，图上的线来回跳。
  /// - 没有 `age` 的（本机新画、云端还没确认；访客档案带来的）算最新，彼此之间按桶里的先后。
  ///   不给 `age` 时整桶就是按桶里的先后（本机落笔顺序，头上最老）。
  @discardableResult
  public mutating func capToLimit(age: (Drawing) -> Age? = { _ in nil }) -> [String: Int] {
    var dropped: [String: Int] = [:]
    for (key, bucket) in bySymbol where bucket.count > Self.perSymbolLimit {
      let ages = bucket.map(age)
      let ranked = bucket.indices.sorted { i, j in
        switch (ages[i], ages[j]) {
        case let (x?, y?): x == y ? bucket[i].id < bucket[j].id : x < y
        case (nil, nil): i < j
        case (nil, _?): false
        case (_?, nil): true
        }
      }
      let keep = Set(ranked.suffix(Self.perSymbolLimit))
      dropped[key] = bucket.count - Self.perSymbolLimit
      bySymbol[key] = bucket.indices.filter(keep.contains).map { bucket[$0] }
    }
    return dropped
  }

  /// 一串画线里最新的 `perSymbolLimit` 条（数组尾上的那几条）。收件箱里一封信带的线走这一条：
  /// 信里的顺序就是发信人桶里的先后。
  public static func newest(_ drawings: [Drawing]) -> [Drawing] {
    drawings.count > perSymbolLimit ? Array(drawings.suffix(perSymbolLimit)) : drawings
  }

  // 键名短是故意的：这份文件会跟着 app 一起备份，没必要为可读性多占字节。
  private enum CodingKeys: String, CodingKey {
    case version = "v"
    case bySymbol = "d"
    case preferences
    case intervals = "iv"
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(version, forKey: .version)
    try c.encode(bySymbol, forKey: .bySymbol)
    try c.encode(preferences, forKey: .preferences)
    // 空的不写：老存档、没画过线的存档逐字不变。
    if !intervals.isEmpty { try c.encode(intervals, forKey: .intervals) }
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    // 工具偏好坏了只丢偏好，不能连累下面的画线一起解不开。
    preferences = ((try? c.decodeIfPresent(DrawingPreferences.self, forKey: .preferences)) ?? nil)
      ?? DrawingPreferences()
    // 逐条解，不是整桶解（2026-09-20）。
    //
    // 新版本每加一把工具，`Drawing.Kind` 就多一个 rawValue；老版本的 app 认不得它，
    // `Drawing.init(from:)` 直接抛。整桶解的时候这一抛就是整份存档解不开——`read()` 抛出去，
    // `load()` 退回一份空档，用户看到的是**这台手机上所有品种的画线全没了**，
    // 而实际上只是云端同步下来一条它不认识的新工具。丢掉那一条，剩下的照常读。
    let raw = try c.decodeIfPresent([String: [TolerantDrawing]].self, forKey: .bySymbol) ?? [:]
    bySymbol = Self.migrate(raw.compactMapValues { bucket in
      let kept = bucket.compactMap(\.drawing)
      return kept.isEmpty ? nil : kept
    })
    // 周期记录坏了只丢记录，线照常读。
    intervals = ((try? c.decodeIfPresent([String: String].self, forKey: .intervals)) ?? nil) ?? [:]
  }
}

/// 一把工具的样式：解得开就留下，解不开（比如以后多出来的线型）就当没记过。
private struct TolerantStyle: Decodable {
  let style: DrawingStyle?
  init(from decoder: Decoder) throws { style = try? DrawingStyle(from: decoder) }
}

/// 解得开就留下，解不开就当没有这一条。
private struct TolerantDrawing: Decodable {
  let drawing: Drawing?
  init(from decoder: Decoder) throws { drawing = try? Drawing(from: decoder) }
}
