import SwiftUI

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

private struct IconShape: Shape {
  var box: Double
  var items: [IconItem]

  func path(in rect: CGRect) -> Path {
    let k = min(rect.width, rect.height) / box
    var p = Path()
    for item in items {
      switch item {
      case .path(let d):
        SVGPath.append(d, to: &p)
      case .circle(let x, let y, let r):
        p.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
      case .rect(let x, let y, let w, let h, let r):
        p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
      }
    }
    return p.applying(CGAffineTransform(scaleX: k, y: k))
  }
}

/// `d=` 串的最小解析器：只认 M/L/H/V/Z 和它们的小写。
///
/// 原型的图标只用到这几条命令（圆弧只出现在假状态栏的 wifi 上，真机不画），
/// 所以不做完整实现——遇到没见过的命令直接忽略，不要让它悄悄画歪。
enum SVGPath {
  static func append(_ d: String, to p: inout Path) {
    var cur = CGPoint.zero
    var start = CGPoint.zero
    var open = false
    for (cmd, a) in tokenize(d) {
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
      case "z":
        if open { p.closeSubpath() }
        cur = start
      default:
        break
      }
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

  static var indicator: VectorIcon {
    tool([.path("M2.5 13.5 6.5 8l3.5 3.5L17 4"), .path("M2.5 17h15")])
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

  static var landscape: VectorIcon {
    tool([.rect(x: 2.5, y: 5.5, w: 15, h: 9, r: 1.6), .path("M7 2.6 9 4.6 7 6.6")])
  }
}
