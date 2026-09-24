import Foundation
import Testing

// ============================================================ 审查 C.10 第 9 条
//
// 钉的是「Release 测试没有靠裁掉套件假绿」。
//
// 报告里那句话的意思是：`make test-release` 报出来的通过数，必须和 Debug 那一份
// **测的是同一批行为**。一个套件只要整体包在条件编译里，它在 Release 下就压根不存在，
// 于是「Release 全绿」这件事里少掉的那一块，从结果上一点痕迹都看不出来——
// 通过数变小，没有任何一行写着「少掉的是这些」。跳过也一样：一条灰钩在汇总里
// 跟绿钩挨着，人扫一眼只看红的。
//
// 所以这一条不测产品，它测**测试本身**：把全仓所有测试源码里的条件编译与跳过
// 各自点成一张名册，和这儿写死的白名单逐字对账。想再关掉一个套件可以，
// 但必须同时来这儿加一行，把理由写下来——那正是报告要的「每个差异都有明确 DEBUG-only 原因」。
//
// 它落在品种那一组（`Kanpan/KanpanTests/Symbols/`），是因为还留着条件编译的测试套件里
// 有一个就在这一组（`SymbolPrefsSeedIsolationTests`）。单测跑在模拟器上的 app 宿主里，
// 模拟器进程读得到本机工作树，扫描照常成立。

@Suite("C.10-9 Release 的测试名册")
struct ReleaseTestRosterTests {

  // ---------------------------------------------------------------- 白名单

  /// 允许整体不进 Release 的测试文件，以及为什么。
  ///
  /// 加一项之前先想清楚：Release 下这段代码真的不存在（不是「跑不过」），
  /// 而且那个行为另有 Release 下真的会跑的用例守着。
  static let debugOnly: [String: String] = [
    "SymbolPrefsSeedIsolationTests.swift":
      "钉的是 `SymbolPrefsStore.testSeed`，那段种子脚手架按 A-07 / C-02 只存在于 DEBUG；"
      + "Release 下这条分支根本不在，用例会为了错的理由变绿。",
    "CrosshairWorkTests.swift":
      "靠 `ChartWorkCounter` 读数的那三条（几何/布局/掩码的重算次数）圈在 DEBUG 里："
      + "那份计数存储趴在渲染热路径上，Release 里 `bump` 是空的、`count` 恒返回 0，"
      + "断言要么直接红，要么因为上界永远成立而假绿。同文件里「一次移动一条回调」"
      + "这类产品行为没被圈进去，Release 照样跑。",
    "P31AlertKindsTests.swift":
      "「UI 注入写裸代号也响」那一条调的是 `WatchMoveMonitor.injectTestMove`，"
      + "那是 UI 用例的注入口，只在 DEBUG 里有。同文件其余用例两种配置都跑。",
  ]

  /// 允许跳过用例的文件，以及跳过的那一下是什么门。
  ///
  /// 两条都必须是**运行环境不成立**的门（窄窗、没给显式开关），不许是
  /// 「数据没来就跳过」那种——那种跳的是产品的毛病，正是 C.9 点名的假绿。
  static let skipGates: [String: String] = [
    "IPadLayoutUITests.swift": "窗口宽度不到 700pt 时，iPad 宽屏封顶这件事无从谈起。",
    "UITestSupport.swift":
      "`ManualTool.skipUnlessRequested`：会写进这台设备上用户正式自选存档的手动工具，"
      + "没给 KANPAN_INSTALL_USER_FAVORITES=1 就记成「未执行」。",
  ]

  /// Release 下必须真的跑起来的那几摊行为，各自的看门文件。
  ///
  /// 报告点名了四样：Release 白名单、保存恢复、设备 kind、会话正常链。
  /// 本轮把账号那三套从条件编译里拆了出来（改成白名单主机 + 自带 URLProtocol），
  /// 这儿钉住它们别再被包回去。
  static let mustRunInRelease: [String: String] = [
    "ClientHardeningTests.swift": "Release 主机白名单",
    "SymbolPrefsDurabilityTests.swift": "自选的保存与恢复",
    "DeviceKindTests.swift": "设备 kind",
    "SessionLifecycleTests.swift": "会话正常链",
  ]

  // ---------------------------------------------------------------- 名册

  @Test("整体不进 Release 的测试套件，只剩白名单上那些")
  func conditionalSuitesMatchTheRoster() throws {
    var found: [String: [Int]] = [:]
    for file in Self.testSources {
      let hits = Self.conditionalCompilationLines(in: try String(contentsOf: file, encoding: .utf8))
      if !hits.isEmpty { found[file.lastPathComponent, default: []].append(contentsOf: hits) }
    }
    let complaint = "测试源码里的条件编译名册变了：现在是 \(found.keys.sorted())，"
      + "白名单是 \(Self.debugOnly.keys.sorted())。"
      + "要么把新关掉的那个套件改成 Release 也能编，要么来 `debugOnly` 里写下理由。"
    #expect(Set(found.keys) == Set(Self.debugOnly.keys), "\(complaint)")
  }

