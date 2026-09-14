import SwiftUI
import KanpanCore

/// 风格卡片上的那张小图（A6.2）。
///
/// **拿同一串价格，按这一版的形态、体积、影线、间距真画一遍**——不是贴图，也不是近似。
/// 逐行对应原型 `app.js` 的 `styleThumb`：同样的十二根、同样的 `step / cnt / pad / yOf`、
/// 同样的空心判定与最新价虚实。配色不属于风格，所以小图和主图用的是同一套靛，
/// 涨跌两色也跟着 `redUp` 一起对调。
///
/// 这里没走 `KanpanChart`：那个包现在没链进 app target。等它链进来，
/// `bars` 这段几何可以整体换成 `KanpanChart` 的同一份算法，外面的 API 不用动。
struct StyleThumbnail: View {
  var style: CandleStyle
  var colors: ChartColors

  /// 原型 `THUMB`：[开, 高, 低, 收] × 12，一个数都没改。
  static let bars: [[Double]] = [
    [52, 56, 49, 55], [55, 60, 54, 59], [59, 61, 53, 54], [54, 58, 50, 51],
    [51, 53, 44, 46], [46, 50, 45, 49], [49, 57, 48, 56], [56, 62, 55, 61],
    [61, 63, 58, 59], [59, 60, 52, 53], [53, 57, 52, 56], [56, 64, 55, 63],
  ]

  static let height: CGFloat = 56

  var body: some View {
    Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
      Self.draw(style: style, colors: colors, in: &ctx, size: size)
    }
    .frame(height: Self.height)
    .background(Color(hex: colors.bg))
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
      .stroke(Color(hex: colors.hair), lineWidth: 1))
    .accessibilityHidden(true)
  }

  // MARK: - 画

  static func draw(style: CandleStyle, colors: ChartColors,
                   in ctx: inout GraphicsContext, size: CGSize) {
    let W = size.width, H = size.height
    let bg = Color(hex: colors.bg)
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))

    // 网格：横线 / 横竖 / 右端刻度 / 不画——也是风格的一部分。
    if style.grid != .none {
      let grid = Color(hex: colors.grid)
      for i in 1...3 {
        let y = (H * CGFloat(i) / 4).rounded() + 0.5
        let x0: CGFloat = style.grid == .tick ? W - 14 : 0
        ctx.stroke(Path { $0.move(to: CGPoint(x: x0, y: y)); $0.addLine(to: CGPoint(x: W, y: y)) },
                   with: .color(grid), lineWidth: 1)
      }
      if style.grid == .both {
        for i in 1...3 {
          let x = (W * CGFloat(i) / 4).rounded() + 0.5
          ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: H)) },
                     with: .color(grid), lineWidth: 1)
        }
      }
    }

    // 上下留白和左右间距都照这一版：间距小的自然塞进更多根。
    let step = max(3, min(W / 6, AICoinBehavior.initialSpacing * 2.2))
    let count = max(4, Int((W - 6) / step))
    func bar(_ i: Int) -> [Double] { bars[i % bars.count] }

    var lo = Double.infinity, hi = -Double.infinity
    for i in 0..<count {
      let b = bar(i)
      lo = min(lo, b[2]); hi = max(hi, b[1])
    }
    let padv = (hi - lo) * 0.1
    lo -= padv; hi += padv
    let span = max(hi - lo, .leastNonzeroMagnitude)
    func yOf(_ v: Double) -> CGFloat { H - 4 - CGFloat((v - lo) / span) * (H - 8) }

    let bodyW = max(1.2, step * 2 / 3)
    let wickW = 2.0 / 3
    let left = (W - CGFloat(count) * step) / 2 + step / 2
    let cap: CGLineCap = style.wickCap == .round ? .round : .butt

    for i in 0..<count {
      let b = bar(i)
      let (o, h, l, c) = (b[0], b[1], b[2], b[3])
      let rising = c >= o
      let hex = rising ? colors.up : colors.down
      let col = Color(hex: hex)
      let x = left + CGFloat(i) * step

      // 影线。`wickTint < 1` 的版本把它往底色里兑淡。
      let wickHex = style.wickTint < 1 ? mixHex(colors.bg, hex, style.wickTint) : hex
      ctx.stroke(Path { $0.move(to: CGPoint(x: x, y: yOf(h))); $0.addLine(to: CGPoint(x: x, y: yOf(l))) },
                 with: .color(Color(hex: wickHex)),
                 style: StrokeStyle(lineWidth: wickW, lineCap: cap))

      // 实体。十字星也要留 `minBody` 那么一条，不然整根消失。
      let top = min(yOf(o), yOf(c))
      let bh = max(0.5, abs(yOf(c) - yOf(o)))
      let rect = CGRect(x: x - bodyW / 2, y: top, width: bodyW, height: bh)
      let r = min(style.radius, bodyW / 2, bh / 2)
      let body = r > 0
        ? Path(roundedRect: rect, cornerRadius: r, style: .continuous)
        : Path(rect)

      let hollow = style.shape == .outline || (style.shape == .hollowUp && rising)
      if hollow, bodyW > 2.4 {
        ctx.fill(body, with: .color(bg))
        ctx.stroke(body, with: .color(col), lineWidth: 1)
      } else {
        ctx.fill(body, with: .color(col))
      }
    }

    // 最新价线：虚实也是方案的一部分。
    let y = (yOf(bar(count - 1)[3])).rounded() + 0.5
    ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: W, y: y)) },
               with: .color(Color(hex: colors.amber)),
               style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
  }
}

#Preview("十一款缩略图") {
  ScrollView {
    VStack(spacing: 8) {
      ForEach(CandleStyle.all) { st in
        VStack(alignment: .leading, spacing: 4) {
          Text("\(st.name) · \(st.visualSummary)").font(PanelFont.cardOne)
          StyleThumbnail(style: st, colors: Palette.chart(dark: false))
        }
      }
    }
    .padding()
  }
}
