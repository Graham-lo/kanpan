import ActivityKit
import KanpanCore

// app 与小组件扩展共用（Kanpan/KanpanShared 同时同步进两个 target）：同一个类型在两边编两次，
// ActivityKit 按类型名与编码认活动，两边字段一改一起编不过。
// 从前放在 KanpanCore，用 `#if canImport(ActivityKit)` 包着；审查 24 把系统框架请出 Core。

/// 活动的静态那一半：建的时候定死，服务端一个字都不改（`symbol` / `alertID` / `toolLabel`）。
struct AlertActivityAttributes: ActivityAttributes {
  typealias ContentState = AlertActivityState

  var symbol: String
  /// 同步对象 id（`binance/usd_m/<SYM>/<id>`），服务端按它找线、判停。
  var alertID: String
  /// 「水平线」「趋势线」「价格」这一类，锁屏上说明它盯的是什么。
  var toolLabel: String
  /// 价格按品种精度排；服务端不用这一格。
  var decimals: Int?
  /// 发起那一刻的涨跌配色（锁屏上没有皮肤可跟，只跟这一项）。
  var redUp: Bool

  init(symbol: String, alertID: String, toolLabel: String, decimals: Int?, redUp: Bool) {
    self.symbol = symbol; self.alertID = alertID; self.toolLabel = toolLabel; self.decimals = decimals
    self.redUp = redUp
  }
}
