import Foundation

/// 画线：只有水平线和趋势线两种（§7.5，原型 `draws`）。
///
/// 端点存的是**时间 + 价格**，不是像素——缩放、换周期、切对数轴之后线还在原来的
/// 位置上。命中判定的三个阈值（手柄 12、线身 9、水平线 9）照抄原型。

/// 一个端点。
public struct DrawPoint: Sendable, Equatable, Codable {
  /// 毫秒时间戳。
  public var t: Double
  /// 价格。
  public var p: Double

  public init(t: Double, p: Double) {
    self.t = t
    self.p = p
  }
}

public struct Drawing: Sendable, Equatable, Identifiable, Codable {
  public enum Kind: String, Sendable, Codable { case hline, trend }
  /// 命中到哪个部位。
  public enum Part: String, Sendable, Equatable { case a, b, body }

  public var id: String
  public var kind: Kind
  public var a: DrawPoint
  /// 趋势线的第二个点；水平线没有。
  public var b: DrawPoint?
  /// 不给就用主题的 `band` 色。
  public var color: Hex?

  public init(id: String = Drawing.newID(), kind: Kind, a: DrawPoint, b: DrawPoint? = nil, color: Hex? = nil) {
    self.id = id
    self.kind = kind
    self.a = a
    self.b = b
    self.color = color
  }

  /// 原型是 `'d' + Date.now()`，同一毫秒内连画两条会撞号——撞了之后选中和删除都会
  /// 连坐。这里保留同样的前缀，再补一个进程内自增的尾巴。
  public static func newID() -> String {
    "d\(Int(Date().timeIntervalSince1970 * 1000))-\(idSeq.next())"
  }

  /// 价格区间要把画线端点算进去（§5.4）。
  public var prices: [Double] { kind == .hline ? [a.p] : [a.p, b?.p ?? a.p] }
}

/// 命中结果。
public struct DrawHit: Sendable, Equatable {
  public var id: String
  public var part: Drawing.Part
}

/// 点到线段的距离（原型 `distSeg`）。
public func distSeg(_ px: Double, _ py: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
  let dx = x2 - x1, dy = y2 - y1
  let len = dx * dx + dy * dy
  var t = len != 0 ? ((px - x1) * dx + (py - y1) * dy) / len : 0
  t = max(0, min(1, t))
  return ((px - (x1 + t * dx)) * (px - (x1 + t * dx)) + (py - (y1 + t * dy)) * (py - (y1 + t * dy))).squareRoot()
}

/// 画线集合的命中判定。从最后一条往前找——后画的在上面。
///
/// `xOf` / `yOf` 由调用方给：时间→x、价格→y，Core 不知道 pane 长什么样。
public func hitDraw(
  _ draws: [Drawing], px: Double, py: Double,
  xOf: (Double) -> Double, yOf: (Double) -> Double
) -> DrawHit? {
  for d in draws.reversed() {
    if d.kind == .hline {
      if abs(yOf(d.a.p) - py) < Chart.hitLinePt { return DrawHit(id: d.id, part: .body) }
      continue
    }
    guard let b = d.b else { continue }
    let x1 = xOf(d.a.t), y1 = yOf(d.a.p)
    let x2 = xOf(b.t), y2 = yOf(b.p)
    if ((px - x1) * (px - x1) + (py - y1) * (py - y1)).squareRoot() < Chart.hitHandlePt {
      return DrawHit(id: d.id, part: .a)
    }
    if ((px - x2) * (px - x2) + (py - y2) * (py - y2)).squareRoot() < Chart.hitHandlePt {
      return DrawHit(id: d.id, part: .b)
    }
    if distSeg(px, py, x1, y1, x2, y2) < Chart.hitLinePt { return DrawHit(id: d.id, part: .body) }
  }
  return nil
}

/// 画线的编辑状态：待落的第二点、选中项、当前工具。
public struct DrawingStore: Sendable, Equatable {
  public enum Tool: String, Sendable, Equatable { case hline, trend }

  public var items: [Drawing] = []
  public var selected: String?
  /// 趋势线落了第一点、还差第二点。
  public var pending: DrawPoint?
  public var tool: Tool?
  /// 吸附到 K 线中心。
  public var magnet = true

  public init() {}

  /// 落一个点。趋势线要落两次。
  public mutating func place(_ pt: DrawPoint, id: String = Drawing.newID()) {
    switch tool {
    case .hline:
      items.append(Drawing(id: id, kind: .hline, a: pt))
      tool = nil
      pending = nil
    case .trend:
      if let first = pending {
        items.append(Drawing(id: id, kind: .trend, a: first, b: pt))
        pending = nil
        tool = nil
      } else {
        pending = pt
      }
    case nil:
      break
    }
  }

  public mutating func removeSelected() {
    guard let sel = selected else { return }
    items.removeAll { $0.id == sel }
    selected = nil
  }

  public mutating func clear() {
    items = []
    selected = nil
    pending = nil
  }

  /// 拖动：`part` 决定动哪一端，`body` 两端一起走。
  public mutating func move(id: String, part: Drawing.Part, from start: Drawing, dt: Double, dp: Double) {
    guard let i = items.firstIndex(where: { $0.id == id }) else { return }
    switch part {
    case .a:
      items[i].a = DrawPoint(t: start.a.t + dt, p: start.a.p + dp)
    case .b:
      if let sb = start.b { items[i].b = DrawPoint(t: sb.t + dt, p: sb.p + dp) }
    case .body:
      items[i].a = DrawPoint(t: start.a.t + dt, p: start.a.p + dp)
      if let sb = start.b { items[i].b = DrawPoint(t: sb.t + dt, p: sb.p + dp) }
    }
  }

  /// 所有画线端点的价格，喂给 `priceRange`。
  public var prices: [Double] { items.flatMap(\.prices) }
}

/// 画线 ID 的自增尾号。画线是用户手速级别的低频操作，一把锁足够。
private final class IDSeq: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    n += 1
    return n
  }
}

private let idSeq = IDSeq()
