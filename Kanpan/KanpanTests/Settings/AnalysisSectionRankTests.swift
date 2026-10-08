import Foundation
import Testing

@testable import Kanpan

/// 「分析」面板四节按使用频率排（2026-10-08）：出厂 画线 → 主力订单流 → 指标 → 对比，
/// 用过的按次数排、同次数按出厂序，总数过 256 整体减半；次数表的清洗规则和服务端值规则对齐。
@Suite struct AnalysisSectionRankTests {

  @Test("没用过：画线 → 主力订单流 → 指标 → 对比，四节一个不少")
  func defaultOrder() {
    #expect(AnalysisSectionRank.order(usage: [:]) == [.draw, .orderFlow, .indicators, .compare])
    #expect(Set(AnalysisSectionRank.defaultOrder) == Set(AnalysisSection.allCases))
    #expect(AnalysisSection.allCases.map(\.rawValue) == ["draw", "orderFlow", "indicators", "compare"],
            "键名三端一致、随账号同步，不许改名")
  }

  @Test("按次数从多到少，没用过的按出厂序补在后面")
  func byCounts() {
    #expect(AnalysisSectionRank.order(usage: ["compare": 9, "indicators": 4]) == [.compare, .indicators, .draw, .orderFlow])
    #expect(AnalysisSectionRank.order(usage: ["orderFlow": 1]) == [.orderFlow, .draw, .indicators, .compare])
  }

  @Test("次数一样按出厂序")
  func tiesFollowDefault() {
    #expect(AnalysisSectionRank.order(usage: ["compare": 3, "draw": 3, "indicators": 3]) == [.draw, .indicators, .compare, .orderFlow])
  }

  @Test("认不出的键、0 和负数不算数")
  func junkIgnored() {
    #expect(AnalysisSectionRank.order(usage: ["laser": 99, "compare": 0, "indicators": -4]) == AnalysisSectionRank.defaultOrder)
  }

  @Test("记一次 +1；认不出的键、0 次顺手丢掉")
  func countedAddsOne() {
    #expect(AnalysisSectionRank.counted([:], .orderFlow) == ["orderFlow": 1])
    #expect(AnalysisSectionRank.counted(["orderFlow": 2, "laser": 5, "draw": 0], .orderFlow) == ["orderFlow": 3])
  }

  @Test("总数过 256 整体减半，减成 0 的删掉")
  func decay() {
    let usage = ["draw": 200, "indicators": 56, "compare": 1]
    // 加一次 compare 之后总数 258 > 256，整体减半：100 / 28 / 1，compare 2→1
    #expect(AnalysisSectionRank.counted(usage, .compare) == ["draw": 100, "indicators": 28, "compare": 1])
    let tiny = ["draw": 255, "orderFlow": 1]
    // 255 + 1 + 1 = 257 → 127 / 1（orderFlow 2→1）
    #expect(AnalysisSectionRank.counted(tiny, .orderFlow) == ["draw": 127, "orderFlow": 1])
    let drops = ["draw": 256, "compare": 1]
    // 256 + 1 + 1(draw) → draw 257→128，compare 1→0 删掉
    #expect(AnalysisSectionRank.counted(drops, .draw) == ["draw": 128])
  }

  @Test("cleanAnalysisUsage：只认四节、次数 > 0、夹到上限、最多四个键")
  func clean() {
    #expect(Prefs.cleanAnalysisUsage(["draw": 5, "laser": 3, "compare": 0, "orderFlow": -1]) == ["draw": 5])
    #expect(Prefs.cleanAnalysisUsage(["indicators": 500_000]) == ["indicators": Prefs.maxDrawToolUsageCount])
    let all = ["draw": 1, "orderFlow": 2, "indicators": 3, "compare": 4]
    #expect(Prefs.cleanAnalysisUsage(all) == all)
    #expect(Prefs.maxAnalysisUsageKeys == 4)
    #expect(Prefs.defaults.analysisUsage.isEmpty)
  }
}
