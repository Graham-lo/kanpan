import Foundation

/// 颜色。Core 不碰 UIKit，所以用 8 位十六进制字符串存，取用时再转 RGBA。
public struct Hex: Sendable, Equatable, Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
  /// 原样的 `#RRGGBB` 或 `#RRGGBBAA`，和原型字符串逐字相同。
  public let value: String

  public init(_ value: String) { self.value = value }
  public init(stringLiteral value: String) { self.init(value) }
  public var description: String { value }

  /// 归一化后的 RGBA，0…1。解析不了就是透明黑。
  /// 0–255 的四个通道。混色、解析都走这里，免得在浮点上来回换。
  public var bytes: (r: Int, g: Int, b: Int, a: Int) {
    var hex = Substring(value)
    if hex.hasPrefix("#") { hex = hex.dropFirst() }
    let d = hex.compactMap { $0.hexDigitValue }
    guard d.count >= 6 else { return (0, 0, 0, 255) }
    let a = d.count >= 8 ? d[6] * 16 + d[7] : 255
    return (d[0] * 16 + d[1], d[2] * 16 + d[3], d[4] * 16 + d[5], a)
  }

  public var rgba: (r: Double, g: Double, b: Double, a: Double) {
    var s = Substring(value)
    if s.hasPrefix("#") { s = s.dropFirst() }
    guard s.count == 6 || s.count == 8, let n = UInt32(s, radix: 16) else { return (0, 0, 0, 0) }
    if s.count == 6 {
      return (Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255, 1)
    }
    return (Double((n >> 24) & 0xFF) / 255, Double((n >> 16) & 0xFF) / 255,
            Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
  }

  /// 叠一层 alpha（两位十六进制，和原型 `a(hex, aa)` 一样是字符串拼接）。
  public func alpha(_ aa: String) -> Hex { Hex(value + aa) }
}

/// 一套配色的原始令牌。
///
/// `amber` 是**画在图上**的那支暖色（BOLL 中轴、画线手柄）；`accent` 是**界面**的强调色
/// （选中的周期、底栏当前项、面板里的动作字）。两者分开是因为这一版的两套配色里，
/// 界面强调色是配色自己的主色（青苔的墨绿、陶土的赤陶），而图上那支暖色仍要和
/// K 线、均线区分得开——合成一支的话，要么图上多一支绿线和涨色撞，要么界面变土黄。
public struct PaletteSeed: Sendable, Equatable {
  public var dark: Bool
  public var ground, app, chart, raised, raised2: Hex
  public var line, grid, hair: Hex
  public var ink, ink2, ink3: Hex
  public var up, down, amber: Hex
  /// 界面强调色。
  public var accent: Hex
  public var palette: [Hex]

  public init(dark: Bool, ground: Hex, app: Hex, chart: Hex, raised: Hex, raised2: Hex,
              line: Hex, grid: Hex, hair: Hex, ink: Hex, ink2: Hex, ink3: Hex,
              up: Hex, down: Hex, amber: Hex, accent: Hex? = nil, palette: [Hex]) {
    self.dark = dark
    self.ground = ground; self.app = app; self.chart = chart
    self.raised = raised; self.raised2 = raised2
    self.line = line; self.grid = grid; self.hair = hair
    self.ink = ink; self.ink2 = ink2; self.ink3 = ink3
    self.up = up; self.down = down; self.amber = amber
    self.accent = accent ?? amber
    self.palette = palette
  }
}

/// 图表用色（原型 `expand(t).chart` 加上几个常用的派生令牌）。
public struct ChartColors: Sendable, Equatable {
  public var bg, grid, axis, text, dim, ink, amber, cross: Hex
  public var band, oi, oiFill: Hex
  public var chip, panel: Hex
  public var crossBg, crossInk: Hex
  /// 比网格还淡一层的发丝线。
  public var hair: Hex
  public var amberSoft, amberLine: Hex
  /// 涨 / 跌。注意这两个会被「红涨绿跌」开关对调。
  public var up, down: Hex
  /// 指标线依次取色。
  public var palette: [Hex]
}

/// 两套配色：青苔（冷，出厂）与陶土（暖），各有浅深两版。
///
/// K 线与指标的**画法**一个像素都不改——这里换的只有颜色。蜡烛的宽度、间距、
/// 副图的分区、读数那一行的排布全在 `KanpanChart` 里，和这份表没有关系。
///
/// **画布不跟皮肤走。** K 线绘图区（主图 + 副图 + 坐标轴）一律用 AICoin 那套固定配色，
/// 皮肤只染图区以外的一切（顶栏、周期条、底栏、面板、自选页）。染过一版画布：整屏是
/// 连成一块了，但蜡烛和均线全压在一层带色的底上，看久了分不清价格结构——这正是 AICoin
/// 十年如一日用白底的原因。接缝交给 `ground` / `raised` 去收，那本来就是它们的活。
///
/// 跟着皮肤走的只剩涨跌色、`amber` 和 MA 那组 `palette`：这几样在头部胶囊、自选列表里
/// 也出现，图里图外必须是同一个红、同一个绿。
/// 种子里的 `chart` 字段因此只用于图表以外的容器，不再是画布底色。
public enum Palette: Sendable {
  // ---------------------------------------------------------------- 青苔（冷）

