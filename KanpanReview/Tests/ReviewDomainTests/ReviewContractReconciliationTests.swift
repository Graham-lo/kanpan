import XCTest
import Foundation
import ReviewDomain

/// **客户端那份「能不能记」的规则，和服务端那份逐条对账。**
///
/// 复盘能不能记一条，权威只有一处：
/// `Backend/kanpan-api/vendor/scorebook-core/src/domain/native_review.rs` 的
/// `validate_range` / `validate`，外加 `interval.rs` 那 15 个币安周期。客户端本来只校验
/// 「至少 3 根、到期晚于现在、多空价格关系」，比服务端松得多——于是 BTCUSDC、1501 根、
/// 六万五千字的正文这些**本地过关、服务端必拒**的记录照样能保存、照样入队，然后永远
/// 400 / 409 堵在队首（审查 B-02 + B-06）。
///
/// 现在 `ReviewContract` 是那份规则在 Swift 这边的镜像。镜像的老毛病是漂：Rust 那边
/// 把上限从 1500 改成 3000、加一个 `observe` 之外的方向、或者币安新上一个周期，
/// Swift 这边没人知道。所以这个文件**直接读那两个 `.rs` 文件**，把常量抠出来和
/// `ReviewContract` / `ReviewInterval` 逐条比，对不上就红。
///
/// 做法照 `Kanpan/Settings/Tests/KanpanSettingsTests/PrefsFieldPlanTests.swift` 里的
/// `SettingsFieldContract`：靠 `#filePath` 退回仓库根去找那份权威文件，不拿当前工作目录
/// （`swift test` 的 CWD 取决于谁在哪儿敲的命令，用它拼路径迟早会在某台机器上找不到文件，
/// 然后被当成「测试挂了」）。差别是那边中间还有一个 `make sync-contract` 生成的 JSON，
/// 这边没有——复盘的服务端在 `vendor/` 里，这一轮不许动，所以直接解析 Rust 源码。
///
/// **这条红了不要改测试里的期望值，去改 `ReviewContract`。** 只有服务端那段校验被
/// 重写、下面的正则再也抠不出东西时，才动正则本身。
final class ReviewContractReconciliationTests: XCTestCase {

  // MARK: - 权威文件在哪儿

