import Foundation

/// Visual skins only. Candle dimensions, axes, layout and gestures live in the shared chart base.
public struct CandleStyle: Sendable, Equatable, Identifiable, Codable {
  public enum WickCap: String, Sendable, Codable { case butt, round }
  public enum Shape: String, Sendable, Codable { case solid, hollowUp, outline }
  public enum Grid: String, Sendable, Codable { case h, both, none, tick }
  public let id: String
  public let name: String
  public let wickCap: WickCap
  public let wickTint: Double
  public let shape: Shape
  public let radius: Double
  public let grid: Grid

  public var visualSummary: String {
    let body = shape == .hollowUp ? "阳线空心" : shape == .outline ? "轮廓" : "实心"
    return (radius > 0 ? "圆角" : "直角") + body + (wickCap == .round ? " · 圆头影线" : " · 平头影线")
  }

  public static let aicoin = CandleStyle(id: "aicoin", name: "AICoin", wickCap: .butt,
    wickTint: 1, shape: .solid, radius: 0, grid: .none)
  public static let originalStyles: [CandleStyle] = [
    .init(id: "stout", name: "墩", wickCap: .round, wickTint: 0.7, shape: .solid, radius: 1.5, grid: .h),
    .init(id: "indigo", name: "靛", wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, grid: .both),
    .init(id: "glow", name: "辉", wickCap: .round, wickTint: 0.6, shape: .solid, radius: 2.6, grid: .none),
    .init(id: "airy", name: "阔", wickCap: .round, wickTint: 1, shape: .solid, radius: 1, grid: .h),
    .init(id: "brick", name: "砖", wickCap: .butt, wickTint: 0.45, shape: .solid, radius: 0, grid: .h),
    .init(id: "needle", name: "针", wickCap: .round, wickTint: 0.9, shape: .solid, radius: 0.5, grid: .h),
    .init(id: "pill", name: "芯", wickCap: .round, wickTint: 1, shape: .solid, radius: 3, grid: .h),
    .init(id: "paper", name: "纸", wickCap: .butt, wickTint: 1, shape: .hollowUp, radius: 0, grid: .h),
    .init(id: "outline", name: "描", wickCap: .butt, wickTint: 0.85, shape: .outline, radius: 0, grid: .tick),
    .init(id: "bone", name: "骨", wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, grid: .tick),
    .init(id: "dense", name: "密", wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, grid: .none)
  ]
  public static let all = [aicoin] + originalStyles
  public static let `default` = aicoin
  public static func style(id: String) -> CandleStyle { all.first { $0.id == id } ?? .aicoin }
}
