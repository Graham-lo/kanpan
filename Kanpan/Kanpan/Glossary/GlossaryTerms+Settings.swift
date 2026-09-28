import Foundation

// 设置页（行情 · 通知 · 通用）上的解释。涨跌色、外观、铃声、上新下架一看就懂，不挂。
extension GlossaryTerm {
  static let route = GlossaryTerm(
    id: "route",
    title: "线路 · 行情从哪来",
    body: "直连：手机自己直接连交易所，出厂就是它。\n网关：经我们的服务器转一道，手机连不上交易所时用。\n选了哪条就一直走哪条，不会自己切换。")

  static let watchMove = GlossaryTerm(
    id: "watchMove",
    title: "波动提醒",
    body: "自选里的品种短时间内涨跌得特别快时，发一条通知。\n多快才算快按每只自己平时的波动自动定，不用自己填。")

  static let habits = GlossaryTerm(
    id: "habits",
    title: "自动适应",
    body: "按你平时怎么用来调默认：每只品种常看的周期、各类品种用对数还是线性刻度、板块页看今日还是 5 日、波动提醒的灵敏度。\n学到的都列在「已学到的」里；关掉立刻回到出厂设置。")
}
