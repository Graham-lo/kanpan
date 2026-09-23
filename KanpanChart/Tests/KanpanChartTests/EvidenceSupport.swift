import CoreGraphics
import Foundation
import KanpanCore
import UIKit

@testable import KanpanChart

// MARK: - 定版快照（M3 取证的唯一数据源）
//
// 三份 fixture 由 `Tools/export-chart-fixtures.mjs` 从 `prototype/src/data.js` /
// `styles.js` / `chart.js` 导出，跟着测试 target 走 `Bundle.module`。
// 取证一律用它，**不碰网络**——不然每跑一次图都不一样，快照就没法比。

enum Fixture {
  private static func url(_ name: String) -> URL {
    guard let u = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
      ?? Bundle.module.url(forResource: name, withExtension: "json")
    else { fatalError("缺 fixture：\(name).json（先跑 node Tools/export-chart-fixtures.mjs）") }
    return u
  }

  private static func load<T: Decodable>(_ name: String, as: T.Type) -> T {
    let d = try! Data(contentsOf: url(name))
    return try! JSONDecoder().decode(T.self, from: d)
  }

  // ---------------------------------------------------------------- snapshot
  struct Snapshot: Decodable {
    struct Meta: Decodable {
      let base: String, quote: String
      let pricePrecision: Int, tickSize: Double
    }
    struct OI: Decodable { let t0: Int64, step: Int64, values: [Double] }
    let symbol: String, interval: String
    let t0: Int64, step: Int64, p: Int
    let open: [Double], high: [Double], low: [Double], close: [Double], volume: [Double]
    let oi: OI
    let meta: Meta
  }

  static let snapshot: Snapshot = load("snapshot", as: Snapshot.self)

  static let series: BarSeries = {
    let s = snapshot
    return BarSeries(
      symbol: s.symbol, interval: Interval(rawValue: s.interval) ?? .h1,
      t0: s.t0, step: s.step,
      open: s.open, high: s.high, low: s.low, close: s.close, volume: s.volume)
  }()

  static let oi: OISeries = {
    OISeries(t0: snapshot.oi.t0, step: snapshot.oi.step, values: snapshot.oi.values)
  }()

  static let symbol: SymbolInfo = {
    let m = snapshot.meta
    return SymbolInfo(
      symbol: snapshot.symbol, base: m.base, quote: m.quote,
      pricePrecision: m.pricePrecision, tickSize: m.tickSize)
  }()

  // ---------------------------------------------------------------- geometry
  struct Geometry: Decodable {
    struct View: Decodable { let from: Double, to: Double }
    struct Range: Decodable { let lo: Double, hi: Double, base: Double }
    struct Visible: Decodable { let lo: Int, hi: Int }
    struct Row: Decodable {
      let axisW: Double, timeH: Double, subH: Double
      let spacing: Double, bodyW: Double, wickW: Double, padTop: Double
      let view: View, range: Range, visible: Visible
      let mainH: Double, plotW: Double, thin: Bool

      var metrics: [String: Double] {
        ["axisW": axisW, "timeH": timeH, "subH": subH, "spacing": spacing,
         "bodyW": bodyW, "wickW": wickW, "padTop": padTop]
      }
    }
    let device: String, width: Double, height: Double, scale: Double
    let overlays: [String], subs: [String]
    let metrics: [String]
    let styles: [String: Row]
  }

  static let geometry: Geometry = load("geometry", as: Geometry.self)

  // ---------------------------------------------------------------- colors
  struct Colors: Decodable {
    struct Row: Decodable {
      let upBody: String, downBody: String, wick: String, wickDown: String
      let grid: String, bg: String, lastLine: String, axisText: String
      let gridMode: String, shape: String
      let wickDevicePx: Double, outlineDevicePx: Double, lastDash: Bool
    }
    let points: [String]
    let lastBarUp: Bool
    let themes: [String: [String: Row]]
  }

  static let colors: Colors = load("colors", as: Colors.self)
}

// MARK: - 取证的固定口径
//
// 这几项一改，176 张基线和 77 个几何数就全变了，所以和导出脚本写死在同一处口径上。

enum Evidence {
  /// 主图叠加与副图：和 `Tools/export-chart-fixtures.mjs` 一致。
  static let overlays: [IndicatorID] = [.ma]
  static let subs: [IndicatorID] = [.macd, .rsi]

  /// 时区固定 UTC。原型跟设备走，但取证要能在任何机器上重放出同一张图，
  /// 时间轴文字不能跟着跑测试的人所在时区变——这是刻意的偏差，记在清单里。
  static let timezone: TZChoice = .utc

