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
  public var line, grid, hair: Hex
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
    ground: "#C7CCE4", app: "#FFFFFF", chart: "#FFFFFF", raised: "#FFFFFF", raised2: "#ECEFF9",
    line: "#DCE0F0", grid: "#EDEFF6", hair: "#12163A0F",
    ink: "#12163A", ink2: "#565C85", ink3: "#8B90B2",
    up: "#34B257", down: "#E64553", amber: "#B26A00",
    palette: ["#B26A00", "#4A55D6", "#0E8F73", "#C43A7E", "#7A5BD6", "#1A7FC4"])

  public static let darkSeed = PaletteSeed(
    dark: true,
    ground: "#07091C", app: "#0F1230", chart: "#161A3F", raised: "#1C2154", raised2: "#232858",
    line: "#2A2E6E", grid: "#232858", hair: "#FFFFFF0A",
    ink: "#EDEEF8", ink2: "#A6A9C0", ink3: "#6D719A",
    up: "#3DC65C", down: "#F2555B", amber: "#FFB454",
    palette: ["#FFB454", "#8C95FF", "#4FD1B5", "#F78FB3", "#C8B6FF", "#7FD0FF"])

  public static let paperSeed = PaletteSeed(
    dark: false,
    ground: "#B7B2A0", app: "#F4F0E4", chart: "#EDE8D9", raised: "#FAF7EE", raised2: "#E5DFCD",
    line: "#D9D2BD", grid: "#E3DDC9", hair: "#3A35241A",
    ink: "#2F2C25", ink2: "#625D4D", ink3: "#736D5D",
    up: "#387A58", down: "#B74B3F", amber: "#96660F",
    palette: ["#96660F", "#5A63A8", "#3F8A63", "#A85A78", "#7A6BA8", "#3F7FA0"])

  public static let nightSeed = PaletteSeed(
    dark: true,
    ground: "#0D0C0A", app: "#191712", chart: "#201D17", raised: "#262219", raised2: "#2C281F",
    line: "#3A342A", grid: "#2C281F", hair: "#FFFFFF0A",
    ink: "#E0DAC9", ink2: "#A19A86", ink3: "#887F6A",
    up: "#56A883", down: "#D3766A", amber: "#D3A15C",
    palette: ["#D3A15C", "#9AA0D8", "#6FC2A4", "#D99BB0", "#BDAEDC", "#85B8D6"])

  public static func isComfort(_ t: PaletteSeed) -> Bool {
    t.ground == paperSeed.ground || t.ground == nightSeed.ground
  }

  /// Preserve prototype seeds; derive readable small text for actual surfaces.
  public static func secondaryInk(_ t: PaletteSeed) -> Hex {
    if t == paperSeed { return paperSecondary }
    if t == nightSeed { return nightSecondary }
    return t.ink3
  }

  private static let paperSecondary = readable(paperSeed.ink3, on: [paperSeed.app, paperSeed.raised, paperSeed.raised2], toward: paperSeed.ink)
  private static let nightSecondary = readable(nightSeed.ink3, on: [nightSeed.app, nightSeed.raised, nightSeed.raised2], toward: nightSeed.ink)
  private static let paperColors = expanded(paperSeed)
  private static let nightColors = expanded(nightSeed)

  /// Relative luminance contrast for opaque sRGB tokens. Composite alpha layers first.
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
  public static func chart(_ t: PaletteSeed, redUp: Bool = false) -> ChartColors {
    var result = t == paperSeed ? paperColors : (t == nightSeed ? nightColors : expanded(t))
    if redUp { swap(&result.up, &result.down) }
    return result
  }

  private static func expanded(_ t: PaletteSeed) -> ChartColors {
    let d = t.dark
    let colors = isComfort(t) ? t.palette.map { readable($0, on: [t.app], toward: t.ink) } : t.palette
    return ChartColors(
      bg: isComfort(t) ? t.app : t.chart, grid: t.grid, axis: t.line, text: t.ink2, dim: secondaryInk(t),
      ink: t.ink, amber: isComfort(t) ? colors[0] : t.amber, cross: t.ink3,
      band: colors[4], oi: colors[5], oiFill: colors[5].alpha(d ? "33" : "2E"),
      chip: d ? t.ground : t.app, panel: t.app,
      crossBg: d ? t.line : t.ink, crossInk: d ? t.ink : t.app,
      hair: t.hair,
      amberSoft: t.amber.alpha(d ? "1A" : "16"), amberLine: t.amber.alpha("55"),
      up: t.up, down: t.down,
      palette: colors)
  }

  public static func chart(dark: Bool, redUp: Bool = false) -> ChartColors {
    chart(dark ? darkSeed : lightSeed, redUp: redUp)
  }

  /// 遮罩与薄纱，弹层用。
  public static func veil(_ t: PaletteSeed) -> Hex { t.app.alpha(t.dark ? "EE" : "F0") }
  public static func scrim(_ t: PaletteSeed) -> Hex { t.dark ? t.ground.alpha("D9") : t.ink.alpha("4D") }
}
