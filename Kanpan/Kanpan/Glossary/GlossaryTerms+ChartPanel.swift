import Foundation

// 图表设置面板（`ChartPanel`）里要解释的只有「刻度」：画法、盘口是一看就懂的行业词，不挂问号。
extension GlossaryTerm {
  static let priceScale = GlossaryTerm(
    id: "priceScale",
    title: "刻度",
    body: "线性：每格代表同样多的钱。\n对数：每格代表同样的涨跌幅，看大涨大跌的长周期更公平。\n百分比：以屏幕最左边那根为 0，刻度直接写涨跌了多少 %。")
}
