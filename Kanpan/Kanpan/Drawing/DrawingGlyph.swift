import KanpanCore
import SwiftUI

/// 每种画线一个记号（§2E5）。
///
/// 工具面板原来是一张纯文字的 `List`，名字排下来像一份目录：用户要读完
/// 「射线 / 延长线 / 水平射线」才能想起哪个是哪个。工具的名字是**形状**——把形状
/// 画出来，一眼就认得。工具全量对齐 TradingView 之后有 38 把，靠读名字更无从找起。
///
/// 不用 SF Symbols：斐波那契、回归通道、江恩箱、多空持仓框这些在系统符号里没有对应物，
/// 硬凑只会得到一堆意思不对的图标；而且系统符号的线宽和这里的手绘线对不齐，
/// 一屏格子里有一半粗一半细，比没有图标更难看。所以 38 个全部手绘，
/// 同一个线宽、同一个 24×24 的取景框，横平竖直都落在半像素上。
///
/// 颜色由外面的 `foregroundStyle` 决定，这里只管形状。
struct DrawKindGlyph: View {
  let kind: Drawing.Kind
  var size: Double = 24
  var lineWidth: Double = 1.4

  var body: some View {
    Canvas { ctx, box in
      let k = min(box.width, box.height) / 24
      let shade = GraphicsContext.Shading.foreground
      func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * k, y: y * k) }
      func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, dash: [CGFloat] = []) {
        var p = Path(); p.move(to: pt(x1, y1)); p.addLine(to: pt(x2, y2))
        ctx.stroke(p, with: shade, style: .init(lineWidth: lineWidth, lineCap: .round, dash: dash.map { $0 * k }))
      }
      func dot(_ x: Double, _ y: Double, _ r: Double = 1.8) {
        ctx.fill(Path(ellipseIn: CGRect(x: (x - r) * k, y: (y - r) * k, width: 2 * r * k, height: 2 * r * k)), with: shade)
      }
      func box4(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, fill: Double = 0) {
        let r = CGRect(x: min(x1, x2) * k, y: min(y1, y2) * k,
                       width: abs(x2 - x1) * k, height: abs(y2 - y1) * k)
        if fill > 0 {
          ctx.drawLayer { inner in inner.opacity = fill; inner.fill(Path(r), with: shade) }
        }
        ctx.stroke(Path(r), with: shade, style: .init(lineWidth: lineWidth))
      }
      /// 箭头：给「测量」「价格区间」「日期区间」用，指向 `(dx, dy)`。
      func arrow(_ x: Double, _ y: Double, dx: Double, dy: Double) {
        let len = max(hypot(dx, dy), 0.001), ux = dx / len, uy = dy / len
        let w = 2.4, back = 3.4
        var p = Path()
        p.move(to: pt(x, y))
        p.addLine(to: pt(x - ux * back - uy * w / 2, y - uy * back + ux * w / 2))
        p.addLine(to: pt(x - ux * back + uy * w / 2, y - uy * back - ux * w / 2))
        p.closeSubpath()
        ctx.fill(p, with: shade)
      }
      /// 一串点连成的折线；`closed` 时首尾也连上。形态类（XABCD、头肩、艾略特）都靠它。
      func poly(_ xy: [Double], closed: Bool = false, dots: Bool = false) {
        var p = Path()
        for i in stride(from: 0, to: xy.count - 1, by: 2) {
          let q = pt(xy[i], xy[i + 1])
          i == 0 ? p.move(to: q) : p.addLine(to: q)
        }
        if closed { p.closeSubpath() }
        ctx.stroke(p, with: shade, style: .init(lineWidth: lineWidth, lineJoin: .round))
        if dots { for i in stride(from: 0, to: xy.count - 1, by: 2) { dot(xy[i], xy[i + 1], 1.3) } }
      }
      /// 一段二次曲线，给「曲线」和「气泡标注」的尾巴用。
      func curve(_ x1: Double, _ y1: Double, _ cx: Double, _ cy: Double, _ x2: Double, _ y2: Double) {
        var p = Path(); p.move(to: pt(x1, y1)); p.addQuadCurve(to: pt(x2, y2), control: pt(cx, cy))
        ctx.stroke(p, with: shade, style: .init(lineWidth: lineWidth, lineCap: .round))
      }
      /// 一小行字：斐波那契、江恩那几把靠数字才认得出是哪一种刻度。
      func tag(_ text: String, _ x: Double, _ y: Double) {
        ctx.draw(Text(text).font(.system(size: 6 * k, weight: .semibold)), at: pt(x, y), anchor: .center)
      }

      switch kind {
      case .hline: line(3, 12, 21, 12)
      case .vline: line(12, 3, 12, 21)
      case .trend: line(3, 19, 21, 5); dot(3, 19); dot(21, 5)
      case .ray: line(4, 19, 21, 5); dot(4, 19)
      case .hray: line(5, 12, 21, 12); dot(5, 12)
      case .extended:
        line(2, 20, 22, 6, dash: [3, 2.5]); line(7, 16.5, 17, 9.5); dot(7, 16.5); dot(17, 9.5)
      case .rectangle: box4(4, 6, 20, 18, fill: 0.16)
      case .channel:
        line(3, 17, 21, 6); line(3, 21, 21, 10)
      case .regression:
        line(3, 17, 21, 7, dash: [3, 2.5]); line(3, 13, 21, 3); line(3, 21, 21, 11)
      case .fibonacci:
        for y in [4.0, 9.0, 14.0, 20.0] { line(3, y, 21, y) }
        dot(4.5, 20); dot(19.5, 4)
      case .fibExtension:
        line(3, 19, 8, 8); line(8, 8, 12, 15)
        for y in [4.0, 10.0, 18.0] { line(12, y, 21, y, dash: y == 10 ? [] : [3, 2.5]) }
      case .measure:
        // 一个框 + 中间一根指向的竖轴，和画布上量出来的那个框同形。
        box4(4, 5, 20, 19, fill: 0.16)
        line(12, 18, 12, 8); arrow(12, 6.4, dx: 0, dy: -1)
      case .position:
        box4(5, 5, 19, 12, fill: 0.22); box4(5, 12, 19, 19, fill: 0.1)
        line(3, 12, 21, 12)
      case .priceRange:
        line(3, 6, 21, 6); line(3, 18, 21, 18)
        line(12, 7.5, 12, 16.5); arrow(12, 5.6, dx: 0, dy: -1); arrow(12, 18.4, dx: 0, dy: 1)
      case .dateRange:
        line(6, 3, 6, 21); line(18, 3, 18, 21)
        line(7.5, 12, 16.5, 12); arrow(5.6, 12, dx: -1, dy: 0); arrow(18.4, 12, dx: 1, dy: 0)
      case .note:
        line(6, 6, 18, 6); line(12, 6, 12, 18)
        line(9.5, 18, 14.5, 18)

      // ---- 全量对齐 TV 之后补的那批（2026-09-18）。取景框、线宽跟上面完全一致。
      case .crossLine: line(3, 12, 21, 12); line(12, 3, 12, 21); dot(12, 12)
      case .arrowLine: line(3, 19, 18, 7); arrow(21, 4.6, dx: 3, dy: -2.4); dot(3, 19)
      case .pitchfork:
        // 一柄分叉：柄从左下伸向中线，三条平行的齿朝右。
        line(3, 19, 10, 12); dot(3, 19)
        line(10, 5, 10, 19); line(10, 5, 21, 5); line(10, 12, 21, 12); line(10, 19, 21, 19)
      case .fibChannel:
        line(3, 18, 21, 10); line(3, 13, 21, 5); line(3, 20.5, 21, 12.5, dash: [2.5, 2])
        tag("0.5", 15.5, 8.4)
      case .ellipse:
        ctx.stroke(Path(ellipseIn: CGRect(x: 3 * k, y: 6 * k, width: 18 * k, height: 12 * k)),
                   with: shade, style: .init(lineWidth: lineWidth))
      case .triangle: poly([12, 4, 21, 19, 3, 19], closed: true, dots: true)
      case .curve: curve(3, 18, 12, 1, 21, 15); dot(3, 18); dot(21, 15)
      case .datePriceRange:
        box4(4, 6, 20, 18)
        arrow(4.6, 12, dx: -1, dy: 0); arrow(19.4, 12, dx: 1, dy: 0)
        arrow(12, 6.6, dx: 0, dy: -1); arrow(12, 17.4, dx: 0, dy: 1)
      case .fibTimeZone:
        line(3, 4, 3, 20); line(6, 4, 6, 20); line(11, 4, 11, 20); line(19, 4, 19, 20)
        dot(3, 21.6, 1.1); dot(6, 21.6, 1.1)
      case .fibFan:
        line(4, 20, 21, 4); line(4, 20, 21, 10); line(4, 20, 21, 16); dot(4, 20)
      case .gannBox:
        box4(3, 5, 21, 19)
        line(12, 5, 12, 19); line(3, 12, 21, 12); line(3, 19, 21, 5)
      case .gannFan:
        line(3, 20, 21, 3); line(3, 20, 21, 11); line(3, 20, 21, 17); line(3, 20, 12, 3)
        dot(3, 20)
      case .xabcd:
        poly([3, 17, 8, 6, 13, 15, 17, 7, 21, 18], dots: true)
        line(3, 17, 13, 15); line(8, 6, 17, 7)
      case .abcd: poly([3, 18, 9, 7, 14, 14, 21, 4], dots: true)
      case .headShoulders:
        poly([3, 19, 6, 12, 9, 16, 12, 5, 15, 16, 18, 12, 21, 19], dots: true)
        line(3, 16.5, 21, 16.5, dash: [2.5, 2])
      case .elliottImpulse:
        poly([3, 20, 7, 12, 10, 16, 14, 7, 17, 11, 21, 4], dots: true)
        tag("5", 20.4, 1.6)
      case .elliottCorrection:
        poly([3, 6, 9, 16, 14, 9, 21, 19], dots: true)
        tag("C", 20.6, 21.6)
      case .callout:
        box4(4, 4, 20, 14, fill: 0.14)
        poly([9, 14, 7, 20, 13, 14])
      case .priceLabel:
        box4(7, 8, 21, 16, fill: 0.14)
        poly([7, 8, 3, 12, 7, 16], closed: true)
      case .flag:
        line(6, 3, 6, 21)
        poly([6, 4, 19, 8, 6, 12], closed: true)
      case .markerUp: poly([12, 4, 19, 17, 5, 17], closed: true); line(12, 17, 12, 21)
      case .markerDown: poly([12, 20, 19, 7, 5, 7], closed: true); line(12, 7, 12, 3)
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

extension Drawing.Kind {
  /// 某一分类下的全部工具，顺序就是 `Kind` 的声明顺序。
  static func all(in group: String) -> [Drawing.Kind] {
    allCases.filter { $0.group == group }
  }
}
