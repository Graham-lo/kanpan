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
///
/// 7 项里 **`wickW` 是有意分歧**，不进 ±1 的比对（M8 起）：原型算的是 `(4.0 / 3) / dpr`，
/// 同一个 1.8 在 2x 上 0.9pt、3x 上只剩 0.6pt，屏幕越精细影线越细。风格表是照 2x 屏调的，
/// 所以我们把它当 2x 口径换算成固定物理宽度再量到整数设备像素。分歧值逐条记进
/// `A3.2-geometry.json` 的 `knownDivergences`，最大的一条是墩：1.0pt vs 0.6pt。
@MainActor
@Suite("A3.2 几何量化")
struct GeometryTableTests {
  /// pt 差换成设备像素差；`padTop` 是比例，乘主图高再换。
  @Test("AICoin 底座：时间轴高 17、实体与影线都有宽度")
  func table() {
    let dev = Evidence.geometryDevice
    let actual = ChartRenderer(state: Evidence.state(dark: false, size: dev.size))
      .probe(size: dev.size, scale: dev.scale)
    #expect(actual.bodyW > 0 && actual.wickW > 0)
    #expect(actual.timeH == 17)
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

  @Test("8 机型：实体与影线左缘 x·scale 为整数")
  func candleEdges() {
    var count = 0
    for dev in Evidence.devices {
      let st = Evidence.state(dark: false, size: dev.size)
      let r = ChartRenderer(state: st)
      let s = Double(dev.scale)
      let xs = r.candleXs(size: dev.size, scale: dev.scale)
      #expect(!xs.isEmpty, "\(dev.id)/aicoin 一根都没画")
      for c in xs {
        #expect(isIntegral(c.bodyLeft * s), "\(dev.id)/aicoin 第 \(c.index) 根实体左缘 \(c.bodyLeft)")
        #expect(isIntegral(c.wickLeft * s), "\(dev.id)/aicoin 第 \(c.index) 根影线左缘 \(c.wickLeft)")
        #expect(isIntegral(c.wickHair * s - 0.5), "\(dev.id)/aicoin 第 \(c.index) 根影线中线 \(c.wickHair)")
        count += 1
      }
    }
    #expect(count > 0)
  }

  @Test("竖向细线（价格轴分隔 + 时间网格）中线压在半像素上")
  func verticalHairlines() {
    for dev in Evidence.devices {
      let st = Evidence.state(dark: false, size: dev.size)
      let r = ChartRenderer(state: st)
      let s = Double(dev.scale)
      let xs = r.verticalHairlineXs(size: dev.size, scale: dev.scale)
      #expect(!xs.isEmpty)
      for x in xs {
        #expect(isIntegral(x * s - 0.5), "\(dev.id)/aicoin 竖线 \(x) 没落在像素中线上")
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
