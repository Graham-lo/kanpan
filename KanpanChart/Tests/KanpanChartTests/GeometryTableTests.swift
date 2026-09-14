import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// A3.2：7 项几何 × 11 款风格 = 77 个数，与原型 ±1 设备像素。
///
/// 黄金值不是手抄的公式，是 `Tools/export-chart-fixtures.mjs` 把原型的 `Chart` 类
/// 原样跑起来问出来的（`layout()` / `barSpacing()` / `candleWidths` / `yOf`）。
/// 口径：BTCUSDT 1h 定版快照、iPhone 16 Pro 402×874 @3x、浅色、叠加 MA、副图 MACD + RSI，
/// 视野走 `resetView()`（右边缘留 6% 空白）。
@MainActor
@Suite("A3.2 几何量化")
struct GeometryTableTests {
  /// pt 差换成设备像素差；`padTop` 是比例，乘主图高再换。
  private static func deviceDelta(metric: String, appV: Double, protoV: Double,
                                  scale: Double, mainH: Double) -> Double {
    let d = abs(appV - protoV)
    return metric == "padTop" ? d * mainH * scale : d * scale
  }

  @Test("77 个数逐个对齐原型，误差 ≤ 1 设备像素")
  func table() {
    let g = Fixture.geometry
    let dev = Evidence.geometryDevice
    #expect(g.device == dev.name)
    #expect(g.width == dev.w && g.height == dev.h && g.scale == Double(dev.scale))
    #expect(g.metrics == ChartProbe.metricNames)

    var rows: [[String: Any]] = []
    var csv = ["style,metric,app,prototype,delta_pt,delta_device_px"]
    var worst = 0.0
    var checked = 0

    for style in CandleStyle.all {
      guard let golden = g.styles[style.id] else {
        Issue.record("原型黄金值里没有风格 \(style.id)")
        continue
      }
      let st = Evidence.state(style: style, dark: false, size: dev.size)
      let p = ChartRenderer(state: st).probe(size: dev.size, scale: dev.scale)

      // 视野得先对上，不然后面 7 个数比的就不是同一帧
      #expect(abs(p.viewFrom - golden.view.from) < 1e-6, "\(style.id) 视野左缘和原型不一致")
      #expect(abs(p.viewTo - golden.view.to) < 1e-6, "\(style.id) 视野右缘和原型不一致")
      #expect(p.visibleLo == golden.visible.lo && p.visibleHi == golden.visible.hi)
      #expect(abs(p.plotW - golden.plotW) < 1e-9)
      #expect(abs(p.mainH - golden.mainH) < 1e-9)
      #expect(p.thin == golden.thin)

      var row: [String: Any] = ["style": style.id, "name": style.name, "thin": p.thin]
      let app = p.metrics, proto = golden.metrics
      for m in ChartProbe.metricNames {
        let a = app[m]!, b = proto[m]!
        let dpx = Self.deviceDelta(
          metric: m, appV: a, protoV: b, scale: Double(dev.scale), mainH: p.mainH)
        worst = max(worst, dpx)
        checked += 1
        // 容差就是「±1 设备像素」，但 1/3 pt（3x）这种数除不尽，正好差 1 像素的点会算出
        // 1.0000000000000018 这样的值。放 1e-9 的浮点噪声，判据本身一点没松。
        #expect(dpx <= 1 + 1e-9, "\(style.id).\(m)：app \(a) vs 原型 \(b)，差 \(dpx) 设备像素")
        row[m] = ["app": a, "prototype": b, "deltaDevicePx": dpx]
        csv.append("\(style.id),\(m),\(a),\(b),\(abs(a - b)),\(dpx)")
      }
      row["reference"] = [
        "plotW": p.plotW, "mainH": p.mainH, "padBottom": p.padBottom,
        "minBody": p.minBody, "radius": p.radius, "outline": p.outline,
        "rangeLo": p.rangeLo, "rangeHi": p.rangeHi,
        "visibleLo": p.visibleLo, "visibleHi": p.visibleHi,
      ]
      rows.append(row)
    }

    #expect(checked == 77, "A3.2 要的是 7 × 11 = 77 个数，实际比了 \(checked) 个")

    Evidence.writeJSON(
      [
        "item": "A3.2",
        "note": "7 项几何 × 11 款风格 = 77 个数，app 实测 vs 原型 chart.js，容差 ±1 设备像素。",
        "device": dev.name, "width": dev.w, "height": dev.h, "scale": dev.scale,
        "theme": "light", "symbol": Fixture.snapshot.symbol, "interval": Fixture.snapshot.interval,
        "overlays": Evidence.overlays.map(\.rawValue), "subs": Evidence.subs.map(\.rawValue),
        "metrics": ChartProbe.metricNames,
        "worstDeltaDevicePx": worst,
        "styles": rows,
      ], "A3.2-geometry.json")
    Evidence.writeText(csv.joined(separator: "\n") + "\n", "A3.2-geometry.csv")
  }
}

