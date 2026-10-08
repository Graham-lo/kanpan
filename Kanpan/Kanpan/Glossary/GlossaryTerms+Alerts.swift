import Foundation

// 创建提醒页（`AlertForm`）上的解释。
extension GlossaryTerm {
  static let alertCondition = GlossaryTerm(
    id: "alertCondition",
    title: "条件",
    body: "价格达到：盘中价格一碰到就响。\n收盘穿过：要等 K 线收盘、收盘价越过这个价才响，盘中来回插针不算。\n资金费率、持仓量、MA、大单墙这几样由服务器盯着，登录后才有。")

  static let webhook = GlossaryTerm(
    id: "webhook",
    title: "网络回调",
    body: "提醒响的时候，往你填的这个网址发一条消息（也叫 Webhook），内容是一句提醒文字，格式由我们定好。\n可以接到自己的机器人或群里；点「发一条测试」先试一下。")
}
