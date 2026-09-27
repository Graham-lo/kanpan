import Foundation
import Testing

// ============================================================ 自动复盘 · 只读守卫
//
// 用户 2026-09-27 要的是「只读 API 做成自动复盘」：app 只看账户，永远不替用户下单、撤单、划转、提现。
// 接入时会查 Key 的权限、拒收非只读 Key，但那是交易所那一侧的保险；这一侧的保险是**源码里根本没有
// 那些端点**。只靠自觉守不住——下一次有人顺手加一个「一键平仓」，结论就悄悄失效了。
//
// 所以照 `ReleaseHookScanTests` 的做法，把会进 app 的账户代码（`Kanpan/Kanpan/Exchange/`）与
// 拼回合的纯逻辑（`KanpanCore/…/Trades/`）逐行扫一遍：出现下单 / 批量下单 / 撤单 / 划转 / 提现的路径、
// `DELETE` 方法、或者 `withdraw` 字样，这条用例就红；每一处 `httpMethod` 也必须是 `GET`。
// 单测跑在模拟器上的 app 宿主里，读得到本机工作树。

@Suite("自动复盘 · 账户代码里没有任何能动钱的端点")
struct ExchangeEndpointScanTests {

  /// 一出现就算破戒的字样（区分大小写）。`enableWithdrawals` 是权限查询的 JSON 键，大写 W，不在此列。
  static let forbidden = [
    "/fapi/v1/order",
    "/fapi/v1/batchOrders",
    "/fapi/v1/allOpenOrders",
    "/sapi/v1/capital",
    "/sapi/v1/asset/transfer",
    "/api/v3/order",
    "DELETE",
    "withdraw",
  ]

  static let scannedRoots = ["Kanpan/Kanpan/Exchange", "KanpanCore/Sources/KanpanCore/Trades"]

  @Test("账户代码与拼回合逻辑里，一处能动钱的端点都没有")
  func noMoneyMovingEndpoints() throws {
    var hits: [String] = []
    for file in Self.sources {
      hits += Self.violations(in: try String(contentsOf: file, encoding: .utf8))
        .map { "\(file.lastPathComponent):\($0)" }
    }
    #expect(hits.isEmpty, "只读账户代码里出现了能动钱的端点或方法：\(hits)")
  }

  @Test("扫描器真的在扫：文件列表不空，账户实现在里面，样例里的每一种都认得出来")
  func theScannerIsNotBlind() {
    let names = Set(Self.sources.map(\.lastPathComponent))
    #expect(names.contains("BinanceFuturesAccount.swift"), "扫描范围里没有账户实现：\(names.sorted())")
    #expect(names.contains("RoundBuilder.swift"), "扫描范围里没有拼回合逻辑：\(names.sorted())")
    for bad in Self.forbidden {
      #expect(!Self.violations(in: "let p = \"\(bad)\"").isEmpty, "扫描器认不出 \(bad)")
    }
    #expect(!Self.violations(in: "request.httpMethod = \"POST\"").isEmpty, "扫描器认不出非 GET")
    #expect(Self.violations(in: "request.httpMethod = \"GET\"").isEmpty)
    #expect(Self.violations(in: "var enableWithdrawals: Bool?").isEmpty)
  }

  /// 一段源码里的违规行（行号: 内容）。
  static func violations(in text: String) -> [String] {
    var out: [String] = []
    for (index, line) in text.components(separatedBy: "\n").enumerated() {
      let bad = forbidden.contains { line.contains($0) }
      let nonGet = line.contains("httpMethod") && line.contains("=") && !line.contains("\"GET\"")
      if bad || nonGet { out.append("\(index + 1): \(line.trimmingCharacters(in: .whitespaces))") }
    }
    return out
  }

  static var sources: [URL] {
    let fm = FileManager.default
    var out: [URL] = []
    for root in scannedRoots {
      let dir = ReleaseTestRosterTests.repoRoot.appendingPathComponent(root, isDirectory: true)
      guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { continue }
      for case let url as URL in walker where url.pathExtension == "swift" { out.append(url) }
    }
    return out.sorted { $0.path < $1.path }
  }
}
