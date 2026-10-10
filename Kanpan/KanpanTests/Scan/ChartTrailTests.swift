import Testing
@testable import Kanpan

// 走进这张图的那条路（来路 + 扫图名单）什么时候留着、什么时候作废。

@Suite("走进图的来路与扫图名单")
struct ChartTrailTests {

  private func entered() -> ChartTrail {
    var trail = ChartTrail()
    trail.entered(from: .favorites)
    trail.scan = ScanList(["binance/usd_m/BTCUSDT", "binance/usd_m/ETHUSDT", "binance/usd_m/SOLUSDT"])
    return trail
  }

  @Test("从别的一格走进图记下来路；本来就在图上不算来路")
  func recordsOriginOnlyFromOtherTabs() {
    var trail = ChartTrail()
    trail.entered(from: .chart)
    #expect(trail.origin == nil)
    trail.entered(from: .home)
    #expect(trail.origin == .home)
  }

  @Test("行情页上再点「图表」只回到最新：来路和名单都留着（9414f44b）")
  func retappingChartKeepsTheTrail() {
    var trail = entered()
    let before = trail
    trail.tapped(.chart, on: .chart)
    #expect(trail == before)
  }

  @Test("底栏点别的一格（或在别处点「图表」）就是回家：来路和名单一起作废")
  func tappingAnotherTabForgetsTheTrail() {
    var trail = entered()
    trail.tapped(.me, on: .chart)
    #expect(trail == ChartTrail())
    trail = entered()
    trail.tapped(.chart, on: .favorites)
    #expect(trail == ChartTrail())
  }

  @Test("换了号 / 退登 / 被顶下线：上一个人的扫图名单和来路不能留着")
  func ownerSwitchForgetsTheTrail() {
    var trail = entered()
    trail.ownerSwitched(settled: true)
    #expect(trail.scan == nil)
    #expect(trail.origin == nil)
    // 作废之后再横滑什么都不发生。
    #expect((trail.scan?.step(from: "binance/usd_m/ETHUSDT", .next) ?? .unavailable) == .unavailable)
  }

  @Test("冷启动里同一个人的档案晚到不是换人：来路和名单原样留着")
  func lateProfileOfTheSamePersonKeepsTheTrail() {
    var trail = entered()
    let before = trail
    trail.ownerSwitched(settled: false)
    #expect(trail == before)
  }
}
