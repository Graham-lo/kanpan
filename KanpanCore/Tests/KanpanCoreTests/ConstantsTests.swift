import Testing
@testable import KanpanCore
@Suite("共用尺寸参数") struct ConstantsTests {
  @Test func defaults() {
    #expect(AICoinBehavior.initialSpacing == 4)
    #expect(Chart.minBarSpacing == 1.6 && Chart.maxBarSpacing == 40)
    #expect(AICoinBehavior.rightInset == 0)
    #expect(Chart.hitHandlePt == Chart.hitLinePt)
  }
}