/// A3.10：所有绘制 x 都落在设备像素边界上。
///
/// 「边界」有两种：填充矩形的左缘要压在整数设备像素上（`snap`），1 像素细线的中线要压在
/// 半像素上（`hairline`）。两者都由 `KanpanCore` 的同名函数保证，这里是在真实视野下
/// 把 `drawCandles` 会用到的每一个 x 都抓出来验一遍。
@MainActor
@Suite("A3.10 像素边界")
struct PixelBoundaryTests {
  private func isIntegral(_ v: Double) -> Bool { abs(v - v.rounded()) < 1e-9 }

  @Test("11 款风格 × 8 机型：实体与影线左缘 x·scale 为整数", arguments: CandleStyle.all)
  func candleEdges(style: CandleStyle) {
    var count = 0
    for dev in Evidence.devices {
      let st = Evidence.state(style: style, dark: false, size: dev.size)
      let r = ChartRenderer(state: st)
      let s = Double(dev.scale)
      let xs = r.candleXs(size: dev.size, scale: dev.scale)
      #expect(!xs.isEmpty, "\(dev.id)/\(style.id) 一根都没画")
      for c in xs {
        #expect(isIntegral(c.bodyLeft * s), "\(dev.id)/\(style.id) 第 \(c.index) 根实体左缘 \(c.bodyLeft)")
        #expect(isIntegral(c.wickLeft * s), "\(dev.id)/\(style.id) 第 \(c.index) 根影线左缘 \(c.wickLeft)")
        #expect(isIntegral(c.wickHair * s - 0.5), "\(dev.id)/\(style.id) 第 \(c.index) 根影线中线 \(c.wickHair)")
        count += 1
      }
    }
    #expect(count > 0)
  }

  @Test("竖向细线（价格轴分隔 + 时间网格）中线压在半像素上", arguments: CandleStyle.all)
  func verticalHairlines(style: CandleStyle) {
    for dev in Evidence.devices {
      let st = Evidence.state(style: style, dark: false, size: dev.size)
      let r = ChartRenderer(state: st)
      let s = Double(dev.scale)
      let xs = r.verticalHairlineXs(size: dev.size, scale: dev.scale)
      #expect(!xs.isEmpty)
      for x in xs {
        #expect(isIntegral(x * s - 0.5), "\(dev.id)/\(style.id) 竖线 \(x) 没落在像素中线上")
      }
    }
  }

  /// `snap` / `hairline` 本身的性质：任意倍率下都得落在格子上，且不跑偏超过半像素。
  @Test("snap / hairline 在 1×/2×/3× 下都对")
  func primitives() {
    for s in [1.0, 2.0, 3.0] {
      for raw in stride(from: -3.0, through: 60.0, by: 0.137) {
        let a = snap(raw, scale: s)
        #expect(isIntegral(a * s))
        #expect(abs(a - raw) <= 0.5 / s + 1e-9)
        let b = hairline(raw, scale: s)
        #expect(isIntegral(b * s - 0.5))
        #expect(abs(b - raw) <= 1.0 / s + 1e-9)
      }
    }
  }
}
