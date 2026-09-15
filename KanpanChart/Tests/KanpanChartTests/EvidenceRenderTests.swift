import CoreGraphics
import CryptoKit
import Foundation
import KanpanCore
import Testing
import UIKit

@testable import KanpanChart

/// M3 的取证渲染器（A3.1 / A3.4–A3.9）。
///
/// 跑法：`make evidence`。它给 `xcodebuild test` 传
/// `TEST_RUNNER_KANPAN_EVIDENCE_DIR=<仓库>/docs/acceptance/M3`，模拟器里的测试进程
/// 拿到这个环境变量才落盘。不带它（也就是 `make chart-test`）这几条测试直接跳过，
/// 日常跑测试不会在仓库里拉出两百张 png。
///
/// 数据一律来自 `Fixture`（定版快照），时区固定 UTC，视野走 `resetView()`——
/// 同一份代码在任何机器上跑出来的必须是同一批字节，A3.11 的基线才立得住。
@MainActor
@Suite("M3 取证渲染", .serialized)
struct EvidenceRenderTests {
  private static func sha256(_ d: Data) -> String {
    SHA256.hash(data: d).map { String(format: "%02x", $0) }.joined()
  }

  /// 落盘并登记。
  private func emit(_ img: CGImage, _ name: String, _ info: [String: Any],
                    into list: inout [[String: Any]]) {
    let data = UIImage(cgImage: img).pngData()!
    Evidence.writePNG(img, name)
    var row = info
    row["file"] = name
    row["px"] = [img.width, img.height]
    row["bytes"] = data.count
    row["sha256"] = Self.sha256(data)
    // 像素指纹：A3.11 回归比的是这个，不是 png 文件。png 编码器换个版本字节就变了，
    // 但「diff > 0 像素即失败」说的是像素本身。
    row["pixelSha256"] = Self.pixelSHA(img)
    list.append(row)
  }

  /// 位图本体（sRGB / 每通道 8 位）的 sha256。
  static func pixelSHA(_ img: CGImage) -> String {
    sha256(Data(Pixels(img).buf))
  }

  // ---------------------------------------------------------------- A3.1

  @Test("A3.1：8 机型 × 浅深 × 风格表 = 每款一张基线")
  func baselines() {
    guard Evidence.outputDir != nil else { return }
    var list: [[String: Any]] = []
    for dev in Evidence.devices {
      for dark in [false, true] {
        for (k, style) in CandleStyle.all.enumerated() {
          let st = Evidence.state(style: style, dark: dark, size: dev.size)
          let img = Evidence.render(st, size: dev.size, scale: dev.scale)
          let p = ChartRenderer(state: st).probe(size: dev.size, scale: dev.scale)
          emit(
            img, Evidence.name(dev.id, dark, style.id, k + 1),
            [
              "item": "A3.1", "device": dev.id, "deviceName": dev.name,
              "pt": [dev.w, dev.h], "scale": dev.scale,
              "theme": dark ? "dark" : "light", "style": style.id, "styleName": style.name,
              "spacing": p.spacing, "bars": p.visibleHi - p.visibleLo + 1, "thin": p.thin,
            ], into: &list)
        }
      }
    }
    #expect(list.count == 192, "基线应为 8 × 2 × 12 = 192 张，实际 \(list.count) 张")
    Evidence.writeJSON(["item": "A3.1", "count": list.count, "images": list], "A3.1-baselines.json")
  }

  // ---------------------------------------------------------------- A3.4–A3.9

