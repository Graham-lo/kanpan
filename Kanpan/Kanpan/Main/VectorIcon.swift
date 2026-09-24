import Foundation
import SwiftUI

/// 按 key 记住算过的结果。
///
/// 徽章那三层（记号定义、渐变配色、`d=` 串解析）都是纯函数：同样的入参永远算出
/// 同样的结果，而自选表一滚就要把它们整屏重算——每一帧、每一行、每一层。
/// `Shape.path(in:)` 不保证在主线程上调用，所以这里用锁，不用 `@MainActor`。
///
/// 满了就整桶倒掉：留在桶里的本来就是「这几屏在用的那些」，挑着淘汰不比
/// 重新攒一遍便宜。
final class RenderMemo<Key: Hashable, Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var box: [Key: Value] = [:]
  private let limit: Int

  init(limit: Int = 512) { self.limit = limit }

  func value(for key: Key, _ make: () -> Value) -> Value {
    lock.lock()
    let hit = box[key]
    lock.unlock()
    if let hit { return hit }
    // 算的时候不持锁：这几个函数都不便宜，也都不依赖缓存本身。
    // 两条线程同时算同一个 key 只是白算一次，结果一模一样。
    let made = make()
    lock.lock()
    if box.count >= limit { box.removeAll(keepingCapacity: true) }
    box[key] = made
    lock.unlock()
    return made
  }
}

/// 原型里那些手画的小图标，原样搬过来。
///
/// 为什么不用 SF Symbols：原型的图标是按 `style.css` 的字号和 1.5/1.6 的描边配好的，
/// 换成系统符号后粗细、留白、视觉重心全不一样，底栏五个挤在一起时立刻看得出来。
/// 这里保留原型的 `viewBox` 坐标和 `d=` 串，等比缩放到目标尺寸——改图标只要把
/// 原型里那一行拷过来。
struct VectorIcon: View {
  /// 原型 `viewBox` 的边长（都是正方形）。
  var box: Double
  var size: Double
  var lineWidth: Double = 1.6
  var items: [IconItem]

  var body: some View {
    IconShape(box: box, items: items)
      .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
      .frame(width: size, height: size)
  }
}

enum IconItem: Equatable {
  case path(String)
  case circle(x: Double, y: Double, r: Double)
  case rect(x: Double, y: Double, w: Double, h: Double, r: Double)
}

/// 把一组 `IconItem` 摊成一条 `Path`，等比缩到给定的框里。
///
/// 它本来是 `VectorIcon` 的私有实现。底栏那四个记号要分层上色——蜡烛是实心的身子加
/// 一根描边的影线，星和螺母选中时里头填实——而 `VectorIcon` 是「一套路径、一个描边色」，
/// 表达不了。所以把这一层露出来，让 `TabGlyph` 直接拿它 `.fill` / `.stroke` 地叠。
struct IconShape: Shape {
  var box: Double
  var items: [IconItem]

  func path(in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) / box
    var p = Path()
    for item in items {
      switch item {
      case .path(let d):
        p.addPath(SVGPath.parsed([d]))
      case .circle(let x, let y, let r):
        p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
      case .rect(let x, let y, let w, let h, let r):
        p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
      }
    }
    return p.applying(CGAffineTransform(scaleX: k, y: k))
  }
}

/// `d=` 串的解析器：M/L/H/V/Z 加三条曲线命令 C/S/Q/T 和圆弧 A，大小写都认。
///
/// 原来只有直线，够画原型里那些线性图标，但品种徽章要的是真的品牌记号——
/// 苹果那一口、亚马逊那道弧、Meta 那个无限符，没有曲线就只能退回去写字母，
/// 而「图标是两个字母」正是用户挑出来的毛病。遇到不认识的命令仍旧直接忽略，
/// 不要让它悄悄画歪。
enum SVGPath {
  /// 解析好的路径，坐标还是 `d=` 串自己那套（调用方自己缩）。同一串只解析一次。
  ///
  /// 一枚徽章的记号是一到两层、每层一串到七串 `d=`；一屏自选二十几行，每行一枚，
  /// 每次重画都要把这些串重新扫一遍字符、拆成命令和数字、再一段段 `addCurve`。
  /// 这些串是写死在代码和资源文件（`CoinBadgeBrands.json`）里的常量，解析结果永远一样。
  static func parsed(_ paths: [String]) -> Path {
    memo.value(for: paths) {
      var p = Path()
      for d in paths { append(d, to: &p) }
      return p
    }
  }

