import KanpanCore
import UIKit

// P2.12：读屏（VoiceOver）念的是十字线那一根的时间、开高低收和涨跌。
//
// 图是一整块自绘画布，读屏看不见里面的蜡烛；所以把「这一根是什么样」直接做成
// `accessibilityValue`，并把画布标成可调节元素——上下轻扫 = 十字线前后挪一根，
// 念出来的值跟着变。没有十字线时念最新那一根，第一次轻扫从最新那根起步。
extension ChartView {
  /// 读屏念的那一句。十字线在哪根就念哪根，没有十字线念最新一根。
  var voiceOverValue: String? {
    guard let s = state, s.series.count > 0 else { return nil }
    let i = s.crosshair.map { min(max($0.index, 0), s.series.count - 1) } ?? (s.series.count - 1)
    let b = s.series
    let d = s.decimals
    let prev = i > 0 ? b.close[i - 1] : b.open[i]
    let change: String
    if prev.isFinite, prev != 0, b.close[i].isFinite {
      let pct = (b.close[i] / prev - 1) * 100
      let text = toFixed(abs(pct), 2) + "%"
      change = text == "0.00%" ? "持平" : (pct > 0 ? "涨 " : "跌 ") + text
    } else {
      change = "涨跌未知"
    }
    let bar = [
      fmtFull(ms: Double(b.time(at: i)), offsetMinutes: s.timezone.offsetMinutes),
      "开 " + fmtNum(b.open[i], d), "高 " + fmtNum(b.high[i], d),
      "低 " + fmtNum(b.low[i], d), "收 " + fmtNum(b.close[i], d), change,
    ].joined(separator: "，")
    guard s.crosshair == nil else { return bar }
    return "\(InstrumentID(s.symbol.symbol).symbol)，\(b.interval.display)，最新一根 " + bar
  }

  public override func accessibilityIncrement() { stepCrosshairForVoiceOver(1) }
  public override func accessibilityDecrement() { stepCrosshairForVoiceOver(-1) }

  /// 读屏的上下轻扫：没有十字线就先落在最新那根上，有了就前后挪一根。
  private func stepCrosshairForVoiceOver(_ step: Int) {
    guard var s = state, s.series.count > 0 else { return }
    guard s.crosshair != nil else {
      let last = s.series.count - 1
      s.crosshair = Crosshair(index: last, price: s.series.close[last])
      state = s
      return
    }
    moveCrosshair(by: step)
  }
}
