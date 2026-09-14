import Testing
import SwiftUI
import Foundation
import KanpanCore
@testable import KanpanStyleArt

/// A6.2：十一款缩略图必须是**按这一版真画出来的**，不是贴图。
///
/// 这里用 `ImageRenderer` 把面板里那份 `StyleThumbnail` 原样渲染一遍：
/// 编不过、画不出、十一张里有两张一模一样，都会在这儿被抓住。
/// 顺带把 PNG 落到 `docs/acceptance/M6/`，当肉眼取证。
@Suite("风格缩略图", .serialized)
@MainActor
struct StyleThumbnailTests {

  @Test("十一款都能画出来，而且两两不同")
  func 逐款不同() throws {
    var seen: [String: String] = [:]
    for st in CandleStyle.all {
      let png = try #require(Self.render(style: st, dark: false), "\(st.name) 画不出来")
      let key = png.base64EncodedString()
      if let dup = seen[key] {
        Issue.record("「\(st.name)」和「\(dup)」画出来一模一样")
      }
      seen[key] = st.name
    }
    #expect(seen.count == CandleStyle.all.count)
    #expect(CandleStyle.all.count == 11)
  }

  @Test("涨跌对调之后缩略图跟着换色（A6.7 不漏这一处）")
  func 对调也管缩略图() throws {
    let st = CandleStyle.default
    let green = try #require(Self.render(style: st, dark: false, redUp: false))
    let red = try #require(Self.render(style: st, dark: false, redUp: true))
    #expect(green != red)
  }

  @Test("出一张十一款并排的图，存到 docs/acceptance/M6/")
  func 取证() throws {
    for dark in [false, true] {
      let sheet = VStack(alignment: .leading, spacing: 8) {
        ForEach(CandleStyle.all) { st in
          VStack(alignment: .leading, spacing: 4) {
            Text("\(st.name) · \(st.one)")
              .font(.system(size: 11))
              .foregroundStyle(Color(hex: dark ? Palette.darkSeed.ink2 : Palette.lightSeed.ink2))
            StyleThumbnail(style: st, colors: Palette.chart(dark: dark))
              .frame(width: 230)
          }
        }
      }
      .padding(14)
      .background(Color(hex: dark ? Palette.darkSeed.raised : Palette.lightSeed.raised))

      let renderer = ImageRenderer(content: sheet)
      renderer.scale = 3
      let png = try #require(Self.png(renderer))
      let url = Self.evidenceDir.appendingPathComponent("styles-\(dark ? "dark" : "light").png")
      try FileManager.default.createDirectory(at: Self.evidenceDir, withIntermediateDirectories: true)
      try png.write(to: url)
      #expect(png.count > 1000)
    }
  }

  // MARK: - 工具

  static func render(style: CandleStyle, dark: Bool, redUp: Bool = false) -> Data? {
    let view = StyleThumbnail(style: style, colors: Palette.chart(dark: dark, redUp: redUp))
      .frame(width: 230, height: StyleThumbnail.height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    return png(renderer)
  }

  static func png<V: View>(_ renderer: ImageRenderer<V>) -> Data? {
    #if canImport(AppKit)
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
    #elseif canImport(UIKit)
    return renderer.uiImage?.pngData()
    #else
    return nil
    #endif
  }

  /// 仓库根：从这份测试文件往上数四层（Kanpan/Settings/Tests/KanpanStyleArtTests）。
  static let evidenceDir: URL = {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()   // KanpanStyleArtTests
      .deletingLastPathComponent()   // Tests
      .deletingLastPathComponent()   // Settings
      .deletingLastPathComponent()   // Kanpan
      .deletingLastPathComponent()   // 仓库根
      .appendingPathComponent("docs/acceptance/M6", isDirectory: true)
  }()
}