  @Test("名册上每一项，理由都写在它自己文件的开头")
  func everyRosterEntryCarriesItsReason() throws {
    for (name, reason) in Self.debugOnly {
      #expect(!reason.isEmpty, "\(name) 的理由是空的")
      let file = try #require(Self.testSources.first { $0.lastPathComponent == name },
                              "白名单上的 \(name) 在工作树里找不到了")
      let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: "\n")
      let first = try #require(lines.firstIndex { Self.opensConditionalCompilation($0) })
      // 往上找最近的一行非空内容：必须是注释，也就是「这儿为什么关掉」写在手边。
      let preceding = lines[..<first].last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      let trimmed = (preceding ?? "").trimmingCharacters(in: .whitespaces)
      #expect(trimmed.hasPrefix("//"), "\(name) 的条件编译上面没有写理由：\(trimmed)")
    }
  }

  @Test("跳过只许是环境门，不许是「数据没来就算了」")
  func skipsAreEnvironmentGatesOnly() throws {
    var throwing: Set<String> = []
    var silent: [String] = []
    for file in Self.testSources {
      let text = try String(contentsOf: file, encoding: .utf8)
      for line in text.components(separatedBy: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.hasPrefix("//") else { continue }
        if trimmed.contains("XCTSkip(") { throwing.insert(file.lastPathComponent) }
        // `XCTSkipUnless` / `XCTSkipIf` 是「条件一不成立就悄悄灰掉」的写法：
        // 它们判的往往是产品有没有把数据送到，那种地方该红不该灰（审查 C.9）。
        if trimmed.contains("XCTSkipUnless") || trimmed.contains("XCTSkipIf") {
          silent.append("\(file.lastPathComponent)：\(trimmed)")
        }
      }
    }
    #expect(silent.isEmpty, "还有条件跳过没拆成硬断言：\(silent)")
    #expect(throwing == Set(Self.skipGates.keys),
            "跳过的名册变了：现在是 \(throwing.sorted())，白名单是 \(Self.skipGates.keys.sorted())")
  }

  @Test("Release 下必须真的跑的那几摊，一个都没被包回条件编译里")
  func namedBehavioursActuallyRunInRelease() throws {
    for (name, what) in Self.mustRunInRelease {
      let file = try #require(Self.testSources.first { $0.lastPathComponent == name },
                              "\(what) 的用例文件 \(name) 不见了")
      let text = try String(contentsOf: file, encoding: .utf8)
      #expect(Self.conditionalCompilationLines(in: text).isEmpty,
              "\(what)（\(name)）又被条件编译包起来了，Release 下等于没测")
      #expect(text.contains("@Test"), "\(what)（\(name)）里一条用例都没有")
    }
  }

  @Test("Makefile 的 Release 回归口子和这份名册对得上")
  func makefileDocumentsTheSameRoster() throws {
    let makefile = try String(contentsOf: Self.repoRoot.appendingPathComponent("Makefile"),
                              encoding: .utf8)
    #expect(makefile.contains("test-release:"), "没有 `test-release` 目标，Release 根本没人跑")
    // xcodebuild 在 Release 下默认 `ENABLE_TESTABILITY=NO`，缺了它 `@testable import` 编不过。
    #expect(makefile.contains("ENABLE_TESTABILITY=YES"),
            "走 xcodebuild 的那几个包没写 ENABLE_TESTABILITY=YES")
    for name in Self.debugOnly.keys {
      #expect(makefile.contains(name),
              "Makefile 的 Release 注释里没有列出 \(name)——差集必须写在人看得见的地方")
    }
    // 账号与复盘两个包必须挂在 `test` 上（审查 C-05）：它们过去一个都不在。
    let line = try #require(makefile.components(separatedBy: "\n").first { $0.hasPrefix("test:") })
    for target in ["account-test", "review-test", "main-ios-test", "chart-test"] {
      #expect(line.contains(target), "`test` 里没有 \(target)：\(line)")
    }
  }

  // ---------------------------------------------------------------- 扫描

  /// 工作树根：从这个文件往上走，直到同时看见 Makefile 和 workspace。
  static let repoRoot: URL = {
    var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let fm = FileManager.default
    while dir.pathComponents.count > 1 {
      if fm.fileExists(atPath: dir.appendingPathComponent("Makefile").path),
         fm.fileExists(atPath: dir.appendingPathComponent("Kanpan.xcworkspace").path) {
        return dir
      }
      dir.deleteLastPathComponent()
    }
    return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
  }()

  /// 全仓的测试源码。构建产物、别的工作树、原型目录都不算。
  static let testSources: [URL] = {
    let skipped: Set<String> = [".build", ".git", ".claude", ".xcbuild", ".xcbuild-release",
                                "DerivedData", "Evidence", "prototype", "node_modules", "target"]
    var out: [URL] = []
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: repoRoot, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles])
    else { return [] }
    for case let url as URL in walker {
      if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
      guard url.pathExtension == "swift" else { continue }
      let path = url.path
      guard path.contains("/Tests/") || path.contains("/Kanpan/KanpanTests/")
              || path.contains("/KanpanUITests/") else { continue }
      // 名册自己不算测试对象：它整篇都在拿「#if DEBUG」「XCTSkipUnless」这些词做文章，
      // 扫进来只会照见自己。
      guard url.lastPathComponent != URL(fileURLWithPath: #filePath).lastPathComponent
      else { continue }
      out.append(url)
    }
    return out.sorted { $0.path < $1.path }
  }()

  /// 这一行是不是在按**构建配置**开一个条件编译块。只认块的开头，`#else` / `#endif` 不算。
  ///
  /// 只数提到 DEBUG / RELEASE 的那些：它们才会造成「Debug 跑得到、Release 跑不到」。
  /// `#if os(iOS)` `#if canImport(UIKit)` 这类是平台门（`FrameProbeSmokeTests` 就是），
  /// Debug 和 Release 在同一台机器上给出的答案一模一样，不属于这一条要防的事。
  static func opensConditionalCompilation(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#if ") else { return false }
    return trimmed.contains("DEBUG") || trimmed.contains("RELEASE")
  }

  static func conditionalCompilationLines(in text: String) -> [Int] {
    text.components(separatedBy: "\n").enumerated()
      .filter { opensConditionalCompilation($0.element) }
      .map { $0.offset + 1 }
  }
}