  private static let memo = RenderMemo<[String], Path>()

  static func append(_ d: String, to p: inout Path) {
    var cur = CGPoint.zero
    var start = CGPoint.zero
    var open = false
    // 平滑命令（S / T）要拿上一条曲线的控制点做镜像；上一条不是同类曲线时，
    // 按 SVG 规矩镜像点就取当前点本身。
    var lastCubic: CGPoint?
    var lastQuad: CGPoint?
    for (cmd, a) in tokenize(d) {
      let lower = Character(cmd.lowercased())
      if lower != "c" && lower != "s" { lastCubic = nil }
      if lower != "q" && lower != "t" { lastQuad = nil }
      let rel = cmd.isLowercase
      switch Character(cmd.lowercased()) {
      case "m":
        var i = 0
        while i + 1 < a.count {
          let q = point(a[i], a[i + 1], rel: rel, from: cur)
          // 第一对是 moveTo，后面跟的成对数字按 SVG 规矩当 lineTo。
          if i == 0 {
            p.move(to: q); start = q; open = true
          } else if open {
            p.addLine(to: q)
          }
          cur = q
          i += 2
        }
      case "l":
        var i = 0
        while i + 1 < a.count {
          let q = point(a[i], a[i + 1], rel: rel, from: cur)
          if open { p.addLine(to: q) }
          cur = q
          i += 2
        }
      case "h":
        for v in a {
          let q = CGPoint(x: rel ? cur.x + v : v, y: cur.y)
          if open { p.addLine(to: q) }
          cur = q
        }
      case "v":
        for v in a {
          let q = CGPoint(x: cur.x, y: rel ? cur.y + v : v)
          if open { p.addLine(to: q) }
          cur = q
        }
      case "c":
        var i = 0
        while i + 5 < a.count {
          let c1 = point(a[i], a[i + 1], rel: rel, from: cur)
          let c2 = point(a[i + 2], a[i + 3], rel: rel, from: cur)
          let q = point(a[i + 4], a[i + 5], rel: rel, from: cur)
          if open { p.addCurve(to: q, control1: c1, control2: c2) }
          lastCubic = c2
          cur = q
          i += 6
        }
      case "s":
        var i = 0
        while i + 3 < a.count {
          let c1 = mirror(lastCubic, about: cur)
          let c2 = point(a[i], a[i + 1], rel: rel, from: cur)
          let q = point(a[i + 2], a[i + 3], rel: rel, from: cur)
          if open { p.addCurve(to: q, control1: c1, control2: c2) }
          lastCubic = c2
          cur = q
          i += 4
        }
      case "q":
        var i = 0
        while i + 3 < a.count {
          let c = point(a[i], a[i + 1], rel: rel, from: cur)
          let q = point(a[i + 2], a[i + 3], rel: rel, from: cur)
          if open { p.addQuadCurve(to: q, control: c) }
          lastQuad = c
          cur = q
          i += 4
        }
      case "t":
        var i = 0
        while i + 1 < a.count {
          let c = mirror(lastQuad, about: cur)
          let q = point(a[i], a[i + 1], rel: rel, from: cur)
          if open { p.addQuadCurve(to: q, control: c) }
          lastQuad = c
          cur = q
          i += 2
        }
      case "a":
        var i = 0
        while i + 6 < a.count {
          let q = point(a[i + 5], a[i + 6], rel: rel, from: cur)
          if open {
            arc(from: cur, to: q, rx: a[i], ry: a[i + 1], rotation: a[i + 2],
                large: a[i + 3] != 0, sweep: a[i + 4] != 0, into: &p)
          }
          cur = q
          i += 7
        }
      case "z":
        if open { p.closeSubpath() }
        cur = start
      default:
        break
      }
    }
  }

  private static func mirror(_ control: CGPoint?, about c: CGPoint) -> CGPoint {
    guard let control else { return c }
    return CGPoint(x: 2 * c.x - control.x, y: 2 * c.y - control.y)
  }

