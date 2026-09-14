import Testing

@testable import KanpanCore

/// A1.3：根宽表必须和原型 `candleWidths` 完全相同，并满足奇偶、包含关系等不变量。
@Suite("根宽与像素对齐")
struct GeometryTests {
  @Test("candleWidths 与原型逐点相等", arguments: Fx.widths.indices)
  func candleWidths(_ ri: Int) {
    let row = Fx.widths[ri]
    var bad = 0
    var first = ""
    for i in row.body.indices {
      let s = row.spacing(i)
      let got = KanpanCore.candleWidths(spacing: s, scale: row.scale, bodyR: row.bodyR)
      if Double(got.body) != row.body[i] || Double(got.wick) != row.wick[i] {
        bad += 1
        if first.isEmpty {
          first = "spacing=\(s) want (\(row.body[i]), \(row.wick[i])) got (\(got.body), \(got.wick))"
        }
      }
    }
    #expect(bad == 0, "\(row.style)@\(Int(row.scale))x：\(bad) 点不符，首个 \(first)")
  }

  @Test("奇偶相同 / body ≥ wick / 细到极致时合二为一", arguments: Fx.widths.indices)
  func widthInvariants(_ ri: Int) {
    let row = Fx.widths[ri]
    for i in row.body.indices {
      let s = row.spacing(i)
      let w = KanpanCore.candleWidths(spacing: s, scale: row.scale, bodyR: row.bodyR)
      #expect(w.body % 2 == w.wick % 2, "spacing=\(s) 奇偶不同 \(w)")
      #expect(w.body >= w.wick, "spacing=\(s) 实体比影线还细 \(w)")
      #expect(w.wick >= 1, "spacing=\(s) 影线归零 \(w)")
      // 原型：raw = spacing · bodyR · dpr，不到 2 个设备像素就退成一根竖线。
      if s * row.bodyR * row.scale < 2 { #expect(w.body == w.wick, "spacing=\(s) 细蜡烛没退成一根线") }
    }
  }

  /// 根宽随根间距单调不减——放大不能把蜡烛画细了。
  @Test("根宽单调", arguments: Fx.widths.indices)
  func monotonic(_ ri: Int) {
    let row = Fx.widths[ri]
    var prev = -1
    for i in row.body.indices {
      let b = KanpanCore.candleWidths(spacing: row.spacing(i), scale: row.scale, bodyR: row.bodyR).body
      #expect(b >= prev, "spacing=\(row.spacing(i)) 变细了 \(prev)→\(b)")
      prev = b
    }
  }

  @Test("snap 落在设备像素边界", arguments: [1.0, 2.0, 3.0])
  func snapping(_ scale: Double) {
    var r = Rng(UInt64(scale * 100))
    for _ in 0..<2000 {
      let x = r.d(-500, 1500)
      let s = snap(x, scale: scale)
      #expect(abs(s * scale - (s * scale).rounded()) < 1e-9, "snap(\(x)) = \(s) 没对齐")
      #expect(abs(s - x) <= 0.5 / scale + 1e-9, "snap 挪太远")
      let h = hairline(x, scale: scale)
      #expect(abs((h * scale - 0.5) - (h * scale - 0.5).rounded()) < 1e-9, "hairline(\(x)) = \(h) 不在半像素上")
    }
  }

  /// 挤到 1.3 pt 以内只画影线；宽到 20 pt 一定是胖实体。
  @Test("thin 判定")
  func thinFlag() {
    for st in CandleStyle.all {
      #expect(candleMetrics(spacing: 1.0, style: st, scale: 2).thin, "\(st.id) 挤成这样还画实体")
      #expect(!candleMetrics(spacing: 20, style: st, scale: 2).thin, "\(st.id) 拉开了还不画实体")
    }
  }

  /// 影线粗细按 `max(0.5, style.wick) / scale`，和原型 drawCandles 开头一致。
  @Test("影线粗细换算")
  func wickWidth() {
    for st in CandleStyle.all {
      for scale in [1.0, 2.0, 3.0] {
        #expect(wickLineWidth(style: st, scale: scale) == max(0.5, st.wick) / scale, "\(st.id)@\(scale)")
        let m = candleMetrics(spacing: 8, style: st, scale: scale)
        let wickW = max(0.5, st.wick) / scale
        #expect(m.minBody == max(wickW, st.minBody / scale), "\(st.id)@\(scale) minBody")
        #expect(m.radius == min(st.radius, m.bodyW / 2), "\(st.id)@\(scale) radius")
        #expect(m.outline == max(1, (scale * 0.9).rounded()) / scale, "\(st.id)@\(scale) 描边线宽")
        #expect(m.bodyW > 0 && m.wickW > 0)
      }
    }
  }
}
