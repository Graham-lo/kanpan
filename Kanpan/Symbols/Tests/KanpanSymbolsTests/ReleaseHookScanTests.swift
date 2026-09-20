import Foundation
import Testing

// ============================================================ 审查 C.10 第 1 条 / C-02
//
// 「Release 不进测试后门」这件事，只靠在模拟器上跑一遍是证不完的：
// 测试后门的本质是**一串没人会在正常使用里设置的环境变量**，跑一遍只能证明
// 「我这次设的这几个没生效」，证不了「没有第 N 个我没想到的」。
//
// 所以这一条走的是机械扫描：把 app 与各包里**会进 Release 二进制**的源码全过一遍，
// 每一处读启动环境的地方，都要落在 `#if DEBUG` 里面。落在外面的，必须逐条出现在
// 下面那张交接表上，连责任人带理由——而且那张表是**双向**对账的：
// 别人把某一处修掉之后，这条用例会红，提醒来这儿把它划掉。
//
// 为什么这段扫描器要做成一条会跑的用例，而不是一次性脚本：C-02 的结论
// （「Release 里一个后门都不剩」）是靠扫描得出的，扫描不留在仓库里，下一次有人
// 随手加一个 `ProcessInfo.processInfo.environment["KANPAN_…"]`，这个结论就悄悄失效了。
//
// 注意条件编译的写法：`#if !DEBUG … #else …` 里的 `#else` 分支其实也只在 DEBUG 下编，
// 但机械扫描要认出这一点就得反着数一层。本轮把 `MarketModel.log` 那处改成了
// `#if DEBUG … #else`，全仓于是只剩一种写法，扫描不必猜。

@Suite("C.10-1 Release 里一个测试后门都没有")
struct ReleaseHookScanTests {

  /// 会进 Release、却仍然读启动环境的地方。每一行都带责任人。
  ///
  /// 这两处都在**本轮任务范围之外**的包里（同一轮审查里另有代理在改那两个包），
  /// 所以这儿不动它们，只把事实钉住：它们确实还在，改掉之后这条用例会红。
  static let handoffs: [String: String] = [
    "ChartView.swift":
      "KanpanChart：`accessibilityValue` 里的 `KANPAN_CHART_DIAGNOSTICS`。"
      + "Release 包里那块画布仍然会吐整包诊断 JSON。归 KanpanChart 那一摊处理。",
    "DrawStore.swift":
      "KanpanCore/Drawing：`applicationSupport()` 读 `KANPAN_TEST_PROFILE` 与 "
      + "`KANPAN_PERSISTENCE_PROFILE` 决定画线存到哪。归画线那一摊处理。",
  ]

  @Test("读启动环境的地方，要么在 DEBUG 里，要么在交接表上")
  func everyEnvironmentReadIsDebugOnly() throws {
    var reachable: [String: [String]] = [:]
    var debugOnly = 0
    for file in Self.productSources {
      for hit in Self.environmentReads(in: try String(contentsOf: file, encoding: .utf8)) {
        if hit.debugOnly { debugOnly += 1; continue }
        reachable[file.lastPathComponent, default: []].append("\(hit.line): \(hit.text)")
      }
    }
    #expect(debugOnly > 0, "一处 DEBUG 下的后门都没扫到，八成是扫描器自己瞎了")
    let complaint = "这些地方在 Release 里也读得到启动环境：\(reachable)。"
      + "交接表上写着的是 \(Self.handoffs.keys.sorted())。"
      + "新出现的要包进 `#if DEBUG`；表上的被别人修好了，就来把那一行划掉。"
    #expect(Set(reachable.keys) == Set(Self.handoffs.keys), "\(complaint)")
  }

  @Test("扫描器认得出条件编译，不是靠数关键字蒙的")
  func theScannerActuallyTracksNesting() {
    // 样例按数组拼，不用多行字符串：多行字符串里那几行 `#if DEBUG` 会顶在行首，
    // 隔壁 `ReleaseTestRosterTests` 的名册扫描是按文本看的，会把这个文件误认成
    // 「整体不进 Release 的套件」。
    let sample = ["let a = ProcessInfo.processInfo.environment[\"KANPAN_A\"]",
                  "#if DEBUG",
                  "let b = ProcessInfo.processInfo.environment[\"KANPAN_B\"]",
                  "  #if os(iOS)",
                  "  let c = ProcessInfo.processInfo.environment[\"KANPAN_C\"]",
                  "  #endif",
                  "#else",
                  "let d = 0",
                  "#endif",
                  "// let e = ProcessInfo.processInfo.environment[\"KANPAN_E\"]"]
      .joined(separator: "\n")
    let hits = Self.environmentReads(in: sample)
    #expect(hits.map(\.line) == [1, 3, 5], "注释该跳过、嵌套该跟住：\(hits)")
    #expect(hits.map(\.debugOnly) == [false, true, true])
  }