  /// SVG 的 `A` 是「端点参数」写法，CoreGraphics 要的是圆心加起止角，
  /// 所以照规范附录 F.6.5 换算一遍。半径给小了就按规范放大到刚好够。
  private static func arc(from p0: CGPoint, to p1: CGPoint, rx: Double, ry: Double,
                          rotation: Double, large: Bool, sweep: Bool, into path: inout Path) {
    var rx = abs(rx), ry = abs(ry)
    guard rx > 0, ry > 0, p0 != p1 else {
      path.addLine(to: p1)
      return
    }
    let phi = rotation * .pi / 180
    let cosPhi = cos(phi), sinPhi = sin(phi)
    let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
    let x1 = cosPhi * dx + sinPhi * dy
    let y1 = -sinPhi * dx + cosPhi * dy
    let over = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
    if over > 1 {
      let k = over.squareRoot()
      rx *= k
      ry *= k
    }
    let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    let coef = (large == sweep ? -1.0 : 1.0) * (den == 0 ? 0 : (num / den).squareRoot())
    let cx1 = coef * rx * y1 / ry
    let cy1 = -coef * ry * x1 / rx
    let cx = cosPhi * cx1 - sinPhi * cy1 + (p0.x + p1.x) / 2
    let cy = sinPhi * cx1 + cosPhi * cy1 + (p0.y + p1.y) / 2
    func angle(_ x: Double, _ y: Double) -> Double { atan2((y - cy1) / ry, (x - cx1) / rx) }
    let start = atan2((y1 - cy1) / ry, (x1 - cx1) / rx)
    let end = atan2((-y1 - cy1) / ry, (-x1 - cx1) / rx)
    _ = angle
    // 椭圆弧先在单位圆上摆好，再用一个仿射把它拉成 rx × ry 并转 `phi`。
    var unit = Path()
    unit.addArc(center: .zero, radius: 1, startAngle: .radians(start), endAngle: .radians(end),
                clockwise: !sweep)
    let t = CGAffineTransform(translationX: cx, y: cy)
      .rotated(by: phi)
      .scaledBy(x: rx, y: ry)
    // 接到当前子路径上，**不能**用 `addPath`——那会另起一条子路径。
    //
    // 一个圆常写成 `M12 5a7 7 0 1 1 0 14 7 7 0 0 1 0-14z`：上半弧、下半弧、闭合。
    // 两段弧各自成子路径的话，最后那个 `z` 闭的就只是下半弧，于是从弧尾拉一条弦回弧头，
    // 描边出来是「圆里横着一根杠」。品种徽章里凡是圆环的记号（COIN 的圆中方、
    // 长尾那枚环）都中过这一刀。所以把弧的各段直接续到当前子路径上，起点那一下
    // 由 `move` 改成 `line`。
    append(unit.applying(t), to: &path)
  }

  /// 把一条已经算好的子路径续到 `path` 末尾：头一个 `move` 当 `line` 用，其余照搬。
  private static func append(_ piece: Path, to path: inout Path) {
    var first = true
    piece.forEach { element in
      switch element {
      case .move(let to):
        if first, path.currentPoint != nil { path.addLine(to: to) } else { path.move(to: to) }
      case .line(let to):
        path.addLine(to: to)
      case .quadCurve(let to, let control):
        path.addQuadCurve(to: to, control: control)
      case .curve(let to, let control1, let control2):
        path.addCurve(to: to, control1: control1, control2: control2)
      case .closeSubpath:
        path.closeSubpath()
      }
      first = false
    }
  }

  private static func point(_ x: Double, _ y: Double, rel: Bool, from c: CGPoint) -> CGPoint {
    rel ? CGPoint(x: c.x + x, y: c.y + y) : CGPoint(x: x, y: y)
  }

  /// 切成 (命令, 参数表)。数字可能连着写（`4.6.6` 是两个数），所以自己扫。
  private static func tokenize(_ d: String) -> [(Character, [Double])] {
    var out: [(Character, [Double])] = []
    var cmd: Character?
    var args: [Double] = []
    let s = Array(d)
    var i = 0
    func flush() {
      if let c = cmd { out.append((c, args)) }
      args = []
    }
    while i < s.count {
      let c = s[i]
      if c.isLetter {
        flush()
        cmd = c
        i += 1
        continue
      }
      if c == "," || c == " " || c == "\n" || c == "\t" {
        i += 1
        continue
      }
      var j = i
      if s[j] == "-" || s[j] == "+" { j += 1 }
      var dot = false
      while j < s.count {
        if s[j].isNumber {
          j += 1
        } else if s[j] == "." && !dot {
          dot = true
          j += 1
        } else {
          break
        }
      }
      guard j > i, let v = Double(String(s[i..<j])) else {
        i += 1
        continue
      }
      args.append(v)
      i = j
    }
    flush()
    return out
  }
}

