import Foundation

/// 十一款形态（§6，原型 `styles.js` 的 `STYLES`）。
///
/// 配色只有一套「靛」，风格换的只是 K 线自己和它周围的距离：形态、体积、影线、
/// 上下左右留白、网格形态、最新价线虚实。图表类型从头到尾只有蜡烛一种。
/// 表里的数字一个都不许改——原型即规格。
public struct CandleStyle: Sendable, Equatable, Identifiable, Codable {
  /// 影线端头。
  public enum WickCap: String, Sendable, Codable { case butt, round }

  /// 实体画法：实心 / 涨空心跌实心 / 只描边。
  public enum Shape: String, Sendable, Codable { case solid, hollowUp, outline }

  /// 网格：只横 / 横竖 / 不画 / 右端一小截刻度。
  public enum Grid: String, Sendable, Codable { case h, both, none, tick }

  public let id: String
  /// 一个字的名字，风格选择器里就显示这个。
  public let name: String
  /// 一行话。
  public let one: String
  /// 这款风格赌的是什么，说明页用。
  public let bet: String

  /// 实体占一根间距的比例。
  public let bodyR: Double
  /// 影线粗细（pt）。
  public let wick: Double
  public let wickCap: WickCap
  /// 影线相对实体的浓度，1 = 同色。
  public let wickTint: Double
  public let shape: Shape
  /// 实体圆角（pt）。
  public let radius: Double
  /// 十字星时实体的保底高度（px）。
  public let minBody: Double
  /// 默认根间距（pt）。
  public let spacing: Double
  /// 价格上下留白比例。
  public let pad: Double
  /// 右侧价格轴宽（pt）。
  public let axisW: Double
  /// 时间轴高（pt）。
  public let timeH: Double
  /// 单个副图高（pt）。
  public let subH: Double
  public let grid: Grid
  /// 最新价线是否虚线。
  public let lastDash: Bool

  public init(
    id: String, name: String, one: String, bet: String,
    bodyR: Double, wick: Double, wickCap: WickCap, wickTint: Double,
    shape: Shape, radius: Double, minBody: Double, spacing: Double, pad: Double,
    axisW: Double, timeH: Double, subH: Double, grid: Grid, lastDash: Bool
  ) {
    self.id = id; self.name = name; self.one = one; self.bet = bet
    self.bodyR = bodyR; self.wick = wick; self.wickCap = wickCap; self.wickTint = wickTint
    self.shape = shape; self.radius = radius; self.minBody = minBody
    self.spacing = spacing; self.pad = pad
    self.axisW = axisW; self.timeH = timeH; self.subH = subH
    self.grid = grid; self.lastDash = lastDash
  }
}

