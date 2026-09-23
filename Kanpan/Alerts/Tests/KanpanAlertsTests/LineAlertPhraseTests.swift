import Testing
@testable import KanpanAlerts

/// 选中栏上那句「跌到 64,000 叫我」怎么拼。
///
/// 方向按线在现价上面还是下面定；好几条线（通道、矩形、回撤）只报现价两侧最近的那两条；
/// 「还差多少」只在一侧有线时写。
@Suite("画线提醒胶囊的那句话")
struct LineAlertPhraseTests {
  @Test("线在现价下面：跌到")
  func below() {
    let p = LineAlertPhrase(targets: [64_000], current: 65_152, decimals: 0)
    #expect(p.target == "跌到 64,000")
    #expect(p.distance == "还差 1.77%")
  }

  @Test("线在现价上面：涨到")
  func above() {
    let p = LineAlertPhrase(targets: [70_000], current: 65_000, decimals: 1)
    #expect(p.target == "涨到 70,000.0")
    #expect(p.distance == "还差 7.69%")
  }

  @Test("两侧都有线：各报最近的一条，不写还差多少")
  func bothSides() {
    let p = LineAlertPhrase(targets: [60_000, 63_000, 66_000, 70_000], current: 64_000, decimals: 0)
    #expect(p.target == "涨到 66,000 或跌到 63,000")
    #expect(p.distance == nil)
  }

  @Test("还没拿到现价：只说到哪个价")
  func noQuote() {
    #expect(LineAlertPhrase(targets: [64_000], current: nil, decimals: 0).target == "到 64,000")
    #expect(LineAlertPhrase(targets: [1, 2], current: nil, decimals: 0).target == "碰到这条线")
  }

  @Test("线段此刻不在（已经走完或还没开始）：不报价")
  func outOfSpan() {
    #expect(LineAlertPhrase(targets: [], current: 64_000, decimals: 0).target == "碰到这条线")
  }

  @Test("小价不插千分位，四位以上才插")
  func grouping() {
    #expect(LineAlertPhrase(targets: [0.5], current: 0.6, decimals: 4).target == "跌到 0.5000")
    #expect(LineAlertPhrase(targets: [1234.5], current: 1300, decimals: 1).target == "跌到 1,234.5")
    #expect(LineAlertPhrase(targets: [987], current: 900, decimals: 0).target == "涨到 987")
  }

  @Test("压在现价上")
  func atPrice() {
    #expect(LineAlertPhrase(targets: [64_000], current: 64_000, decimals: 0).distance == "就在现价")
  }
}
