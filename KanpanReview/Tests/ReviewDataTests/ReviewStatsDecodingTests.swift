import XCTest
import ReviewDomain
import ReviewData

// ============================================================ 战绩那份响应怎么解
//
// 服务端（B-07）改完之后一张响应里同时有两套分组：
//
// - 老的 `groups` / `proof` / `grouping`：**绝对**口径——目标 80286.3、到期某个具体时刻，
//   几乎一笔一组，界面上只能一行行写「样本不足」；
// - 新的 `comparableGroups` / `comparableProof` / `comparableGrouping`：**相对**口径——
//   同方向、同确认方式、同品种周期，目标与止损按相对幅度分档、时长分档，同一类判断
//   才攒得到一起，这才是报告 B-07 要给用户看的那份战绩。
//
// 客户端的规矩就两条，这个文件盯的也是这两条：
//
// 1. **新的给了就只用新的**，老的一眼都不看（界面上不摆两套口径让用户挑）；
// 2. **老服务端没给就照旧**——升级顺序不该由客户端来担心。

final class ReviewStatsDecodingTests: XCTestCase {

  private func decode(_ json: String) throws -> NativeStatsResponse {
    try JSONDecoder().decode(NativeStatsResponse.self, from: Data(json.utf8))
  }

  /// 新服务端：两套都在，用相对口径那套。
  ///
  /// 数字特意摆成两套不一样的：绝对那套是 `0/1`（噪声），相对那套是 `13/20`。
  /// 要是哪天又退回老字段，这条会直接报出「界面上摆的是 0%」。
  func testTheComparableGroupingWinsWhenTheServerSendsIt() throws {
    let response = try decode("""
    {
      "groups": [{"id": "abs-1", "title": "BTCUSDT 1h 目标 80286.3", "total": 1, "correct": 0}],
      "proof": {"compatible_groups": {"abs-1": {"numerator": 0, "denominator": 1, "verdict_status": "insufficient"}}},
      "ruleVersion": "criteria-v2",
      "grouping": "confirmed_anchored_episode_absolute_rule",
      "asOf": 1789667100000,
      "comparableGroups": [
        {"id": "rel-1", "title": "BTCUSDT 1h 做多 · 目标 +2% · 3 天内", "total": 20, "correct": 13, "verdictStatus": "verdict_due"},
        {"id": "rel-2", "title": "ETHUSDT 4h 只记录", "total": 4, "correct": 0, "verdictStatus": "observing"}
      ],
      "comparableProof": {"compatible_groups": {
        "rel-1": {"numerator": 13, "denominator": 20, "realization_rate": 0.65, "verdict_status": "verdict_due", "recheck": true},
        "rel-2": {"numerator": 0, "denominator": 4, "verdict_status": "observing"}
      }},
      "comparableGrouping": "confirmed_anchored_episode_relative_rule"
    }
    """)

    XCTAssertEqual(response.comparableGrouping, "confirmed_anchored_episode_relative_rule")
    XCTAssertEqual(response.resolvedGrouping, "confirmed_anchored_episode_relative_rule",
                   "界面上摆的是哪一份，口径就得报哪一份")
    let groups = response.resolvedGroups
    XCTAssertEqual(groups.map(\.id), ["rel-1", "rel-2"], "绝对口径那组一个都不该露面")
    XCTAssertEqual(groups[0].title, "BTCUSDT 1h 做多 · 目标 +2% · 3 天内")
    XCTAssertEqual(groups[0].total, 20)
    XCTAssertEqual(groups[0].correct, 13)
    XCTAssertEqual(groups[0].verdict, "verdict_due", "组里自带的 `verdictStatus` 要认")
    XCTAssertEqual(groups[0].recheck, true, "「最近十笔明显变差」在证据里，得贴回来")
    XCTAssertEqual(groups[0].rateText, "65%")
    XCTAssertEqual(groups[1].verdict, "observing")
    XCTAssertEqual(groups[1].rateText, "0%", "只记录那一档是真的 0/4，不是样本不足")
    // 老字段照旧解得出来，只是不上屏——出了事还得靠它对账。
    XCTAssertEqual(response.groups.count, 1)
    XCTAssertEqual(response.grouping, "confirmed_anchored_episode_absolute_rule")
    XCTAssertEqual(response.ruleVersion, "criteria-v2")
    XCTAssertEqual(response.asOf, 1789667100000)
  }

  /// 老服务端：没有那三个新键，照旧走 `groups` + `proof`，判定状态仍从证据里贴。
  func testTheOldShapeStillDecodesAndStillGetsItsVerdict() throws {
    let response = try decode("""
    {
      "groups": [{"id": "abs-1", "title": "BTCUSDT 1h 目标 80286.3", "total": 1, "correct": 0}],
      "proof": {"compatible_groups": {"abs-1": {"numerator": 0, "denominator": 1, "realization_rate": 0.0, "verdict_status": "insufficient", "recheck": false}}},
      "ruleVersion": "criteria-v2",
      "grouping": "confirmed_anchored_episode_absolute_rule",
      "asOf": 1789667100000
    }
    """)

    XCTAssertNil(response.comparableGroups)
    XCTAssertEqual(response.resolvedGrouping, "confirmed_anchored_episode_absolute_rule")
    let groups = response.resolvedGroups
    XCTAssertEqual(groups.map(\.id), ["abs-1"])
    XCTAssertEqual(groups[0].verdict, "insufficient")
    XCTAssertEqual(groups[0].rateText, "样本不足", "一笔一组永远不许排版成 0%")
  }

  /// 新服务端说「相对口径下还没有任何一组」：那就是空的，不许偷偷退回绝对口径那套。
  func testAnEmptyComparableListIsAnAnswerNotAFallback() throws {
    let response = try decode("""
    {
      "groups": [{"id": "abs-1", "title": "BTCUSDT 1h 目标 80286.3", "total": 1, "correct": 0}],
      "proof": {"compatible_groups": {}},
      "comparableGroups": [],
      "comparableProof": {"compatible_groups": {}},
      "comparableGrouping": "confirmed_anchored_episode_relative_rule"
    }
    """)

    XCTAssertTrue(response.resolvedGroups.isEmpty, "空列表是服务端给的答案，不是「没给」")
    XCTAssertEqual(response.resolvedGrouping, "confirmed_anchored_episode_relative_rule")
  }

  /// 证据里没写的东西不许反手把分组里已经有的抹掉。
  ///
  /// `comparableGroups[].verdictStatus` 是服务端直接带下来的；要是贴证据时无脑
  /// `value.verdict = hit.verdictStatus`，证据里恰好没这一项就把「样本不足」抹成了 nil，
  /// 界面转头又拿 0/3 排出一个 0%。
  func testProofNeverErasesWhatTheGroupAlreadyKnows() throws {
    let response = try decode("""
    {
      "groups": [],
      "comparableGroups": [{"id": "rel-1", "title": "BTCUSDT 1h 做多 · 目标 +2%", "total": 3, "correct": 0, "verdictStatus": "insufficient"}],
      "comparableProof": {"compatible_groups": {"rel-1": {"numerator": 0, "denominator": 3}}}
    }
    """)

    let group = try XCTUnwrap(response.resolvedGroups.first)
    XCTAssertEqual(group.verdict, "insufficient")
    XCTAssertEqual(group.rateText, "样本不足")
  }
}