  /// 青苔 · 浅。全新安装就是这一套。
  public static let sageSeed = PaletteSeed(
    dark: false,
    ground: "#C3D6CA", app: "#F3F7F4", chart: "#F3F7F4", raised: "#FFFFFF", raised2: "#E7EFE9",
    line: "#D6E3DA", grid: "#E2EBE5", hair: "#14211B0F",
    ink: "#14211B", ink2: "#4E6158", ink3: "#606F67",
    up: "#2E7D6B", down: "#C34642", amber: "#B57C28", accent: "#2E7D6B",
    palette: ["#BD8229", "#5A79C4", "#2E7D6B", "#B4617F", "#7A6BC0", "#3E86A8"])

  /// 青苔 · 深。
  public static let sageNightSeed = PaletteSeed(
    dark: true,
    ground: "#060A08", app: "#0B120F", chart: "#0B120F", raised: "#131C18", raised2: "#1A241F",
    line: "#25332C", grid: "#1A241F", hair: "#FFFFFF0A",
    ink: "#E9F2EC", ink2: "#A5B8AE", ink3: "#7B8D85",
    up: "#4FB69C", down: "#E36159", amber: "#E0A544", accent: "#4FB69C",
    palette: ["#E0A544", "#7D9AE8", "#4FB69C", "#E894B4", "#BDAEDC", "#7FD0FF"])

  // ---------------------------------------------------------------- 陶土（暖）

  /// 陶土 · 浅。
  public static let terraSeed = PaletteSeed(
    dark: false,
    ground: "#D9C7B4", app: "#FBF6F0", chart: "#FBF6F0", raised: "#FFFFFF", raised2: "#F2E8DE",
    line: "#E7DACB", grid: "#F0E6DA", hair: "#241A130F",
    ink: "#241A13", ink2: "#6E5C4D", ink3: "#756659",
    up: "#2F7D62", down: "#C4483C", amber: "#B37B25", accent: "#B25735",
    palette: ["#C18030", "#5566C4", "#2F7D62", "#B85A82", "#8A6FC0", "#3E7FA8"])

  /// 陶土 · 深。
  public static let terraNightSeed = PaletteSeed(
    dark: true,
    ground: "#0C0805", app: "#16100C", chart: "#16100C", raised: "#211812", raised2: "#2A1F17",
    line: "#37281D", grid: "#2A1F17", hair: "#FFFFFF0A",
    ink: "#F7EFE6", ink2: "#C2AC98", ink3: "#958576",
    up: "#3FA783", down: "#E0584A", amber: "#E0A544", accent: "#E2874F",
    palette: ["#E0A544", "#9B8AE0", "#3FA783", "#E894B4", "#C0AEE0", "#85B8D6"])

  /// 「浅 / 深」这两个词在代码里到处都是，指的就是出厂那一套的两版。
  public static let lightSeed = sageSeed
  public static let darkSeed = sageNightSeed

  /// 暖色那一套（陶土）。渐变、徽章那几处要按冷暖分别让一让。
  public static func isWarm(_ t: PaletteSeed) -> Bool {
    t.ground == terraSeed.ground || t.ground == terraNightSeed.ground
  }

  /// 小字用的第三级墨色。四套种子都是手配的，直接用。
  public static func secondaryInk(_ t: PaletteSeed) -> Hex { t.ink3 }

