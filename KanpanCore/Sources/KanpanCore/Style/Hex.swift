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
