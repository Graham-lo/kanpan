import KanpanCore

// 分析面板（`IndicatorPanel`）指标行上的解释。
// 判据（用户 2026-09-28）：只给「看合约行情的交易员读不出指什么」的词挂问号——缩到一两个字的、
// 自造或不常见的短名。均线、布林带、指数均线、平滑异同、相对强弱、随机指标、动向指标、超级趋势、
// 主力订单流这类行业标准名一律不挂，问号一多整行就花了。退役的随机强弱、真实波幅不在面板上。
extension GlossaryTerm {
  /// 面板那一行挂哪一条；nil = 不挂。
  static func indicator(_ id: IndicatorID) -> GlossaryTerm? {
    switch id {
    case .ma, .vol, .oi, .srsi, .atr, .ema, .boll, .supertrend, .orderFlow, .macd, .rsi, .kdj, .dmi: nil
    case .vwap: .vwap
    case .sar: .sar
    case .lsr: .longShortRatio
    case .taker: .takerRatio
    case .basis: .basis
    case .cvd: .cvd
    }
  }

  static let vwap = GlossaryTerm(
    id: "vwap",
    title: "均价线 · 当日 VWAP",
    body: "从当天起点（上海时间 8 点）算起，按成交量加权的平均成交价。\n价格在它上方，说明今天进场的人多数在赚；在下方则多数在亏。")

  static let sar = GlossaryTerm(
    id: "sar",
    title: "抛物线 · SAR",
    body: "一串跟着价格走的点，趋势走得越久，点追得越紧。\n点在 K 线下方看涨、在上方看跌；价格碰到点，点就翻到另一边。")

  static let orderFlowThreshold = GlossaryTerm(
    id: "orderFlowThreshold",
    title: "门槛",
    body: "挂单金额超过这个数才画到图上。\n现货、合约各有一个，按品种给好了默认值，也可以自己改。")

  static let orderFlowStep = GlossaryTerm(
    id: "orderFlowStep",
    title: "步长",
    body: "相邻这么多美元以内的挂单先并成一档，再和门槛比。\n步长越大，零散的挂单越容易并成一堵墙。")

  static let longShortRatio = GlossaryTerm(
    id: "longShortRatio",
    title: "多空比",
    body: "币安上持有多单的账户数除以持有空单的账户数。\n大于 1 是做多的人多；一边倒得太厉害时，行情常往反方向走。")

  static let takerRatio = GlossaryTerm(
    id: "takerRatio",
    title: "买卖比 · 主动买卖比",
    body: "主动买入的量除以主动卖出的量（主动 = 直接吃掉别人挂单的一方）。\n大于 1 说明买方更急着进场，小于 1 说明卖方更急着走。")

  static let basis = GlossaryTerm(
    id: "basis",
    title: "基差",
    body: "合约价格比现货指数高出多少，按百分比画。\n为正说明合约比现货贵、市场偏乐观；为负则偏悲观。")

  static let cvd = GlossaryTerm(
    id: "cvd",
    title: "量差 · 累计成交量差",
    body: "每根 K 线里主动买减主动卖，从当天起点一路累加。\n线往上走，这一段是被买上去的；往下走，是被卖下去的。")
}
