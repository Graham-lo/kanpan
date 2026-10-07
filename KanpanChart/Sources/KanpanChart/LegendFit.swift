import KanpanCore
import UIKit

/// 图例里的一段：全称（带参数）与短称（去参数、只留读数）。
///
/// 图例一律**单行**（2026-10-08）：主图叠加、对比、副图都不再折第二行——折行会把
/// 主图的 K 线顶下去一截、副图上压住线。一行放不下时先整行换短称，再放不下就把尾巴
/// 收成「+N」。十字线开着时读数换成那一根的，规则不变（每帧现量，字宽跟着读数走）。
struct LegendItem: Equatable {
  var full: String
  var short: String
  var color: Hex
  init(_ full: String, short: String? = nil, color: Hex) {
    self.full = full; self.short = short ?? full; self.color = color
  }
  /// 读不到数（换品种那一拍、指标比序列短一截）的段不进图例。
  var readable: Bool { !full.contains("NaN") && !full.contains("--") }
}

enum LegendFit {
  /// 段与段之间的空隙（和原来折行版一致）。
  static let gap = 8.0

  struct Line: Equatable {
    var texts: [(String, Hex)]
    /// 收进「+N」的段数；0 就是全放下了。
    var more: Int
    static func == (a: Line, b: Line) -> Bool {
      a.more == b.more && a.texts.map(\.0) == b.texts.map(\.0) && a.texts.map(\.1) == b.texts.map(\.1)
    }
  }

  static func moreText(_ n: Int) -> String { "+\(n)" }

  /// 在 `width` 宽里摆一行：全称放得下用全称，否则全用短称，再放不下就留最长的短称前缀 + 「+N」。
  static func fit(_ items: [LegendItem], width: Double, measure: (String) -> Double) -> Line {
    let items = items.filter(\.readable)
    func total(_ texts: [String]) -> Double {
      texts.reduce(0) { $0 + measure($1) } + gap * Double(max(0, texts.count - 1))
    }
    let full = items.map(\.full)
    if total(full) <= width { return Line(texts: items.map { ($0.full, $0.color) }, more: 0) }
    let short = items.map(\.short)
    if total(short) <= width { return Line(texts: items.map { ($0.short, $0.color) }, more: 0) }
    var x = 0.0, kept = 0
    for (k, text) in short.enumerated() {
      let w = measure(text) + (k > 0 ? gap : 0)
      let rest = items.count - k - 1
      let tail = rest > 0 ? gap + measure(moreText(rest)) : 0
      guard x + w + tail <= width else { break }
      x += w; kept = k + 1
    }
    return Line(texts: items.prefix(kept).map { ($0.short, $0.color) }, more: items.count - kept)
  }

  /// 摆好并画出来，返回画到哪儿（下一段的起点 x）。
  @discardableResult
  static func draw(_ items: [LegendItem], x: Double, y: Double, maxX: Double, more color: Hex) -> Double {
    let line = fit(items, width: maxX - x) { Double($0.width(ChartFont.axis)) }
    var x = x
    for (text, c) in line.texts {
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: c)
      x += Double(text.width(ChartFont.axis)) + gap
    }
    if line.more > 0 {
      let text = moreText(line.more)
      text.drawLeft(at: CGPoint(x: x, y: y), font: ChartFont.axis, color: color)
      x += Double(text.width(ChartFont.axis)) + gap
    }
    return x
  }
}