  @Test("A3.4–A3.9：放大、thin、副图、叠加、十字线、价格轴")
  func extras() {
    guard Evidence.outputDir != nil else { return }
    let dev = Evidence.geometryDevice
    let s = Double(dev.scale)
    var list: [[String: Any]] = []
    var no = 0
    func next() -> Int { no += 1; return no }

    // ---- A3.4：3× 下放大 8 倍看边缘 ----
    // 每条各挑一款能代表它的风格，裁一小块出来做最近邻放大——放大的是设备像素本身，
    // 不插值，毛边有没有一眼就看得见。裁哪儿取决于要看的是什么：网格线、实体边、
    // 还是影线的圆头。
    enum Anchor { case grid, body, wickTop }
    let zooms: [(topic: String, style: String, anchor: Anchor, hollowOnly: Bool)] = [
      ("grid-both", "indigo", .grid, false),
      ("grid-h", "stout", .grid, false),
      ("grid-tick", "outline", .grid, false),
      ("grid-none", "glow", .grid, false),
      ("shape-hollowUp", "paper", .body, true),
      ("shape-outline", "outline", .body, true),
      ("radius", "pill", .body, false),
      ("wickcap-round", "needle", .wickTop, false),  // 影线 2.0 设备像素，全 11 款里最粗
    ]
    for z in zooms {
      let style = CandleStyle.style(id: z.style)
      let st = Evidence.state(style: style, dark: false, size: dev.size)
      let r = ChartRenderer(state: st)
      let p = r.probe(size: dev.size, scale: dev.scale)
      let img = Evidence.render(st, size: dev.size, scale: dev.scale)
      var crop = CGRect.zero
      var anchoredAt = ""
      switch z.anchor {
      case .grid:
        // 网格类：裁右边缘那一段留白（没有 K 线压着），横跨一条网格线
        let y = r.priceGridYs(size: dev.size).dropFirst(2).first ?? p.mainH / 2
        crop = CGRect(
          x: ((p.plotW - 40) * s).rounded(), y: ((y - 14) * s).rounded(),
          width: (44 * s).rounded(), height: (28 * s).rounded())
        anchoredAt = "网格线 y=\(y)"
      case .body:
        // 形态类：裁实体本身——空心 / 描边 / 圆角要看的都是实体那一圈边
        let xs = r.candleXs(size: dev.size, scale: dev.scale)
        let cands = xs.filter {
          $0.center > 60 && $0.center < p.plotW - 60 && $0.bodyHeight * s >= 12
            && (!z.hollowOnly || $0.hollow)
        }
        let c = cands.max(by: { $0.bodyHeight < $1.bodyHeight }) ?? xs[xs.count / 2]
        #expect(!z.hollowOnly || c.hollow, "\(z.topic) 没挑到一根走空心分支的蜡烛")
        crop = CGRect(
          x: ((c.center - 11) * s).rounded(), y: ((c.bodyTop - 4) * s).rounded(),
          width: (22 * s).rounded(), height: (26 * s).rounded())
        anchoredAt = "第 \(c.index) 根实体顶，实体高 \(c.bodyHeight) pt，空心=\(c.hollow)"
      case .wickTop:
        // 影线端头：裁上影线最长那根的顶端，圆头收口看得清
        let xs = r.candleXs(size: dev.size, scale: dev.scale)
        let c = xs.filter { $0.center > 60 && $0.center < p.plotW - 60 }
          .max(by: { ($0.bodyTop - $0.wickTop) < ($1.bodyTop - $1.wickTop) }) ?? xs[xs.count / 2]
        crop = CGRect(
          x: ((c.center - 5) * s).rounded(), y: ((c.wickTop - 2) * s).rounded(),
          width: (10 * s).rounded(), height: (9 * s).rounded())
        anchoredAt = "第 \(c.index) 根上影线顶端，影线长 \(c.bodyTop - c.wickTop) pt"
      }
      let big = Evidence.magnify(img, crop: crop, times: 8)
      emit(
        big, "M3-\(dev.id)-light-\(z.topic)-zoom8-\(String(format: "%02d", next())).png",
        [
          "item": "A3.4", "topic": z.topic, "style": style.id, "styleName": style.name,
          "grid": style.grid.rawValue, "shape": style.shape.rawValue,
          "radius": style.radius, "wickCap": style.wickCap.rawValue,
          "wickDevicePx": max(0.5, (4.0 / 3)), "anchor": anchoredAt,
          "cropDevicePx": [crop.minX, crop.minY, crop.width, crop.height], "magnify": 8,
        ], into: &list)
    }

    // ---- A3.5：thin 模式 ----
    // spacing < 1.3 只画影线；再压到下限 0.4 看一屏能塞多少根。
    for (tag, spacing, d) in [
      ("thin-1.2", 1.2, dev), ("thin-0.4", Chart.minBarSpacing, dev),
      ("thin-0.4-ipad", Chart.minBarSpacing, Evidence.devices.first { $0.id == "ipad" }!),
    ] {
      let style = CandleStyle.default
      let st = Evidence.state(style: style, dark: false, size: d.size, spacing: spacing)
      let r = ChartRenderer(state: st)
      let p = r.probe(size: d.size, scale: d.scale)
      let img = Evidence.render(st, size: d.size, scale: d.scale)
      #expect(p.thin, "\(tag) 的 spacing \(p.spacing) 没进 thin")
      emit(
        img, "M3-\(d.id)-light-\(tag)-\(String(format: "%02d", next())).png",
        [
          "item": "A3.5", "device": d.id, "askedSpacing": spacing, "spacing": p.spacing,
          "thin": p.thin, "bars": p.visibleHi - p.visibleLo + 1,
          "barsOnScreen": p.plotW / p.spacing, "style": style.id,
        ], into: &list)
    }

    // ---- A3.6：7 种副图各一张 ----
    for id in [IndicatorID.macd, .rsi, .kdj, .srsi, .atr, .vol, .oi] {
      let st = Evidence.state(
        style: .default, dark: false, size: dev.size, overlays: [], subs: [id])
      let img = Evidence.render(st, size: dev.size, scale: dev.scale)
      emit(
        img, "M3-\(dev.id)-light-sub-\(id.rawValue.lowercased())-\(String(format: "%02d", next())).png",
        ["item": "A3.6", "sub": id.rawValue, "subName": id.name,
         "params": id.defaultParams, "style": "stout"], into: &list)
    }

    // ---- A3.7：主图叠加 + 图例 ----
    for (tag, ov) in [
      ("ma", [IndicatorID.ma]), ("ema", [.ema]), ("boll", [.boll]), ("all", [.ma, .ema, .boll]),
    ] {
      let st = Evidence.state(
        style: .default, dark: false, size: dev.size, overlays: ov, subs: [])
      let img = Evidence.render(st, size: dev.size, scale: dev.scale)
      emit(
        img, "M3-\(dev.id)-light-overlay-\(tag)-\(String(format: "%02d", next())).png",
        ["item": "A3.7", "overlays": ov.map(\.rawValue),
         "params": ov.map { [$0.rawValue: $0.defaultParams] }], into: &list)
    }

    // ---- A3.8：十字线静态摆在某根上 ----
    for dark in [false, true] {
      let base = Evidence.state(style: .default, dark: dark, size: dev.size)
      let p = ChartRenderer(state: base).probe(size: dev.size, scale: dev.scale)
      let i = p.visibleLo + (p.visibleHi - p.visibleLo) * 2 / 3
      let st = Evidence.state(
        style: .default, dark: dark, size: dev.size, crosshair: Crosshair(index: i))
      let img = Evidence.render(st, size: dev.size, scale: dev.scale)
      emit(
        img, "M3-\(dev.id)-\(dark ? "dark" : "light")-crosshair-\(String(format: "%02d", next())).png",
        ["item": "A3.8", "barIndex": i, "barTime": Fixture.series.time(at: i),
         "close": Fixture.series.close[i], "timezone": Evidence.timezone.rawValue], into: &list)
    }

    // ---- A3.9：价格轴三模式 ----
    for mode in PriceMode.allCases {
      let st = Evidence.state(
        style: .default, dark: false, size: dev.size, price: PriceTransform(mode: mode))
      let img = Evidence.render(st, size: dev.size, scale: dev.scale)
      emit(
        img, "M3-\(dev.id)-light-axis-\(mode.rawValue)-\(String(format: "%02d", next())).png",
        ["item": "A3.9", "priceMode": mode.rawValue, "display": mode.display], into: &list)
    }

    #expect(list.count == 27, "附加证据应为 8 + 3 + 7 + 4 + 2 + 3 = 27 张，实际 \(list.count) 张")
    Evidence.writeJSON(["count": list.count, "images": list], "A3.4-A3.9-extras.json")
  }

  // Old prototype pixel manifests are historical artifacts. Shared-base geometry and
  // current-device screenshots replace those obsolete behavioral requirements.

  /// 同一份 state 画两次必须逐字节相同。做不到这条，176 张基线就没法进 CI。
  @Test("同一 state 画两次逐字节一致")
  func deterministic() {
    let dev = Evidence.devices.first { $0.id == "std" }!
    for style in CandleStyle.all {
      for dark in [false, true] {
        let st = Evidence.state(style: style, dark: dark, size: dev.size)
        let a = UIImage(cgImage: Evidence.render(st, size: dev.size, scale: dev.scale)).pngData()!
        let b = UIImage(cgImage: Evidence.render(st, size: dev.size, scale: dev.scale)).pngData()!
        #expect(a == b, "\(style.id)/\(dark ? "dark" : "light") 两次渲染不一致")
      }
    }
  }
}