  public static func contrast(_ foreground: Hex, _ background: Hex) -> Double {
    func luminance(_ c: Hex) -> Double {
      let v = c.rgba
      func linear(_ n: Double) -> Double { n <= 0.04045 ? n / 12.92 : pow((n + 0.055) / 1.055, 2.4) }
      return 0.2126 * linear(v.r) + 0.7152 * linear(v.g) + 0.0722 * linear(v.b)
    }
    let a = luminance(foreground), b = luminance(background)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  public static func mix(_ a: Hex, _ b: Hex, amount: Double) -> Hex {
    let x = a.bytes, y = b.bytes, f = min(1, max(0, amount))
    func channel(_ a: Int, _ b: Int) -> Int { Int((Double(a) * f + Double(b) * (1 - f)).rounded()) }
    return Hex(String(format: "#%02X%02X%02X", channel(x.r,y.r), channel(x.g,y.g), channel(x.b,y.b)))
  }

  public static func readable(_ text: Hex, on surfaces: [Hex], toward ink: Hex) -> Hex {
    for step in 0...100 {
      let candidate = mix(text, ink, amount: 1 - Double(step) / 100)
      if surfaces.allSatisfy({ contrast(candidate, $0) >= 4.5 }) { return candidate }
    }
    return ink
  }

  /// 由原始令牌推出图表用色，逐行对应原型 `expand()`。
  ///
  /// `ChartState.colors` 是个计算属性，画一帧要读几十次；每读一次 `expanded` 就重拼
  /// 一遍 `.alpha()` 的十六进制串、重建一次调色板数组。可全仓一共就四套种子，
  /// 结果永远是同样几份。这里挂一张小表：种子数量有限，线性比 `==` 就够，
  /// 不用给 `PaletteSeed` 加 `Hashable`（那是公开 API，能不动就不动）。
  private nonisolated(unsafe) static var chartCache: [(seed: PaletteSeed, redUp: Bool, value: ChartColors)] = []
  private static let chartCacheLock = NSLock()

  public static func chart(_ t: PaletteSeed, redUp: Bool = false) -> ChartColors {
    chartCacheLock.lock()
    if let hit = chartCache.first(where: { $0.redUp == redUp && $0.seed == t }) {
      chartCacheLock.unlock()
      return hit.value
    }
    chartCacheLock.unlock()
    var result = expanded(t)
    if redUp { swap(&result.up, &result.down) }
    chartCacheLock.lock()
    // 皮肤是用户挑的，种类有限；真要被自定义种子撑大了就整只倒掉重来。
    if chartCache.count >= 32 { chartCache.removeAll(keepingCapacity: true) }
    chartCache.append((t, redUp, result))
    chartCacheLock.unlock()
    return result
  }

  /// 画布那几样固定色。日 / 夜各一套，和皮肤无关。
  ///
  /// 取自 `docs/AICoin-安卓包-UI规格提取.md`（页面底、分割线、三 / 四级文字、`line_grid`）
  /// 与 `docs/acceptance/M8/aicoin-对比.md` §4 的实测值。
  public struct ChartCanvas: Sendable, Equatable {
    public var bg, grid, axis, text, dim, ink, cross: Hex
  }

  /// 白天的画布。
  ///
  /// `cross` 是唯一没照抄的一项：AICoin 那份表里日间十字线写的是 `#EEEEEE`，那是画在
  /// 深底上的值，落到 `#FFFFFF` 的画布上等于看不见。取和轴文字同一档的灰蓝，
  /// 权重跟换肤前的 `ink3` 一致。
  public static let dayCanvas = ChartCanvas(
    bg: "#FFFFFF", grid: "#C5C5C5", axis: "#DEE1E5",
    text: "#7A8899", dim: "#B7BFC8", ink: "#292D33", cross: "#7A8899")

  /// 夜里的画布。轴文字仍用 `#7A8899`——在 `#0D111C` 上对比度约 5:1，过得去；
  /// 夜间那组更暗的 `#515A66` 留给 `dim` 这类次要读数。
  public static let nightCanvas = ChartCanvas(
    bg: "#0D111C", grid: "#1C2236", axis: "#25282E",
    text: "#7A8899", dim: "#515A66", ink: "#E6EAF2", cross: "#FFFFFF")

  private static func expanded(_ t: PaletteSeed) -> ChartColors {
    let d = t.dark
    let c = d ? nightCanvas : dayCanvas
    return ChartColors(
      bg: c.bg, grid: c.grid, axis: c.axis, text: c.text, dim: c.dim,
      ink: c.ink, amber: t.amber, cross: c.cross,
      band: t.palette[4], oi: t.palette[5], oiFill: t.palette[5].alpha(d ? "33" : "2E"),
      chip: d ? t.ground : t.app, panel: t.app,
      crossBg: d ? t.line : t.ink, crossInk: d ? t.ink : t.app,
      hair: t.hair,
      amberSoft: t.amber.alpha(d ? "1A" : "16"), amberLine: t.amber.alpha("55"),
      up: t.up, down: t.down,
      palette: t.palette)
  }

  public static func chart(dark: Bool, redUp: Bool = false) -> ChartColors {
    chart(dark ? darkSeed : lightSeed, redUp: redUp)
  }

  /// 遮罩与薄纱，弹层用。
  public static func veil(_ t: PaletteSeed) -> Hex { t.app.alpha(t.dark ? "EE" : "F0") }
  public static func scrim(_ t: PaletteSeed) -> Hex { t.dark ? t.ground.alpha("D9") : t.ink.alpha("4D") }
}
