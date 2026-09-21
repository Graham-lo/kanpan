import Foundation
import Testing
@testable import KanpanCore

/// 持仓量副图空着时那句话。
///
/// 这一组用例是为了钉死一件事：界面**不许替交易所下断言**。
/// 归档站从 2020-09-01 起给全量持仓量，所以「这个周期币安不提供持仓量历史」
/// 这句话在任何周期上都不该再出现——1w / 1M / 1y 画得出来，1m / 3m 也画得出来
/// （源是五分钟一条，图上是一条横着走五根的阶梯）。
@Suite("持仓量提示：只说自己知道的，不替币安下断言")
struct OINoticeTests {

  @Test("线路不报 / 还没到 / 真没有，三句各归各")
  func threeCases() {
    #expect(OINotice.forEmptyPane(routeSupportsOI: false, loaded: false) == .routeMissing)
    #expect(OINotice.forEmptyPane(routeSupportsOI: false, loaded: true) == .routeMissing)
    #expect(OINotice.forEmptyPane(routeSupportsOI: true, loaded: false) == .loading)
    #expect(OINotice.forEmptyPane(routeSupportsOI: true, loaded: true) == .empty)
  }

  @Test("哪个周期都不会被说成『不提供持仓量历史』", arguments: Interval.allCases)
  func noIntervalIsDeclaredUnsupported(interval: Interval) {
    // 提示根本不看周期——这正是重点：从前那句话挂在「指标还没算出来」上，
    // 却写成了周期的锅。现在无论哪个周期，三句里没有一句提交易所不给历史。
    for loaded in [true, false] {
      let text = OINotice.forEmptyPane(routeSupportsOI: true, loaded: loaded).text
      #expect(!text.contains("不提供"), "\(interval.rawValue) → \(text)")
      #expect(!text.contains("币安"), "\(interval.rawValue) → \(text)")
      #expect(!text.contains("这个周期"), "\(interval.rawValue) → \(text)")
      #expect(!text.contains("30 天"), "\(interval.rawValue) → \(text)")
    }
  }

  @Test("唯一一句『不提供』说的是线路，不是周期、不是交易所")
  func theOnlyRefusalIsAboutTheRoute() {
    let refusing = OINotice.allCases.filter { $0.text.contains("不提供") }
    #expect(refusing == [.routeMissing])
    #expect(OINotice.routeMissing.text == "当前行情线路不提供持仓量")
  }

  @Test("三句都是中文，没有 OI 这类英文缩写")
  func chineseOnly() {
    for notice in OINotice.allCases {
      #expect(!notice.text.contains("OI"))
      #expect(notice.text.contains("持仓量"))
    }
  }

  @Test("图例与输出开关上也不出现英文缩写")
  func legendLabelIsChinese() {
    #expect(IndicatorID.oi.name == "持仓量")
    #expect(IndicatorID.oi.lineNames(params: []) == ["持仓量"])
  }
}