// MARK: - 原型里的那几个

extension VectorIcon {
  /// 顶栏品种按钮上的下箭头。
  static func chevron(_ size: Double = 11, w: Double = 1.6) -> VectorIcon {
    VectorIcon(box: 12, size: size, lineWidth: w, items: [.path("M3 4.5 6 7.5 9 4.5")])
  }

  static func search(_ size: Double = 17) -> VectorIcon {
    VectorIcon(box: 18, size: size, items: [.circle(x: 8, y: 8, r: 5.2), .path("M12 12l3.5 3.5")])
  }

  static func star(_ size: Double = 17) -> VectorIcon {
    VectorIcon(
      box: 18, size: size, lineWidth: 1.5,
      items: [.path("M9 2.2l2 4.2 4.6.6-3.4 3.2.9 4.6L9 12.6 4.9 14.8l.9-4.6L2.4 7l4.6-.6z")])
  }

  /// 图区右下角「回到最新」。
  static func chevronRight(_ size: Double = 14) -> VectorIcon {
    VectorIcon(box: 16, size: size, lineWidth: 1.7, items: [.path("M5.5 3.5 10 8l-4.5 4.5")])
  }

  /// 周期条行尾「返回刚才」。和上面那颗是一对，方向反过来。
  static func chevronLeft(_ size: Double = 14) -> VectorIcon {
    VectorIcon(box: 16, size: size, lineWidth: 1.7, items: [.path("M10.5 3.5 6 8l4.5 4.5")])
  }

  static let toolBox = 20.0

  static func tool(_ items: [IconItem], _ size: Double = 19) -> VectorIcon {
    VectorIcon(box: toolBox, size: size, lineWidth: 1.5, items: items)
  }

  static var style: VectorIcon {
    tool([
      .rect(x: 2.5, y: 7, w: 3.6, h: 10.5, r: 1),
      .rect(x: 8.2, y: 3, w: 3.6, h: 14.5, r: 1),
      .rect(x: 13.9, y: 9, w: 3.6, h: 8.5, r: 1),
    ])
  }

  static var draw: VectorIcon {
    tool([.path("M3 17 17 3"), .circle(x: 4.4, y: 15.6, r: 1.8), .circle(x: 15.6, y: 4.4, r: 1.8)])
  }

  static var settings: VectorIcon {
    tool([
      .circle(x: 10, y: 10, r: 2.6),
      .path("M10 2.6v2M10 15.4v2M2.6 10h2M15.4 10h2M4.8 4.8l1.4 1.4M13.8 13.8l1.4 1.4M15.2 4.8l-1.4 1.4M6.2 13.8l-1.4 1.4"),
    ])
  }

  /// K 线设置（横屏工具栏的「图表」）。两根蜡烛：框 + 上下影线。
  static var chart: VectorIcon {
    tool([
      .rect(x: 3.5, y: 6, w: 4, h: 8, r: 0.8), .path("M5.5 2.6v3.4M5.5 14v3.4"),
      .rect(x: 12.5, y: 4.5, w: 4, h: 6, r: 0.8), .path("M14.5 2.6v1.9M14.5 10.5v6.9"),
    ])
  }

  /// 周期条行尾那颗「图表设置」（审查 U12）：两根调节杆，各带一颗旋钮。
  ///
  /// 那儿原来写着「图表」两个字，和底栏的「图表」格同名，开的却是图表设置那张面板。
  /// 不改写成「设置」——底栏最右那一格就叫设置，同名的毛病只是换了个对象。
  /// 描边的粗细、字号和它旁边的「更多 ▾」、顶栏的放大镜是同一套，读起来仍是一行字。
  static func adjust(_ size: Double = 15) -> VectorIcon {
    VectorIcon(
      box: 18, size: size, lineWidth: 1.6,
      items: [
        .path("M2.5 5.5h6.4M13.6 5.5h1.9"), .circle(x: 11.25, y: 5.5, r: 2.1),
        .path("M2.5 12.5h1.9M9.1 12.5h6.4"), .circle(x: 6.75, y: 12.5, r: 2.1),
      ])
  }

  static var landscape: VectorIcon {
    tool([.rect(x: 2.5, y: 5.5, w: 15, h: 9, r: 1.6), .path("M7 2.6 9 4.6 7 6.6")])
  }
}
