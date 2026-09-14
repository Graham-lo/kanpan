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

/// 一套配色的原始令牌（原型 `INDIGO.light` / `INDIGO.dark`）。
public struct PaletteSeed: Sendable, Equatable {
  public var dark: Bool
  public var ground, app, chart, raised, raised2: Hex
  public var line, grid: Hex
  public var ink, ink2, ink3: Hex
  public var up, down, amber: Hex
  public var palette: [Hex]
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

/// 靛——从头到尾只有这一套，浅深各一版（§6）。
public enum Palette: Sendable {
  public static let lightSeed = PaletteSeed(
    dark: false,
    ground: "#C7CCE4", app: "#FFFFFF", chart: "#F4F6FD", raised: "#FFFFFF", raised2: "#ECEFF9",
    line: "#DCE0F0", grid: "#E4E7F5",
    ink: "#12163A", ink2: "#565C85", ink3: "#8B90B2",
    up: "#0E9E78", down: "#DE2E57", amber: "#B26A00",
    palette: ["#B26A00", "#4A55D6", "#0E8F73", "#C43A7E", "#7A5BD6", "#1A7FC4"])

  public static let darkSeed = PaletteSeed(
    dark: true,
    ground: "#07091C", app: "#0F1230", chart: "#161A3F", raised: "#1C2154", raised2: "#232858",
    line: "#2A2E6E", grid: "#232858",
    ink: "#EDEEF8", ink2: "#A6A9C0", ink3: "#6D719A",
    up: "#2FBF8F", down: "#F0567B", amber: "#FFB454",
    palette: ["#FFB454", "#8C95FF", "#4FD1B5", "#F78FB3", "#C8B6FF", "#7FD0FF"])

  /// 由原始令牌推出图表用色，逐行对应原型 `expand()`。
  public static func chart(_ t: PaletteSeed, redUp: Bool = false) -> ChartColors {
    let d = t.dark
    return ChartColors(
      bg: t.chart, grid: t.grid, axis: t.line, text: t.ink2, dim: t.ink3,
      ink: t.ink, amber: t.amber, cross: t.ink3,
      band: t.palette[4], oi: t.palette[5], oiFill: t.palette[5].alpha(d ? "33" : "2E"),
      chip: d ? t.ground : t.app, panel: t.app,
      crossBg: d ? t.line : t.ink, crossInk: d ? t.ink : t.app,
      hair: d ? Hex("#FFFFFF0A") : t.ink.alpha("0F"),
      amberSoft: t.amber.alpha(d ? "1A" : "16"), amberLine: t.amber.alpha("55"),
      up: redUp ? t.down : t.up, down: redUp ? t.up : t.down,
      palette: t.palette)
  }

  public static func chart(dark: Bool, redUp: Bool = false) -> ChartColors {
    chart(dark ? darkSeed : lightSeed, redUp: redUp)
  }

  /// 遮罩与薄纱，弹层用。
  public static func veil(_ t: PaletteSeed) -> Hex { t.app.alpha(t.dark ? "EE" : "F0") }
  public static func scrim(_ t: PaletteSeed) -> Hex { t.dark ? t.ground.alpha("D9") : t.ink.alpha("4D") }
}