  /// A0.2 的八台机型，尺寸与 `prototype/src/app.js` 的 `DEVICES` 一一对应。
  struct Device: Sendable {
    let id: String, name: String
    let w: Double, h: Double, scale: CGFloat
    var size: CGSize { CGSize(width: w, height: h) }
  }

  static let devices: [Device] = [
    .init(id: "se", name: "iPhone SE (3rd generation)", w: 375, h: 667, scale: 2),
    .init(id: "mini", name: "iPhone 13 mini", w: 375, h: 812, scale: 3),
    .init(id: "std", name: "iPhone 15", w: 393, h: 852, scale: 3),
    .init(id: "pro", name: "iPhone 16 Pro", w: 402, h: 874, scale: 3),
    .init(id: "air", name: "iPhone Air", w: 420, h: 912, scale: 3),
    .init(id: "plus", name: "iPhone 16 Plus", w: 430, h: 932, scale: 3),
    .init(id: "max", name: "iPhone 17 Pro Max", w: 440, h: 956, scale: 3),
    .init(id: "ipad", name: "iPad mini (A17 Pro)", w: 744, h: 1133, scale: 2),
  ]

  /// A3.2 的量化机型：浅色、iPhone 16 Pro、@3x。
  static let geometryDevice = devices.first { $0.id == "pro" }!

  /// 造一帧取证用的 state。
  ///
  /// 视野按 A3.1：`右边缘对齐末根 + spacing = AICoin 默认`，也就是原型的 `resetView()`。
  static func state(
    dark: Bool,
    size: CGSize,
    overlays: [IndicatorID] = Evidence.overlays,
    subs: [IndicatorID] = Evidence.subs,
    spacing: Double? = nil,
    price: PriceTransform = .init(),
    crosshair: Crosshair? = nil,
    redUp: Bool = false
  ) -> ChartState {
    let L = Layout(width: Double(size.width), height: Double(size.height), subs: subs)
    let view = ViewMath.reset(
      series: Fixture.series, plotW: L.plotW, spacing: spacing ?? AICoinBehavior.initialSpacing)
    return ChartState(
      series: Fixture.series, symbol: Fixture.symbol, view: view,
      dark: dark, redUp: redUp, price: price,
      overlays: overlays, subs: subs, timezone: Evidence.timezone,
      oi: Fixture.oi, crosshair: crosshair)
  }

  // ---------------------------------------------------------------- 离屏渲染

  /// 离屏画一整帧（底图 + 最新价 + 十字线），跟 `ChartView` 三层合成的结果一致。
  @MainActor
  static func render(_ state: ChartState, size: CGSize, scale: CGFloat) -> CGImage {
    let renderer = ChartRenderer(state: state)
    let f = UIGraphicsImageRendererFormat.preferred()
    f.scale = scale
    f.opaque = true
    let r = UIGraphicsImageRenderer(size: size, format: f)
    return r.image { ctx in
      let c = ctx.cgContext
      renderer.draw(in: c, size: size, scale: scale, live: true)
      guard state.crosshair != nil else { return }
      // 十字线单独画到一张透明图上再合到底图，和 `crossLayer` 的叠法一致。
      // （单张 `draw` 已经把图例画进底图了，这里只补十字线，不重复画图例。）
      let tf = UIGraphicsImageRendererFormat.preferred()
      tf.scale = scale
      tf.opaque = false
      let cross = UIGraphicsImageRenderer(size: size, format: tf).image { octx in
        renderer.drawOverlay(in: octx.cgContext, size: size, scale: scale)
      }
      cross.draw(at: .zero)
    }.cgImage!
  }