extension CandleStyle {
  /// 十一款，顺序与原型一致。第一款「墩」是默认（§3.2，定死）。
  public static let all: [CandleStyle] = [
    CandleStyle(
      id: "stout", name: "墩", one: "实体九成 · 圆头粗影线",
      bet: "默认。实体吃满八成六、圆角一点五，影线一点八还收圆头、比实体淡三成。一眼看清每一根。",
      bodyR: 0.86, wick: 1.8, wickCap: .round, wickTint: 0.7, shape: .solid, radius: 1.5, minBody: 2,
      spacing: 9.2, pad: 0.14, axisW: 58, timeH: 26, subH: 84, grid: .h, lastDash: false),
    CandleStyle(
      id: "indigo", name: "靛", one: "细实体 · 半像素影线",
      bet: "密度优先。实体只占五成五，影线半个设备像素，一屏塞得下最多的根数，网格横竖都留。",
      bodyR: 0.55, wick: 0.5, wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, minBody: 1,
      spacing: 4.8, pad: 0.08, axisW: 54, timeH: 22, subH: 74, grid: .both, lastDash: true),
    CandleStyle(
      id: "glow", name: "辉", one: "圆角实体 · 无网格",
      bet: "把网格整个拿掉，实体切两点六的圆角，影线减淡到六成，只剩价格自己的形状浮在底上。",
      bodyR: 0.70, wick: 1.2, wickCap: .round, wickTint: 0.6, shape: .solid, radius: 2.6, minBody: 2,
      spacing: 7.2, pad: 0.12, axisW: 52, timeH: 24, subH: 72, grid: .none, lastDash: false),
    CandleStyle(
      id: "airy", name: "阔", one: "上下左右全放开",
      bet: "专门赌距离：根间距 11、价格上下各留两成、副图 96、时间轴 30、右轴 62。根数少一半，呼吸多一倍。",
      bodyR: 0.58, wick: 1.0, wickCap: .round, wickTint: 1, shape: .solid, radius: 1, minBody: 1,
      spacing: 11, pad: 0.20, axisW: 62, timeH: 30, subH: 96, grid: .h, lastDash: true),
    CandleStyle(
      id: "brick", name: "砖", one: "实体几乎满格 · 影线极淡",
      bet: "实体占到九成六、彼此只留一线缝，影线细到半像素还淡掉一半。看的是实体连成的墙。",
      bodyR: 0.96, wick: 0.5, wickCap: .butt, wickTint: 0.45, shape: .solid, radius: 0, minBody: 3,
      spacing: 8.4, pad: 0.12, axisW: 56, timeH: 24, subH: 78, grid: .h, lastDash: false),
    CandleStyle(
      id: "needle", name: "针", one: "影线比实体还重",
      bet: "反过来：实体收到四成二，影线加粗到 2.0 收圆头。看的是插针和长影，不是实体。",
      bodyR: 0.42, wick: 2.0, wickCap: .round, wickTint: 0.9, shape: .solid, radius: 0.5, minBody: 2,
      spacing: 7.8, pad: 0.16, axisW: 54, timeH: 24, subH: 76, grid: .h, lastDash: true),
    CandleStyle(
      id: "pill", name: "芯", one: "细胶囊 · 上下带影线",
      bet: "实体只占四成但切满圆角，成一根细胶囊；十字星也保底四像素，不会塌成一条线。",
      bodyR: 0.40, wick: 1.0, wickCap: .round, wickTint: 1, shape: .solid, radius: 3, minBody: 4,
      spacing: 6.6, pad: 0.10, axisW: 52, timeH: 23, subH: 72, grid: .h, lastDash: true),
    CandleStyle(
      id: "paper", name: "纸", one: "涨空心 · 跌实心",
      bet: "东亚制图的老规矩：上涨留白、下跌落墨。实体放宽到六成四，只留横向网格。",
      bodyR: 0.64, wick: 0.8, wickCap: .butt, wickTint: 1, shape: .hollowUp, radius: 0, minBody: 1,
      spacing: 6.4, pad: 0.10, axisW: 48, timeH: 24, subH: 66, grid: .h, lastDash: true),
    CandleStyle(
      id: "outline", name: "描", one: "全部只留轮廓",
      bet: "涨跌都不填实，只留一圈描边靠颜色分方向，网格收成右端一小截刻度。",
      bodyR: 0.68, wick: 0.9, wickCap: .butt, wickTint: 0.85, shape: .outline, radius: 0, minBody: 1,
      spacing: 7.6, pad: 0.10, axisW: 50, timeH: 22, subH: 68, grid: .tick, lastDash: false),
    CandleStyle(
      id: "bone", name: "骨", one: "实体三成 · 只剩骨架",
      bet: "实体收到三成四、间距压到 3.4，影线撑起整根形态。看的是结构，不是单根情绪。",
      bodyR: 0.34, wick: 0.5, wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, minBody: 1,
      spacing: 3.4, pad: 0.06, axisW: 44, timeH: 20, subH: 58, grid: .tick, lastDash: true),
    CandleStyle(
      id: "dense", name: "密", one: "一屏塞进最多根",
      bet: "间距 2.6、留白五分、右轴 40、时间轴 18、副图 52，网格全去掉。用来看长段走势的形状。",
      bodyR: 0.62, wick: 0.5, wickCap: .butt, wickTint: 1, shape: .solid, radius: 0, minBody: 1,
      spacing: 2.6, pad: 0.05, axisW: 40, timeH: 18, subH: 52, grid: .none, lastDash: true),
  ]

  /// 默认「墩」。
  public static let `default`: CandleStyle = all[0]

  public static func style(id: String) -> CandleStyle { all.first { $0.id == id } ?? `default` }
}
