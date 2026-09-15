import Foundation

/// 蜡烛的造型。尺寸、坐标轴、布局与手势都在共用的图表基座里，这里只管「长什么样」。
///
/// 这里原来摆着十二套：AICoin 一套，加上从原型带过来的十一款（墩／靛／辉／阔／砖／针／
/// 芯／纸／描／骨／密），「图表」面板上还有一张四选一的风格卡。用户 2026-09-15 定了：
/// 「k 线风格直接默认 aicoin 那套就行了，不用搞那么多套」。看盘这套视觉本来就是照着
/// 手机 AICoin 抄的（默认风格的 id 就叫 `aicoin`），多出来的十一款既不是谁在用，又让
/// 每改一次渲染都得横着验十二遍——量成交量颜色那次就是十二套一起量的。所以只留这一套。
///
/// 结构体本身留着不动：渲染器读的是 `shape / wickCap / wickTint / radius / grid` 这几个
/// 字段，不是读一个风格 id；把它们摊平成常量等于把造型散进渲染器各处，反而更难改。
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

  public static let aicoin = CandleStyle(id: "aicoin", name: "AICoin", wickCap: .butt,
    wickTint: 1, shape: .solid, radius: 0, grid: .none)
  public static let all: [CandleStyle] = [aicoin]
  public static let `default` = aicoin
  /// 只剩一套了，但调用点（旧存档解码、测试）还按 id 要，就一律给这一套。
  public static func style(id _: String) -> CandleStyle { aicoin }
}
