import Foundation

// 复盘本（`KanpanReview` 包里的交易详情、战绩）上的解释。包里看不到 app 的 Glossary，
// 按 id 向这里要（`ReviewTheme.termMark`，由 `ReviewThemeBridge` 递过去）。
// 净盈亏、胜率、最大浮盈 / 浮亏、资金费、平均持仓这些交易员一看就懂的不挂。
extension GlossaryTerm {
  /// 复盘包按 id 要的那几条；不认得的 id 不挂。
  static func review(_ id: String) -> GlossaryTerm? {
    [rewardRisk, expectancy, feeShare, fills, realized, tradeRewardRisk, afterClose].first { $0.id == id }
  }

  static let rewardRisk = GlossaryTerm(
    id: "rewardRisk",
    title: "盈亏比",
    body: "平均每笔赚的，除以平均每笔亏的。\n大于 1 说明赚的时候比亏的时候多；胜率不高时，靠它撑住。")

  static let expectancy = GlossaryTerm(
    id: "expectancy",
    title: "每笔期望",
    body: "平均每做一笔赚（或亏）多少钱。\n为正说明这样做下去长期是赚的。")

  static let feeShare = GlossaryTerm(
    id: "feeShare",
    title: "费用占毛利",
    body: "手续费（扣掉收到的、加上付出的资金费）占平仓赚亏的比例。\n比例越高，越多的利润被费用吃掉了；毛利为负时不算。")

  static let fills = GlossaryTerm(
    id: "fills",
    title: "成交",
    body: "这一笔里每一次买卖。\n挂单：你的单先挂在簿上、被别人吃掉，手续费低。\n吃单：直接吃掉别人的挂单，成交快、手续费高。")

  static let realized = GlossaryTerm(
    id: "realized",
    title: "已实现",
    body: "平仓时交易所结算的赚亏，还没扣手续费、没算资金费。")

  static let tradeRewardRisk = GlossaryTerm(
    id: "tradeRewardRisk",
    title: "盈亏比 · 这一笔",
    body: "这一笔的净盈亏，除以持仓期间最大浮亏。\n数越大，说明担的风险换来的回报越多。")

  static let afterClose = GlossaryTerm(
    id: "afterClose",
    title: "离开后",
    body: "平仓之后 1、4、24 小时，价格比你的平仓价又走了多少。\n用来看是走早了，还是躲过了一段。")
}
