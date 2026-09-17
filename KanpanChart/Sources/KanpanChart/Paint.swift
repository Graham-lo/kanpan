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
  ///
  /// `k`（影线兑淡量）是随捏合连续变的，所以键**不能**拿 `k` 原样去存——一场捏合
  /// 下来能攒出几千个只用过一次的键。这里不量化 `k`（量化会改掉整数通道上的
  /// 四舍五入，像素就不是原来那张了），改成把表按容量封顶：超过就整只倒掉重来。
  /// 调用方也别在逐根循环里叫它，把结果提到循环外（见 `drawCandles`）。
  private nonisolated(unsafe) static var mixCache: [MixKey: Hex] = [:]
  private static let mixLock = NSLock()
  private static let mixCacheLimit = 512

  private struct MixKey: Hashable {
    let a: String, b: String, k: Double
  }

  static func mix(_ a: Hex, _ b: Hex, _ k: Double) -> Hex {
    let key = MixKey(a: a.value, b: b.value, k: k)
    mixLock.lock()
    if let hit = mixCache[key] { mixLock.unlock(); return hit }
    mixLock.unlock()
    let value = KanpanCore.mixHex(a, b, k)
    mixLock.lock()
    if mixCache.count >= mixCacheLimit { mixCache.removeAll(keepingCapacity: true) }
    mixCache[key] = value
    mixLock.unlock()
    return value
  }
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
  static let axis = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
  static let legend = UIFont.systemFont(ofSize: 10, weight: .medium)
  /// 比价格胶囊小一号，给挂在它底下的倒计时用：两格叠在右轴上，字号一样会显得头重。
  /// 等宽数字是必须的——倒计时每秒都在变，比例数字会让整格左右抖。
  static let tiny = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)

  /// `(字体, 颜色)` → 属性字典。
  ///
  /// 从前每画一个标签都现建一个字典外加一只 `UIColor`；一帧光是右轴刻度、时间轴、
  /// 图例读数就是几十上百个标签，全是同样那几种 `(字体, 颜色)` 组合。
  /// 键用字体的对象身份（不是字号／字重——等宽数字字体和系统字体重名不同 feature，
  /// 按名字做键会把数字宽度算错）加颜色的十六进制串。
  private nonisolated(unsafe) static var attrsCache: [AttrsKey: [NSAttributedString.Key: Any]] = [:]
  private static let attrsLock = NSLock()

  private struct AttrsKey: Hashable {
    let font: ObjectIdentifier, color: String
  }

  static func attrs(_ font: UIFont, _ color: Hex) -> [NSAttributedString.Key: Any] {
    let key = AttrsKey(font: ObjectIdentifier(font), color: color.value)
    attrsLock.lock()
    if let hit = attrsCache[key] { attrsLock.unlock(); return hit }
    attrsLock.unlock()
    let value: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(cgColor: Paint.cg(color))]
    attrsLock.lock()
    attrsCache[key] = value
    attrsLock.unlock()
    return value
  }

  /// `(文字, 字体)` → 排版尺寸。
  ///
  /// 一个标签从前要排两遍版：`width()` 量一次决定胶囊多宽，`draw*` 里再
  /// `size(withAttributes:)` 一次才知道怎么对齐；图例每条读数更是量三次
  /// （换行判断、画、推进 x）。尺寸只跟 `(文字, 字体)` 有关——前景色不参与排版——
  /// 所以量出来的值可以跨调用点复用，量一次画一次。
  ///
  /// 表按条数封顶后整只倒掉：读数字符串随行情一直变，留着只会越攒越多。
  private nonisolated(unsafe) static var sizeCache: [SizeKey: CGSize] = [:]
  private static let sizeLock = NSLock()
  private static let sizeCacheLimit = 512

  private struct SizeKey: Hashable {
    let text: String, font: ObjectIdentifier
  }

  static func measure(_ text: String, _ font: UIFont) -> CGSize {
    let key = SizeKey(text: text, font: ObjectIdentifier(font))
    sizeLock.lock()
    if let hit = sizeCache[key] { sizeLock.unlock(); return hit }
    sizeLock.unlock()
    let value = (text as NSString).size(withAttributes: [.font: font])
    sizeLock.lock()
    if sizeCache.count >= sizeCacheLimit { sizeCache.removeAll(keepingCapacity: true) }
    sizeCache[key] = value
    sizeLock.unlock()
    return value
  }
}

extension String {
  func width(_ font: UIFont) -> CGFloat { ChartFont.measure(self, font).width }

  /// 以 (x, y) 为中心画。CoreText 的基线和原型 `textBaseline = 'middle'` 对齐靠这个。
  func drawCentered(at p: CGPoint, font: UIFont, color: Hex) {
    let s = ChartFont.measure(self, font)
    (self as NSString).draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2),
                            withAttributes: ChartFont.attrs(font, color))
  }

  /// 左对齐、纵向居中。
  func drawLeft(at p: CGPoint, font: UIFont, color: Hex) {
    let s = ChartFont.measure(self, font)
    (self as NSString).draw(at: CGPoint(x: p.x, y: p.y - s.height / 2),
                            withAttributes: ChartFont.attrs(font, color))
  }
}

extension String {
  /// 右对齐、以 (x, y) 为文字底边（原型 `textAlign='right'; textBaseline='bottom'`）。
  func drawRightBottom(at p: CGPoint, font: UIFont, color: Hex) {
    let s = ChartFont.measure(self, font)
    (self as NSString).draw(at: CGPoint(x: p.x - s.width, y: p.y - s.height),
                            withAttributes: ChartFont.attrs(font, color))
  }
}