  @Test("app 自己那一摊里，一处 Release 可达的后门都没有")
  func theAppTargetIsClean() throws {
    // 交接表上那两处都在包里；app 目录（Kanpan/Kanpan/**）必须是干净的，
    // 这是 C-02 那一轮真正动手改掉的范围。
    for file in Self.productSources where file.path.contains("/Kanpan/Kanpan/") {
      let hits = Self.environmentReads(in: try String(contentsOf: file, encoding: .utf8))
        .filter { !$0.debugOnly }
      #expect(hits.isEmpty, "\(file.lastPathComponent) 在 Release 下还读得到启动环境：\(hits)")
    }
  }

  // ---------------------------------------------------------------- 扫描

  struct Hit: CustomStringConvertible {
    var line: Int
    var text: String
    var debugOnly: Bool
    var description: String { "\(line): \(text)" }
  }

  /// 一份源码里所有「读启动环境」的行，各自标上在不在 DEBUG 块里。
  ///
  /// 两种写法都算：直接写 `ProcessInfo.processInfo.environment`，以及把它接住之后
  /// 再按 `KANPAN_` 取值——后者单看取值那一行也得在 DEBUG 里，才算这条链没漏。
  static func environmentReads(in text: String) -> [Hit] {
    var hits: [Hit] = []
    var stack: [Bool] = []          // 每一层：这一层是不是「只在 DEBUG 下编」
    for (index, raw) in text.components(separatedBy: "\n").enumerated() {
      let line = raw.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("#if ") {
        stack.append(line.contains("DEBUG") && !line.contains("!DEBUG"))
      } else if line.hasPrefix("#elseif ") {
        if !stack.isEmpty { stack[stack.count - 1] = line.contains("DEBUG") && !line.contains("!DEBUG") }
      } else if line == "#else" {
        // `#if DEBUG` 的 `#else` 是 Release 分支；`#if !DEBUG` 的 `#else` 才是 DEBUG 分支。
        // 本仓只剩前一种写法（见文件头），这儿照样两种都翻得对。
        if !stack.isEmpty { stack[stack.count - 1] = !stack[stack.count - 1] }
      } else if line == "#endif" {
        if !stack.isEmpty { stack.removeLast() }
      }
      guard !line.hasPrefix("//") else { continue }
      guard line.contains("processInfo.environment") || line.contains("\"KANPAN_") else { continue }
      hits.append(Hit(line: index + 1, text: line, debugOnly: stack.contains(true)))
    }
    return hits
  }

  /// 会被编进 app 的源码：app 目录本身，加上各包的 `Sources/`。
  ///
  /// 不算：测试源码（本来就只在测试里编）、`kanpan-feed` 那个命令行取证工具
  /// （它是 mac 上跑的独立可执行，不在 app 二进制里）、构建产物与原型。
  /// 各壳包 `Sources/` 里是指向 app 目录的符号链接，同一份代码会被走到两次，按真身去重。
  static let productSources: [URL] = {
    let skipped: Set<String> = [".build", ".git", ".claude", ".xcbuild", ".xcbuild-release",
                                "DerivedData", "Evidence", "prototype", "Tools", "Backend",
                                "node_modules", "kanpan-feed"]
    var seen: Set<String> = []
    var out: [URL] = []
    let fm = FileManager.default
    guard let walker = fm.enumerator(at: ReleaseTestRosterTests.repoRoot,
                                     includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles])
    else { return [] }
    for case let url as URL in walker {
      if skipped.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
      guard url.pathExtension == "swift" else { continue }
      let path = url.path
      guard !path.contains("/Tests/") else { continue }
      guard path.contains("/Sources/") || path.contains("/Kanpan/Kanpan/") else { continue }
      let real = url.resolvingSymlinksInPath().path
      guard seen.insert(real).inserted else { continue }
      out.append(url)
    }
    return out.sorted { $0.path < $1.path }
  }()
}