  /// 仓库根：从本源文件往上退四层
  /// `<root>/KanpanReview/Tests/ReviewDomainTests/ReviewContractReconciliationTests.swift`。
  private static var repositoryRoot: URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<4 { url.deleteLastPathComponent() }
    return url
  }

  private static let nativeReviewPath = "Backend/kanpan-api/vendor/scorebook-core/src/domain/native_review.rs"
  private static let intervalPath = "Backend/kanpan-api/vendor/scorebook-core/src/domain/interval.rs"

  private struct NotFound: Error {}

  private func rustSource(_ relativePath: String, file: StaticString = #filePath, line: UInt = #line) throws -> String {
    let url = Self.repositoryRoot.appendingPathComponent(relativePath)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      XCTFail("""
        读不到 \(relativePath)（找的是 \(url.path)）。
        这条测试是客户端规则和服务端规则之间唯一的对账，不能因为找不到文件就算过——
        文件搬家了就改这里的相对路径，仓库根是靠本文件的 `#filePath` 往上退四层算出来的。
        """, file: file, line: line)
      throw NotFound()
    }
    return text
  }

  // MARK: - 从 Rust 源码里抠东西

  private func captures(_ pattern: String, _ text: String) -> [[String]] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
    let whole = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.matches(in: text, range: whole).map { match in
      (0..<match.numberOfRanges).map { index in
        guard let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
      }
    }
  }

  /// 抠第一处匹配，抠不到就红——「找不到」本身就是服务端改过的信号。
  @discardableResult
  private func firstMatch(_ pattern: String, _ text: String, _ what: String,
                          file: StaticString = #filePath, line: UInt = #line) throws -> [String] {
    guard let match = captures(pattern, text).first else {
      XCTFail("""
        在服务端源码里找不到「\(what)」这一条（正则 `\(pattern)`）。
        多半是那段校验被重写了。先去读一遍新的 `validate` / `validate_range`，
        把 `ReviewContract` 改成和它一样，再把这里的正则跟上；不要把这条断言删掉。
        """, file: file, line: line)
      throw NotFound()
    }
    return match
  }

  private func number(_ literal: String) -> Int64? {
    Int64(literal.replacingOccurrences(of: "_", with: "").trimmingCharacters(in: .whitespaces))
  }

  /// `"long" | "short" | "observe"` 这种一串字面量里的全部字符串，保序。
  private func quoted(_ text: String) -> [String] { captures("\"([^\"]*)\"", text).map { $0[1] } }

  /// 一个 `fn` 的完整函数体，靠数花括号找收尾。
  ///
  /// 不能拿「下一个缩进四格的 `}`」当结尾：`validate` 里有两个并排的 `if` 块，
  /// 第一个块的收尾就长这样，按它截会把多空价格关系那一整段漏在外面——**漏掉的断言
  /// 永远是绿的**，这正是对账测试最怕的失效方式。这几个文件里没有含花括号的字符串
  /// 字面量，数括号就够准。
  private func body(ofFunction signature: String, in text: String,
                    file: StaticString = #filePath, line: UInt = #line) throws -> String {
    guard let start = text.range(of: signature) else {
      XCTFail("服务端源码里没有 `\(signature)` 了，函数改名或删了，去对一遍再改这里。", file: file, line: line)
      throw NotFound()
    }
    let rest = text[start.upperBound...]
    guard let open = rest.firstIndex(of: "{") else {
      XCTFail("`\(signature)` 后面找不到函数体的左花括号。", file: file, line: line)
      throw NotFound()
    }
    var depth = 0
    var index = open
    while index < rest.endIndex {
      if rest[index] == "{" { depth += 1 }
      if rest[index] == "}" {
        depth -= 1
        if depth == 0 { return String(rest[rest.index(after: open)..<index]) }
      }
      index = rest.index(after: index)
    }
    XCTFail("`\(signature)` 的花括号没配平，源码被截断了？", file: file, line: line)
    throw NotFound()
  }

  /// `const NAME: i64 = 7 * 86400;` 这种常量，支持互相引用（`THREE_DAYS = 3 * DAY`）。
  private func value(of expression: String, in text: String, depth: Int = 0) -> Int64? {
    let terms = expression.split(separator: "*").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    var product: Int64 = 1
    for term in terms {
      if let literal = number(term) { product *= literal; continue }
      guard depth < 6, let definition = captures("const \(term): i64 = ([^;]+);", text).first,
            let resolved = value(of: definition[1], in: text, depth: depth + 1) else { return nil }
      product *= resolved
    }
    return product
  }

  /// 去掉全部空白，用来比「这条规则还在不在」——Rust 那边换行怎么折都不影响。
  private func compact(_ text: String) -> String {
    text.components(separatedBy: .whitespacesAndNewlines).joined()
  }

  // MARK: - validate_range：框选的那一段

  func testChartRangeRulesMatchTheServer() throws {
    let source = try rustSource(Self.nativeReviewPath)
    let range = try body(ofFunction: "pub fn validate_range", in: source)

    let venue = try firstMatch("range\\.venue != \"([^\"]*)\"", range, "交易所白名单")[1]
    XCTAssertEqual(ReviewContract.venue, venue,
                   "服务端只认交易所 `\(venue)`，`ReviewContract.venue` 写的是 `\(ReviewContract.venue)`")

    let market = try firstMatch("range\\.market != \"([^\"]*)\"", range, "市场白名单")[1]
    XCTAssertEqual(ReviewContract.market, market, "服务端只认市场 `\(market)`")

    let suffix = try firstMatch("range\\.symbol\\.ends_with\\(\"([^\"]*)\"\\)", range, "计价币后缀")[1]
    XCTAssertEqual(ReviewContract.quoteSuffix, suffix,
                   "服务端要求品种以 `\(suffix)` 结尾；客户端放宽了就会让 USDC 永续存进队列再被整条拒掉")

    let symbolLimit = try firstMatch("range\\.symbol\\.len\\(\\) > ([0-9_]+)", range, "品种名长度上限")[1]
    XCTAssertEqual(Int64(ReviewContract.symbolMaxLength), number(symbolLimit), "品种名长度上限对不上")

    let bars = try firstMatch("\\(([0-9_]+)\\.\\.=([0-9_]+)\\)\\.contains\\(&range\\.bars\\)", range, "根数区间")
    XCTAssertEqual(Int64(ReviewContract.minBars), number(bars[1]), "最少根数对不上")
    XCTAssertEqual(Int64(ReviewContract.maxBars), number(bars[2]),
                   "最多根数对不上——这一条松了，1501 根的记录会一路进队列再被拒，把整条队列堵死")

    // 下面四条只比「这条规则还在不在」：它们在 Swift 那边是代码不是常量，抠不出数来比，
    // 但服务端哪天把它们删了 / 改了，客户端跟着松才是真的危险。
    let squeezed = compact(range)
    XCTAssertTrue(squeezed.contains("range.start>=range.end"),
                  "服务端的 `start < end` 没了，`ReviewContract.rangeFailure` 要跟着对一遍")
    XCTAssertTrue(squeezed.contains("range.end>cutoff"),
                  "服务端的「不许圈到未来」没了，客户端这一条也要重新对")
    XCTAssertTrue(squeezed.contains("c.is_ascii_uppercase()||c.is_ascii_digit()"),
                  "服务端对品种字符集的限制变了")
    XCTAssertTrue(squeezed.contains("interval.bars_between(time(range.start)?,time(range.end)?)!=range.bars"),
                  "服务端不再用 `bars_between` 复核根数了？客户端 `ReviewInterval.barsBetween` 那一套跟着重新对")
  }

  // MARK: - validate：这一条记录本身

  func testDraftRulesMatchTheServer() throws {
    let source = try rustSource(Self.nativeReviewPath)
    let draft = try body(ofFunction: "pub fn validate(", in: source)

    let version = try firstMatch("r\\.version != \"([^\"]*)\"", draft, "规则版本")[1]
    XCTAssertEqual(ReviewContract.ruleVersion, version, "服务端认的规则版本是 `\(version)`")

    let directions = quoted(try firstMatch("r\\.direction\\.as_str\\(\\), ([^)]*)\\)", draft, "方向枚举")[1])
    XCTAssertEqual(ReviewContract.directions, directions, "方向枚举对不上：服务端 \(directions)")

    let confirmations = quoted(try firstMatch("r\\.confirmation\\.as_str\\(\\), ([^)]*)\\)", draft, "确认方式枚举")[1])
    XCTAssertEqual(ReviewContract.confirmations, confirmations, "确认方式枚举对不上：服务端 \(confirmations)")

    let origins = quoted(try firstMatch("draft\\.origin\\.as_str\\(\\), ([^)]*)\\)", draft, "来源枚举")[1])
    XCTAssertEqual(ReviewContract.origins, origins, "来源枚举对不上：服务端 \(origins)")

    let confidences = try firstMatch("!\\[([0-9,_ ]+)\\]\\.contains\\(&v\\)", draft, "把握档位")[1]
      .split(separator: ",").compactMap { number(String($0)) }
    XCTAssertEqual(ReviewContract.confidences.map(Int64.init), confidences, "把握档位对不上：服务端 \(confidences)")

    let ahead = try firstMatch("draft\\.created > now \\+ ([0-9_]+)", draft, "本机时钟容差")[1]
    XCTAssertEqual(ReviewContract.createdAheadMillis, number(ahead), "本机时钟最多能快多少，两边对不上")

    let text = try firstMatch("draft\\.text\\.len\\(\\) > ([0-9_]+)", draft, "正文字节上限")[1]
    XCTAssertEqual(Int64(ReviewContract.textMaxBytes), number(text),
                   "正文上限对不上（服务端量的是 UTF-8 字节数，不是字符数）")

    let settings = try firstMatch("chart_settings.{0,80}?len\\(\\) > ([0-9_]+)", draft, "图表设置上限")[1]
    XCTAssertEqual(Int64(ReviewContract.chartSettingsMaxBytes), number(settings), "图表设置上限对不上")

    let snapshot = try firstMatch("drawing_snapshot.{0,80}?len\\(\\) > ([0-9_]+)", draft, "画线快照上限")[1]
    XCTAssertEqual(Int64(ReviewContract.drawingSnapshotMaxBytes), number(snapshot), "画线快照上限对不上")

    let horizon = try firstMatch("r\\.expires > draft\\.created \\+ ([0-9_]+) \\* ([0-9_]+)", draft, "观察窗口上限")
    XCTAssertEqual(ReviewContract.horizonMaxMillis, (number(horizon[1]) ?? 0) * (number(horizon[2]) ?? 0),
                   "到期最远能设到多久，两边对不上")

    let squeezed = compact(draft)
    XCTAssertTrue(squeezed.contains("draft.created<0"), "服务端的「记录时间不能是负数」没了")
    XCTAssertTrue(squeezed.contains("r.expires<=draft.created"), "服务端的「到期要晚于记录时间」没了")
    XCTAssertTrue(squeezed.contains("r.direction==\"long\"&&!(r.target>r.reference&&r.invalidation<r.reference)"),
                  "看多的价格关系变了，`ReviewContract.failure` 里那两行要跟着改")
    XCTAssertTrue(squeezed.contains("r.direction==\"short\"&&!(r.target<r.reference&&r.invalidation>r.reference)"),
                  "看空的价格关系变了，`ReviewContract.failure` 里那两行要跟着改")

    // **三口价为正这一条在 `observe` 之外**——服务端是在第一个 `if` 里对三个方向一视同仁地
    // 查的，「只记录」也逃不掉。客户端原来在 observe 上提前 return，于是只记录类的记录
    // 能带着 0 价存下来、发上去被拒，堵住整条队列（审查 B-02 的那一半成因）。
    guard let prices = squeezed.range(of: "![r.reference,r.target,r.invalidation]"),
          let observe = squeezed.range(of: "r.direction!=\"observe\"") else {
      return XCTFail("服务端那两段（三口价为正 / observe 分流）抠不出来了，去读一遍新的 `validate`")
    }
    XCTAssertTrue(prices.lowerBound < observe.lowerBound, """
      服务端把「三口价必须是正的有限数」挪到 `observe` 分流之后去了。
      `ReviewContract.failure` 现在是对三个方向都查的，跟着一起改，别让两边的松紧反过来。
      """)
  }

  // MARK: - interval.rs：15 个周期

  func testIntervalTableMatchesTheServer() throws {
    let source = try rustSource(Self.intervalPath)
    let names = try body(ofFunction: "pub fn as_str", in: source)
    var stringOf: [String: String] = [:]
    for arm in captures("([A-Za-z0-9_]+) *=> *\"([^\"]+)\"", names) { stringOf[arm[1]] = arm[2] }

    // `ALL` 是服务端那份「按时长升序」的权威顺序，客户端 `allCases` 要逐位一致：
    // 周期条、`fixedSeconds`、根数换算都按这个顺序读。
    let all = try firstMatch("pub const ALL: \\[Interval; ([0-9]+)\\] = \\[([^\\]]*)\\]", source, "周期总表")
    let order = all[2].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    XCTAssertEqual(Int(all[1]), order.count, "服务端 `ALL` 自己声明的长度和里面的项数就对不上")

    let serverIntervals = order.compactMap { stringOf[$0] }
    XCTAssertEqual(serverIntervals.count, order.count,
                   "`ALL` 里有 `as_str` 不认识的周期：\(order.filter { stringOf[$0] == nil })")
    XCTAssertEqual(ReviewInterval.allCases.map(\.rawValue), serverIntervals, """
      支持的周期对不上（顺序也算）。
      服务端 \(serverIntervals)
      客户端 \(ReviewInterval.allCases.map(\.rawValue))
      注意 `ReviewInterval` 和 `KanpanCore.Interval` 不是一回事：图表那份有服务端不认的 `1y`，
      也少了 `8h` / `3d`。复盘范围必须按这一份算。
      """)

    // 每根多少秒。月线在两边都必须是「没有固定秒数」——拿 30 天去除月线，
    // 算出来的根数和服务端 `bars_between` 对不上，整条记录会被 `invalid_chart_range` 拒掉。
    let seconds = try body(ofFunction: "pub fn fixed_seconds", in: source)
    for arm in captures("([A-Za-z0-9_]+) *=> *([^,\n]+),", seconds) {
      guard let key = stringOf[arm[1]], let interval = ReviewInterval(rawValue: key) else { continue }
      if arm[2].contains("None") {
        XCTAssertNil(interval.fixedSeconds, "服务端说 `\(key)` 没有固定秒数，客户端却给了一个")
        continue
      }
      guard let expected = value(of: arm[2], in: source) else {
        return XCTFail("`fixed_seconds` 里 `\(arm[1]) => \(arm[2])` 这一项算不出来，去补一下常量解析")
      }
      XCTAssertEqual(interval.fixedSeconds, expected, "`\(key)` 一根多少秒，两边对不上")
    }
    XCTAssertEqual(Set(ReviewInterval.allCases.compactMap(\.fixedSeconds)).count, ReviewInterval.allCases.count - 1,
                   "只有月线该是「没有固定秒数」，别的周期秒数还得两两不同")

    // 月线只能按日历加减：服务端 `bars_between` 的 `Mo1` 分支走的是年月之差 + 日历校正，
    // 客户端 `ReviewInterval.barsBetween` 抄的就是它。哪天服务端改了，这两条提醒去对。
    let between = compact(try body(ofFunction: "pub fn bars_between", in: source))
    XCTAssertTrue(between.contains("i64::from(t.year())*12+i64::from(t.month())"),
                  "服务端月线的根数算法变了，`ReviewInterval.barsBetween` 里那段日历校正要跟着改")
    XCTAssertTrue(between.contains("num_seconds().div_euclid(step)"),
                  "服务端定长周期的根数算法变了（原来是秒数向下取整除），客户端 `floorDiv` 那一套要跟着改")
  }
}
