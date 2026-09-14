import Foundation
import Testing

@testable import KanpanCore

/// A1.7：切周期**保住像素宽**。14 × 14 组周期两两互切，根间距一模一样，右边缘不动。
@Suite("切周期")
struct PeriodSwitchTests {
  static let plotW = 390.0
  static let end: Int64 = 1_789_300_800_000
  static let spacings: [Double] = [0.4, 0.7, 1.3, 2.6, 4.8, 9.2, 15, 23.5, 32, 40]

  /// 所有周期都收在同一时刻，切过去右边缘才有可比性。
  static func series(_ iv: Interval, count: Int = 2200) -> BarSeries {
    let t0 = end - Int64(count - 1) * iv.stepMs
    return synthSeries(count: count, interval: iv, t0: t0, seed: UInt64(iv.stepMs % 9973))
  }

  @Test("14 × 14 组互切，根宽不变、右缘不动", arguments: Interval.allCases)
  func switchKeepsPixelWidth(_ from: Interval) {
    let a = Self.series(from)
    for to in Interval.allCases {
      let b = Self.series(to)
      for spacing in Self.spacings {
        // 先在旧周期上摆出这个根间距的视野。
        let span0 = (Self.plotW / spacing) * Double(a.step)
        let old = clampView(
          ViewWindow(to: Double(a.lastTime), span: span0), series: a, plotW: Self.plotW)
        let measured = old.barSpacing(step: a.step, plotW: Self.plotW)

        let v = ViewMath.switchInterval(
          to: b, plotW: Self.plotW, spacing: measured, anchorRight: old.to)
        let got = v.barSpacing(step: b.step, plotW: Self.plotW)
        #expect(abs(got - measured) < 1e-9,
                "\(from.rawValue)→\(to.rawValue) @\(spacing)：根宽 \(measured) → \(got)")
        #expect(abs(v.to - old.to) <= max(1e-6, abs(old.to) * 1e-12),
                "\(from.rawValue)→\(to.rawValue) @\(spacing)：右缘 \(old.to) → \(v.to)")
      }
    }
  }

  /// 往回拖过的视野切周期，右缘同样钉死。
  @Test("拖回历史后再切", arguments: Interval.allCases)
  func switchFromScrolledView(_ from: Interval) {
    _ = from
    for to in Interval.allCases {
      let b = Self.series(to)
      for spacing in Self.spacings {
        let span = (Self.plotW / spacing) * Double(b.step)
        let anchor = Double(Self.end) - 0.2 * span
        let v = ViewMath.switchInterval(to: b, plotW: Self.plotW, spacing: spacing, anchorRight: anchor)
        #expect(abs(v.barSpacing(step: b.step, plotW: Self.plotW) - spacing) < 1e-9,
                "\(from.rawValue)→\(to.rawValue) @\(spacing) 根宽变了")
        #expect(abs(v.to - anchor) <= max(1e-6, abs(anchor) * 1e-12),
                "\(from.rawValue)→\(to.rawValue) @\(spacing) 右缘动了")
      }
    }
  }

  /// 没有锚点（换品种式的切法）：右边留 6% 空白。
  @Test("无锚点时落回右缘留白", arguments: Interval.allCases)
  func noAnchorFallsBackToRightGap(_ iv: Interval) {
    let s = Self.series(iv)
    for spacing in Self.spacings {
      let v = ViewMath.switchInterval(to: s, plotW: Self.plotW, spacing: spacing, anchorRight: nil)
      #expect(abs(v.barSpacing(step: s.step, plotW: Self.plotW) - spacing) < 1e-9, "\(iv.rawValue) @\(spacing)")
      #expect(abs((v.to - Double(s.lastTime)) / v.span - Chart.rightGap) < 1e-9, "\(iv.rawValue) @\(spacing) 留白不对")
    }
  }

  /// 越界的根间距先夹到 [0.4, 40] 再算，不许炸出天价窗宽。
  @Test("根间距越界先夹")
  func spacingClamped() {
    let s = Self.series(.h1)
    for bad in [-5.0, 0, 0.01, 1e9, .infinity] {
      let v = ViewMath.switchInterval(to: s, plotW: Self.plotW, spacing: bad, anchorRight: nil)
      let got = v.barSpacing(step: s.step, plotW: Self.plotW)
      #expect(got >= Chart.minBarSpacing - 1e-9 && got <= Chart.maxBarSpacing + 1e-9, "spacing=\(bad) → \(got)")
    }
  }

  /// 连切十次再切回来，根宽还是原来那个——不许一路漂。
  @Test("来回切十次不漂")
  func roundTripNoDrift() {
    let order: [Interval] = [.h1, .m5, .d1, .m1, .h4, .w1, .m15, .mo1, .h12, .m30, .h1]
    var s = Self.series(.h1)
    var v = clampView(
      ViewWindow(to: Double(s.lastTime), span: (Self.plotW / 9.2) * Double(s.step)),
      series: s, plotW: Self.plotW)
    let want = v.barSpacing(step: s.step, plotW: Self.plotW)
    for iv in order.dropFirst() {
      let spacing = v.barSpacing(step: s.step, plotW: Self.plotW)
      let next = Self.series(iv)
      v = ViewMath.switchInterval(to: next, plotW: Self.plotW, spacing: spacing, anchorRight: v.to)
      s = next
    }
    #expect(abs(v.barSpacing(step: s.step, plotW: Self.plotW) - want) < 1e-9,
            "绕一圈回来 \(want) → \(v.barSpacing(step: s.step, plotW: Self.plotW))")
  }
}
