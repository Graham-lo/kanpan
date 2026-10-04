import Foundation
import Testing

/// 审查 A 线：界面字号只许从 `TypeScale` 的字阶上取（DesignTokens.swift）。
///
/// 术语解释卡的正文原来手写 `ScaledFont(14, …)`：14 不在字阶上，和标题 16 只差 2pt，
/// 层级读不出来，也绕开了全 app 一处改字号的总闸。这条扫一遍 app 源码，
/// 除了定义字阶的 DesignTokens.swift，谁也不许再写带数字的 `ScaledFont(`。
@Suite("字号只走字阶")
struct TypeScaleLadderTests {
  /// app 源码根：测试文件在 `<root>/Kanpan/KanpanTests/Main/` 底下。
  static let appSources: URL = {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<3 { url.deleteLastPathComponent() }
    return url.appendingPathComponent("Kanpan")
  }()

  @Test("app 里除了字阶定义处，没有手写字号的 ScaledFont")
  func noHandWrittenFontSizes() throws {
    let files = FileManager.default.enumerator(at: Self.appSources, includingPropertiesForKeys: nil)?
      .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
    #expect(files.count > 50, "没扫到 app 源码：\(Self.appSources.path)")
    let pattern = try Regex(#"ScaledFont\(\s*[0-9.]"#)
    var offenders: [String] = []
    for file in files where file.lastPathComponent != "DesignTokens.swift" {
      let text = try String(contentsOf: file, encoding: .utf8)
      for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
      where line.contains(pattern) && !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
        offenders.append("\(file.lastPathComponent):\(n + 1)")
      }
    }
    #expect(offenders.isEmpty, "这些地方手写了字号，不在 TypeScale 字阶上：\(offenders)")
  }
}
