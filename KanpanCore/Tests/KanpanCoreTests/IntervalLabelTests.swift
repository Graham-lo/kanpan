import Testing
@testable import KanpanCore

/// 周期的中文短写（审查 U12）：周期条、横屏周期栏、「更多」网格、复盘本共用这一份。
@Suite("周期短写") struct IntervalLabelTests {
  @Test func everyIntervalHasItsOwnShortLabel() {
    let labels = Interval.allCases.map(\.shortLabel)
    #expect(Set(labels).count == Interval.allCases.count, "有两档写成了同一个样子：\(labels)")
    #expect(labels == ["1分", "3分", "5分", "15分", "30分", "1时", "2时", "4时", "6时", "12时",
                       "1日", "1周", "1月", "1年"])
  }

  /// 以前 `1m` 和 `1M` 只差一个大小写；短写之后不许再靠大小写区分任何两档。
  @Test func noTwoLabelsDifferOnlyByCase() {
    let folded = Interval.allCases.map { $0.shortLabel.lowercased() }
    #expect(Set(folded).count == Interval.allCases.count)
    #expect(Interval.m1.shortLabel != Interval.mo1.shortLabel)
  }

  /// 复盘记录里存的是原始字符串：认得的换短写，认不得的原样给回去。
  @Test func rawStringFallsBackToItself() {
    #expect(Interval.shortLabel(raw: "1h") == "1时")
    #expect(Interval.shortLabel(raw: "1M") == "1月")
    #expect(Interval.shortLabel(raw: "8h") == "8h")
  }
}
