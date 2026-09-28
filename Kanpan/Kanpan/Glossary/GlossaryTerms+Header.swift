import Foundation

// 行情页头部右侧六格的解释（`PriceRow.stats`）。「市值 / 费率 / 结算」交易员一看就懂，不挂问号
// （2026-09-28 用户：「费率，结算没必要加问号啊，很明显啊」）。
extension GlossaryTerm {
  static let openInterest = GlossaryTerm(
    id: "openInterest",
    title: "仓 · 持仓量",
    body: "现在市场上还没平掉的合约一共值多少美元。\n它在涨，说明有更多资金押注在这只上；在跌，说明有人在离场。")

  static let turnover = GlossaryTerm(
    id: "turnover",
    title: "额 · 24 小时成交额",
    body: "过去 24 小时里这只一共成交了多少美元。\n数越大，交易越活跃，买卖越容易成交。")



  static let oiToMarketCap = GlossaryTerm(
    id: "oiToMarketCap",
    title: "OI/MC · 持仓÷市值",
    body: "合约持仓量除以这个币的总市值。\n比例越高，说明合约上押的钱相对现货越多，价格越容易被合约带着大起大落。")

  static let forwardPE = GlossaryTerm(
    id: "forwardPE",
    title: "Fwd PE · 预期市盈率",
    body: "市值除以分析师预期的未来一年净利润。\n大致是按预期的赚钱速度，要多少年才能赚回现在的市值；越低越便宜。")

  static let priceToSales = GlossaryTerm(
    id: "priceToSales",
    title: "P/S · 市销率",
    body: "市值除以一年的营收。\n还没赚钱的公司没法看市盈率，就看它：越低，说明每一块钱营收被定价得越便宜。")
}
