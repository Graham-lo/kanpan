import CoreGraphics
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// A3.3：AICoin 这一套风格浅深各取 7 个点，像素颜色与 §6 计算值比对。
///
/// 取样点不是猜的：先用 `ChartRenderer.candleXs` / `priceGridYs` / `lastPriceY` 把
/// 那一笔画在哪儿问出来，再直接读那个设备像素——这就是「无抗锯齿处取样」。
///
/// 风格表原来有十一款（见 `CandleStyle`），这条用例也就横着跑十一遍；收成 AICoin 一套
/// 之后只剩一遍。守的东西一点没变——像素必须等于 `state.colors` 算出来的那个值。
///
/// 影线以前有一类点几何上取不到满覆盖：宽度写的是 `max(0.5, (4.0 / 3))` 个设备像素，
/// 有几款只有 0.5 / 0.8 / 0.9，一个整像素都盖不满，期望值只能按
/// `blend(底色, 影线色, 覆盖率)` 算。**M6 之后不再有这一档**：影线一律量化成整数个
/// 设备像素（`wickPixels`），所以这 7 个点全都是满覆盖精确比。这次改的就是实机反馈
/// 「影线颜色发淡、糊在一起」的根因——那条 50% 灰不是错觉，是真的只画了半个像素。
///
/// 轴文字仍然记覆盖率：字形笔画本身就带抗锯齿，那是字体渲染的事，不是我们的。
@MainActor
@Suite("A3.3 颜色取样")
struct ColorSampleTests {
  private static let dev = Evidence.geometryDevice

  /// 一个取样点的结果。
  private struct Sample {
    var point: String
    var expected: String
    var actual: String
    var delta: Int
    var coverage: Double
    var exact: Bool          // 几何上能不能取到满覆盖
    var at: [Int]            // 设备像素坐标
    var note: String = ""

    var dict: [String: Any] {
      ["point": point, "expected": expected, "actual": actual, "delta": delta,
       "coverage": coverage, "exactExpected": exact, "at": at, "note": note]
    }
  }

  private func hexOf(_ c: (r: Int, g: Int, b: Int)) -> String {
    String(format: "#%02X%02X%02X", c.r, c.g, c.b)
  }