  /// 放大 N 倍看边缘（A3.4）。**最近邻**，不插值——要看的就是设备像素本身。
  @MainActor
  static func magnify(_ img: CGImage, crop: CGRect, times: Int) -> CGImage {
    let sub = img.cropping(to: crop) ?? img
    let w = sub.width * times, h = sub.height * times
    let ctx = CGContext(
      data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none
    ctx.draw(sub, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
  }

  // ---------------------------------------------------------------- 落盘

  /// 仓库根。`#filePath` 是编译期写死的绝对路径：
  /// `<仓库>/KanpanChart/Tests/KanpanChartTests/EvidenceSupport.swift`，往上数四层。
  /// 模拟器里的测试进程本身就是一个普通的 macOS 进程，能直接写宿主机路径。
  static let repoRoot: URL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // KanpanChartTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // KanpanChart
    .deletingLastPathComponent()  // 仓库根

  /// 落盘目录。两条路，都没有就**不落盘**——日常 `make chart-test` 不该在仓库里
  /// 拉出两百多张 png，所以取证必须显式开。
  ///
  /// 1. 环境变量 `KANPAN_EVIDENCE_DIR`（CI 或手工指定别处时用）；
  /// 2. 仓库里存在 `docs/acceptance/M3/.render` 标记文件——`make evidence` 开跑前建、
  ///    跑完删。之所以留这条，是因为 `xcodebuild test` 的 `TEST_RUNNER_` 前缀对
  ///    SwiftPM scheme 的 xctest 宿主不生效，环境变量根本进不到测试进程里。
  static var outputDir: URL? {
    if let p = ProcessInfo.processInfo.environment["KANPAN_EVIDENCE_DIR"], !p.isEmpty {
      let u = URL(fileURLWithPath: p, isDirectory: true)
      try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
      return u
    }
    let u = repoRoot.appendingPathComponent("docs/acceptance/M3", isDirectory: true)
    guard FileManager.default.fileExists(atPath: u.appendingPathComponent(".render").path)
    else { return nil }
    return u
  }

  @discardableResult
  static func writePNG(_ img: CGImage, _ name: String) -> Int {
    guard let dir = outputDir else { return 0 }
    let data = UIImage(cgImage: img).pngData()!
    try! data.write(to: dir.appendingPathComponent(name))
    return data.count
  }

  @discardableResult
  static func writeJSON(_ obj: Any, _ name: String) -> Bool {
    guard let dir = outputDir else { return false }
    let d = try! JSONSerialization.data(
      withJSONObject: obj, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try! d.write(to: dir.appendingPathComponent(name))
    return true
  }

  @discardableResult
  static func writeText(_ s: String, _ name: String) -> Bool {
    guard let dir = outputDir else { return false }
    try! s.data(using: .utf8)!.write(to: dir.appendingPathComponent(name))
    return true
  }

  /// §12.1 的文件名：`M3-<机型>-<主题>-<风格>-<编号>.png`。
  static func name(_ device: String, _ dark: Bool, _ style: String, _ no: Int) -> String {
    String(format: "M3-%@-%@-%@-%02d.png", device, dark ? "dark" : "light", style, no)
  }
}

// MARK: - 像素读取

/// 一张位图的像素，按 sRGB / 每通道 8 位读出来。
struct Pixels {
  let w: Int, h: Int
  let buf: [UInt8]

  init(_ img: CGImage) {
    // 局部量再赋给存储属性：闭包里直接用 self.w / self.h 会被当成「初始化前捕获 self」。
    let ww = img.width, hh = img.height
    var b = [UInt8](repeating: 0, count: ww * hh * 4)
    b.withUnsafeMutableBytes { raw in
      let ctx = CGContext(
        data: raw.baseAddress, width: ww, height: hh, bitsPerComponent: 8,
        bytesPerRow: ww * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      ctx.draw(img, in: CGRect(x: 0, y: 0, width: ww, height: hh))
    }
    w = ww
    h = hh
    buf = b
  }

  subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let i = (y * w + x) * 4
    return (Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2]), Int(buf[i + 3]))
  }

  /// 取证图不透明，比色只看 RGB 三通道。
  func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    let p = self[x, y]
    return (p.r, p.g, p.b)
  }

  func hex(_ x: Int, _ y: Int) -> String {
    let p = self[x, y]
    return String(format: "#%02X%02X%02X", p.r, p.g, p.b)
  }
}

extension Hex {
  /// 取色比对只看 RGB 三通道（取证图是不透明的）。
  var rgb8: (r: Int, g: Int, b: Int) {
    let b = bytes
    return (b.r, b.g, b.b)
  }
}

/// 两个颜色的最大通道差。
func chanDelta(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Int {
  max(abs(a.r - b.r), max(abs(a.g - b.g), abs(a.b - b.b)))
}

/// 底色和目标色按覆盖率 k 混出来的 8 位色（CoreGraphics 抗锯齿就是这么合成的）。
func blend8(bg: (r: Int, g: Int, b: Int), fg: (r: Int, g: Int, b: Int), k: Double)
  -> (r: Int, g: Int, b: Int)
{
  func f(_ a: Int, _ b: Int) -> Int { Int((Double(a) + (Double(b) - Double(a)) * k).rounded()) }
  return (f(bg.r, fg.r), f(bg.g, fg.g), f(bg.b, fg.b))
}

/// 这个像素落在 bg → fg 这条直线的什么位置上（用差最大的通道估，避开除零）。
func coverage(of px: (r: Int, g: Int, b: Int), bg: (r: Int, g: Int, b: Int),
              fg: (r: Int, g: Int, b: Int)) -> Double {
  let d = [(fg.r - bg.r, px.r - bg.r), (fg.g - bg.g, px.g - bg.g), (fg.b - bg.b, px.b - bg.b)]
  guard let best = d.max(by: { abs($0.0) < abs($1.0) }), best.0 != 0 else { return 1 }
  return Double(best.1) / Double(best.0)
}
