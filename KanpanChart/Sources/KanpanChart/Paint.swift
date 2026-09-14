import CoreGraphics
import KanpanCore
import UIKit

/// 把 `Hex` 变成 CoreGraphics 认的颜色。
///
/// 原型里颜色都是 `#RRGGBB` 或 `#RRGGBBAA` 的字符串，`Hex.rgba` 已经按同一套规则
/// 解好了；这里只是加一层缓存——一帧要问几百次颜色，每次现算 CGColor 太亏。
enum Paint {
  private nonisolated(unsafe) static var cache: [String: CGColor] = [:]
  private static let lock = NSLock()

  static func cg(_ h: Hex) -> CGColor {
    lock.lock(); defer { lock.unlock() }
    if let c = cache[h.value] { return c }
    let (r, g, b, a) = h.rgba
    let c = CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    cache[h.value] = c
    return c
  }

  /// 原型的 `mixHex(a, b, k)`：在 a 和 b 之间按 k 取色，整数通道、输出小写。
  /// 影线的 `wickTint` 就是靠它把影线往底色里掺淡的。
  static func mix(_ a: Hex, _ b: Hex, _ k: Double) -> Hex { KanpanCore.mixHex(a, b, k) }
}

extension CGContext {
  /// 描一条压在设备像素中线上的横线（原型的 `hair()`）。
  func hairLine(from x0: CGFloat, to x1: CGFloat, y: Double, scale: CGFloat, color: CGColor) {
    let yy = CGFloat(hairline(y, scale: Double(scale)))
    setStrokeColor(color)
    setLineWidth(1 / scale)
    beginPath()
    move(to: CGPoint(x: x0, y: yy))
    addLine(to: CGPoint(x: x1, y: yy))
    strokePath()
  }

  func hairLineV(x: Double, from y0: CGFloat, to y1: CGFloat, scale: CGFloat, color: CGColor) {
    let xx = CGFloat(hairline(x, scale: Double(scale)))
    setStrokeColor(color)
    setLineWidth(1 / scale)
    beginPath()
    move(to: CGPoint(x: xx, y: y0))
    addLine(to: CGPoint(x: xx, y: y1))
    strokePath()
  }

  /// 原型的 `roundRect`：半径大于半边长时自动收敛，不会画出打结的角。
  func addRoundRect(_ r: CGRect, radius: CGFloat) {
    let rr = min(radius, min(r.width, r.height) / 2)
    if rr <= 0 { addRect(r); return }
    beginPath()
    move(to: CGPoint(x: r.minX + rr, y: r.minY))
    addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rr)
    addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: rr)
    addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: rr)
    addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: rr)
    closePath()
  }
}

/// 轴上那些 10pt 等宽小字。
///
/// 原型用的是 `ui-monospace, SFMono-Regular, Menlo`；iOS 上对应
/// `.monospacedDigitSystemFont`——数字等宽，但中文标签（月、日）还走系统字，
/// 跟浏览器把 CJK 落回系统字的行为是一致的。
enum ChartFont {
  static let axis = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
  static let legend = UIFont.systemFont(ofSize: 10, weight: .medium)
  /// 比价格胶囊小一号，给挂在它底下的倒计时用：两格叠在右轴上，字号一样会显得头重。
  /// 等宽数字是必须的——倒计时每秒都在变，比例数字会让整格左右抖。
  static let tiny = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

  static func attrs(_ font: UIFont, _ color: Hex) -> [NSAttributedString.Key: Any] {
    [.font: font, .foregroundColor: UIColor(cgColor: Paint.cg(color))]
  }
}

extension String {
  func width(_ font: UIFont) -> CGFloat { (self as NSString).size(withAttributes: [.font: font]).width }

  /// 以 (x, y) 为中心画。CoreText 的基线和原型 `textBaseline = 'middle'` 对齐靠这个。
  func drawCentered(at p: CGPoint, font: UIFont, color: Hex) {
    let a = ChartFont.attrs(font, color)
    let s = (self as NSString).size(withAttributes: a)
    (self as NSString).draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: a)
  }

  /// 左对齐、纵向居中。
  func drawLeft(at p: CGPoint, font: UIFont, color: Hex) {
    let a = ChartFont.attrs(font, color)
    let s = (self as NSString).size(withAttributes: a)
    (self as NSString).draw(at: CGPoint(x: p.x, y: p.y - s.height / 2), withAttributes: a)
  }
}

extension String {
  /// 右对齐、以 (x, y) 为文字底边（原型 `textAlign='right'; textBaseline='bottom'`）。
  func drawRightBottom(at p: CGPoint, font: UIFont, color: Hex) {
    let a = ChartFont.attrs(font, color)
    let s = (self as NSString).size(withAttributes: a)
    (self as NSString).draw(at: CGPoint(x: p.x - s.width, y: p.y - s.height), withAttributes: a)
  }
}