  @Test("7 个点 × AICoin 一套 × 明暗两套")
  func sample() {
    let dev = Self.dev
    let s = Double(dev.scale)
    let W = Int(dev.w * s), H = Int(dev.h * s)
    var out: [[String: Any]] = []
    var csv = ["theme,style,point,expected,actual,delta,coverage,exactExpected"]
    var checked = 0

    for dark in [false, true] {
      let themeKey = dark ? "dark" : "light"
      guard let goldenAll = Fixture.colors.themes[themeKey] else {
        Issue.record("原型色值里没有主题 \(themeKey)")
        continue
      }
      for style in CandleStyle.all {
        guard let golden = goldenAll[style.id] else {
          Issue.record("原型色值里没有风格 \(style.id)")
          continue
        }
        var st = Evidence.state(style: style, dark: dark, size: dev.size)
        st.options.grid = .style
        let r = ChartRenderer(state: st)
        let p = r.probe(size: dev.size, scale: dev.scale)
        let xs = r.candleXs(size: dev.size, scale: dev.scale)
        let img = Evidence.render(st, size: dev.size, scale: dev.scale)
        let px = Pixels(img)
        let t = st.colors
        #expect(px.w == W && px.h == H)

        // Swift 侧算出来的色值必须先和原型对上，再谈像素
        #expect(t.up.value.uppercased() == golden.upBody.uppercased(), "\(themeKey)/\(style.id) 涨色")
        #expect(t.down.value.uppercased() == golden.downBody.uppercased(), "\(themeKey)/\(style.id) 跌色")
        #expect(t.bg.value.uppercased() == golden.bg.uppercased(), "\(themeKey)/\(style.id) 底色")
        #expect(t.grid.value.uppercased() == golden.grid.uppercased(), "\(themeKey)/\(style.id) 网格色")
        #expect(t.dim.value.uppercased() == golden.axisText.uppercased(), "\(themeKey)/\(style.id) 轴文字色")

        let bg = t.bg.rgb8
        var rows: [Sample] = []

        // 位图没翻：时间轴那条横线必须真在 timeY 上
        let axisRow = Int((hairline(p.mainH, scale: s) * s - 0.5).rounded())
        #expect(
          chanDelta(px.rgb(2, axisRow), t.axis.rgb8) == 0,
          "\(themeKey)/\(style.id) 时间轴线不在 timeY，位图可能翻了")

        // ---------------------------------------------------------------- ① 涨实体 ② 跌实体
        for (name, want) in [("upBody", true), ("downBody", false)] {
          let col = want ? t.up : t.down
          guard let c = xs.filter({ $0.up == want && $0.bodyHeight * s >= 6 })
            .max(by: { $0.bodyHeight < $1.bodyHeight })
          else {
            Issue.record("\(themeKey)/\(style.id) 找不到能取样的\(want ? "涨" : "跌")实体")
            continue
          }
          #expect(!(c.hollow && p.radius > 0), "描边 + 圆角的取样点没实现（AICoin 这套没有这种）")
          let yIdx = Int(((c.bodyTop + c.bodyHeight / 2) * s).rounded(.down))
          // 描边实体中间是底色，取左边那道 lw 宽的边；实心取实体正中。
          let xIdx = c.hollow
            ? Int((c.bodyLeft * s).rounded())
            : Int((c.bodyLeft * s).rounded() + (p.bodyW * s / 2).rounded(.down))
          let got = px.rgb(xIdx, yIdx)
          let d = chanDelta(got, col.rgb8)
          #expect(d == 0, "\(themeKey)/\(style.id).\(name) 期望 \(col.value) 实得 \(hexOf(got))")
          rows.append(
            Sample(
              point: name, expected: col.value.uppercased(), actual: hexOf(got), delta: d,
              coverage: 1, exact: true, at: [xIdx, yIdx],
              note: c.hollow ? "描边实体，取左边框内侧" : "实心实体中心"))
        }

        // ---------------------------------------------------------------- ③ 影线（tint 后）
        do {
          // 实体越细，渲染器越少兑淡影线：8 个设备像素以上照风格兑，8→2 之间线性收回
          // 满饱和，2 以下完全不兑（见 `drawCandles`，AiCoin 实测是根本不兑）。默认根间距
          // 下实体在 8 像素以上，`tintK` 就是风格表原值（AICoin 的 wickTint 是 1，压根不兑）；
          // 但取样点必须和渲染器同一套公式，不能各算各的。
          let tintFade = min(1, max(0, (p.bodyW * Double(dev.scale) - 2) / 6))
          let tintK = style.wickTint + (1 - style.wickTint) * (1 - tintFade)
          let col = tintK < 1 ? Paint.mix(t.bg, t.up, tintK) : t.up
          // M6 起影线一律是**整数个设备像素**（`wickPixels`），所以取样点必然满覆盖，
          // 不再有「0.5 像素 → 50% 灰」那一档。这正是实机上「影线发淡、糊成一片」的根因。
          let wickPx = Double(wickPixels(scale: Double(dev.scale)))
          let full = true
          let expected = col.rgb8
          // 上影线够长的那根：实体顶到最高价之间是纯影线
          guard let c = xs.filter({ $0.up && ($0.bodyTop - $0.wickTop) * s >= 8 })
            .max(by: { ($0.bodyTop - $0.wickTop) < ($1.bodyTop - $1.wickTop) })
          else {
            Issue.record("\(themeKey)/\(style.id) 找不到够长的上影线")
            continue
          }
          // 圆头帽在细影线上只贡献抗锯齿，渲染器已经改成「≥3 设备像素才用圆头描边」，
          // 其余一律填矩形。取样点跟着走：描边取中心线，填矩形取左沿那一列。
          let roundCap = style.wickCap == .round && wickPx >= 3
          let xIdx = (roundCap && !p.thin)
            ? Int((c.wickHair * s - 0.5).rounded())
            : Int((c.wickLeft * s).rounded())
          let gap = c.bodyTop - c.wickTop
          var best = (d: Int.max, y: 0, got: (r: 0, g: 0, b: 0))
          for k in [0.35, 0.45, 0.5, 0.55, 0.65] {
            let yIdx = Int(((c.wickTop + gap * k) * s).rounded(.down))
            let got = px.rgb(xIdx, yIdx)
            let d = chanDelta(got, expected)
            if d < best.d { best = (d, yIdx, got) }
          }
          #expect(
            best.d <= (full ? 0 : 1),
            "\(themeKey)/\(style.id).wick 期望 \(hexOf(expected)) 实得 \(hexOf(best.got))")
          rows.append(
            Sample(
              point: "wick", expected: hexOf(expected), actual: hexOf(best.got), delta: best.d,
              coverage: coverage(of: best.got, bg: bg, fg: col.rgb8), exact: full,
              at: [xIdx, best.y],
              note: "影线 \(Int(wickPx)) 设备像素（风格表 \((4.0 / 3)) 量化后），满覆盖"))
        }

        // ---------------------------------------------------------------- ④ 网格
        do {
          let ys = r.priceGridYs(size: dev.size)
          let lastY = r.lastPriceY(size: dev.size)?.y ?? -1
          // 网格取样躲开最新价线；x 取右边缘留白里，那儿没有 K 线，tick 模式也够得着
          let xIdx = Int(((p.plotW - 6) * s).rounded())
          if r.state.effectiveGrid == .none {
            var anyGrid = false
            for y in ys {
              let row = Int((hairline(y, scale: s) * s - 0.5).rounded())
              if chanDelta(px.rgb(xIdx, row), t.grid.rgb8) == 0 { anyGrid = true }
            }
            #expect(!anyGrid, "\(themeKey)/\(style.id) 是 grid: none，不该画出网格")
            let row = ys.isEmpty ? H / 4 : Int((hairline(ys[0], scale: s) * s - 0.5).rounded())
            let got = px.rgb(xIdx, row)
            rows.append(
              Sample(
                point: "grid", expected: hexOf(bg), actual: hexOf(got),
                delta: chanDelta(got, bg), coverage: 0, exact: true, at: [xIdx, row],
                note: "grid: none，该位置应为底色"))
          } else {
            guard let y = ys.max(by: { abs($0 - lastY) < abs($1 - lastY) }) else {
              Issue.record("\(themeKey)/\(style.id) 一条网格线都没有")
              continue
            }
            let row = Int((hairline(y, scale: s) * s - 0.5).rounded())
            let got = px.rgb(xIdx, row)
            let d = chanDelta(got, t.grid.rgb8)
            #expect(d == 0, "\(themeKey)/\(style.id).grid 期望 \(t.grid.value) 实得 \(hexOf(got))")
            rows.append(
              Sample(
                point: "grid", expected: t.grid.value.uppercased(), actual: hexOf(got), delta: d,
                coverage: 1, exact: true, at: [xIdx, row],
                note: "grid: \(r.state.effectiveGrid.rawValue)，1 设备像素细线"))
          }
        }

        // ---------------------------------------------------------------- ⑤ 底色
        do {
          let xIdx = W - 1, yIdx = H - 1
          let got = px.rgb(xIdx, yIdx)
          let d = chanDelta(got, bg)
          #expect(d == 0, "\(themeKey)/\(style.id).bg 期望 \(t.bg.value) 实得 \(hexOf(got))")
          rows.append(
            Sample(
              point: "bg", expected: t.bg.value.uppercased(), actual: hexOf(got), delta: d,
              coverage: 0, exact: true, at: [xIdx, yIdx], note: "右下角，时间轴外侧"))
        }

        // ---------------------------------------------------------------- ⑥ 最新价线
        do {
          guard let last = r.lastPriceY(size: dev.size) else {
            Issue.record("\(themeKey)/\(style.id) 最新价线不在主图里")
            continue
          }
          #expect(last.up == Fixture.colors.lastBarUp, "末根涨跌和原型不一致")
          let col = last.up ? t.up : t.down
          #expect(col.value.uppercased() == golden.lastLine.uppercased())
          let row = Int((hairline(last.y, scale: s) * s - 0.5).rounded())
          var hit = 0, firstX = -1
          for x in 0..<Int((p.plotW * s).rounded()) where chanDelta(px.rgb(x, row), col.rgb8) == 0 {
            hit += 1
            if firstX < 0 { firstX = x }
          }
          #expect(hit > 0, "\(themeKey)/\(style.id).lastLine 这一行一个 \(col.value) 都没有")
          let got = firstX >= 0 ? px.rgb(firstX, row) : px.rgb(0, row)
          rows.append(
            Sample(
              point: "lastLine", expected: col.value.uppercased(), actual: hexOf(got),
              delta: chanDelta(got, col.rgb8), coverage: 1, exact: true,
              at: [max(0, firstX), row],
              note: "\(true ? "虚线" : "实线")，该行命中 \(hit) 个像素"))
        }

        // ---------------------------------------------------------------- ⑦ 轴文字
        do {
          let ink = t.dim.rgb8
          let x0 = Int(((p.plotW + 5) * s).rounded()), x1 = min(W, Int((dev.w - 2) * s))
          // 最新价那枚胶囊也压在价格轴上。它是**实心的涨跌色**，比 60% 不透明度的轴文字
          // 离底色更远：`coverage` 只看差最大的那个通道，深色下那支 #E36159 算出来是 0.64
          // 的假覆盖率，正好压过真正的字像素（约 0.6），`best` 就被它抢走，
          // 于是断言拿胶囊的红去和「底色→轴文字」那条线比，差 144。
          // 胶囊画在 `drawLastPrice` 里、高 15pt、中心 y 被夹在主图上下各 8pt 之内，
          // 这里照同样的规则把它那一条横带排掉再扫。
          let tagY = r.lastPriceY(size: dev.size).map { max(8, min(p.mainH - 8, $0.y)) }
          let skip = tagY.map { Int(($0 - 9) * s) ... Int(($0 + 9) * s) }
          var best = (d: Int.max, cov: 0.0, x: 0, y: 0, got: (r: 0, g: 0, b: 0))
          for y in r.priceGridYs(size: dev.size) {
            let y0 = max(0, Int((y - 6) * s)), y1 = min(H, Int((y + 6) * s))
            for yy in y0..<y1 where skip?.contains(yy) != true {
              for xx in x0..<x1 {
                let got = px.rgb(xx, yy)
                let cov = coverage(of: got, bg: bg, fg: ink)
                let d = chanDelta(got, blend8(bg: bg, fg: ink, k: min(1, max(0, cov))))
                // 先挑覆盖率最高的，同覆盖率再挑贴线最紧的
                if cov > best.cov + 1e-9 || (abs(cov - best.cov) < 1e-9 && d < best.d) {
                  best = (d, cov, xx, yy, got)
                }
              }
            }
          }
          #expect(best.cov >= 0.5, "\(themeKey)/\(style.id).axisText 最深的字像素才 \(best.cov) 覆盖")
          #expect(best.d <= 1, "\(themeKey)/\(style.id).axisText 没落在底色→\(t.dim.value) 这条线上")
          let exact = best.cov >= 0.999 && chanDelta(best.got, ink) == 0
          rows.append(
            Sample(
              point: "axisText", expected: t.dim.value.uppercased(), actual: hexOf(best.got),
              delta: chanDelta(best.got, ink), coverage: best.cov, exact: exact,
              at: [best.x, best.y],
              note: exact ? "字形笔画有满覆盖像素" : "字形抗锯齿，取覆盖率最高的像素"))
        }

        #expect(rows.count == 7, "\(themeKey)/\(style.id) 只取到 \(rows.count) 个点")
        checked += rows.count
        for r0 in rows {
          csv.append(
            "\(themeKey),\(style.id),\(r0.point),\(r0.expected),\(r0.actual),\(r0.delta),"
              + String(format: "%.4f", r0.coverage) + ",\(r0.exact)")
        }
        out.append([
          "theme": themeKey, "style": style.id, "name": style.name,
          "gridMode": r.state.effectiveGrid.rawValue, "shape": style.shape.rawValue,
          "wickDevicePx": max(0.5, (4.0 / 3)),
          "samples": rows.map(\.dict),
        ])
      }
    }

    #expect(checked == 14, "A3.3 要的是 7 × 1 × 2 = 14 个取样点，实际取了 \(checked) 个")

    Evidence.writeJSON(
      [
        "item": "A3.3",
        "note": "7 个取色点 × AICoin 一套 × 明暗两套 = 14 个取样点。exactExpected=false 的点"
          + "（细影线、轴文字）几何上取不到满覆盖，期望值按 CoreGraphics 合成规则算。",
        "device": Self.dev.name, "width": Self.dev.w, "height": Self.dev.h, "scale": Self.dev.scale,
        "symbol": Fixture.snapshot.symbol, "interval": Fixture.snapshot.interval,
        "points": Fixture.colors.points,
        "rows": out,
      ], "A3.3-colors.json")
    Evidence.writeText(csv.joined(separator: "\n") + "\n", "A3.3-colors.csv")
  }
}

