import ActivityKit
import KanpanCore
import SwiftUI
import WidgetKit

/// 提醒「盯一个」的锁屏 / 灵动岛（P3.3）。
///
/// 显示：品种、现价、24 小时涨跌幅、离提醒价多远。过了 `staleDate`（服务端每拍设成
/// 「此刻 + 150 秒」，app 前台自己更新时同样设）系统把 `isStale` 置真，这时写「价格已停更」，
/// 不再让一个冻住的数字看着像新的。
struct AlertLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: AlertActivityAttributes.self) { context in
      AlertActivityLockView(context: context)
        .activityBackgroundTint(nil)
        .widgetURL(URL(string: "hkline://symbol/\(context.attributes.symbol)"))
    } dynamicIsland: { context in
      let state = context.state
      let tone = activityTone(state.change, redUp: context.attributes.redUp)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(Alert.base(of: context.attributes.symbol)).font(.system(size: 15, weight: .semibold))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(priceText(state.price, context.attributes.decimals))
            .font(.system(size: 15, weight: .semibold).monospacedDigit())
            .foregroundStyle(tone)
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(state.changeLabel).foregroundStyle(tone)
            Spacer()
            Text(context.isStale ? "价格已停更" : statusText(state, context.attributes))
          }
          .font(.system(size: 13, weight: .medium).monospacedDigit())
        }
      } compactLeading: {
        Text(Alert.base(of: context.attributes.symbol)).font(.system(size: 12, weight: .semibold))
      } compactTrailing: {
        Text(context.isStale ? "停更" : state.distanceLabel)
          .font(.system(size: 12, weight: .medium).monospacedDigit())
          .foregroundStyle(tone)
      } minimal: {
        Text(Alert.base(of: context.attributes.symbol).prefix(3)).font(.system(size: 11, weight: .semibold))
      }
      .widgetURL(URL(string: "hkline://symbol/\(context.attributes.symbol)"))
    }
  }
}

private func priceText(_ price: Double?, _ decimals: Int?) -> String {
  guard let price else { return "--" }
  return ReviewLabels.price(price, decimals: decimals)
}

/// 锁屏那一块没有皮肤可跟（系统给的是半透明底），涨跌色取 AICoin 那一套，按发起时的
/// 涨跌配色对调。
private func activityTone(_ change: Double?, redUp: Bool) -> Color {
  guard let change, change != 0 else { return .secondary }
  let rising = change > 0
  let hex = rising == redUp ? Palette.aicoinDayDown.value : Palette.aicoinDayUp.value
  return Color(widgetHex: hex)
}

private func statusText(_ state: AlertActivityState, _ attributes: AlertActivityAttributes) -> String {
  if state.fired {
    return "已触发 " + priceText(state.firedPrice ?? state.price, attributes.decimals)
  }
  return "离提醒价 " + state.distanceLabel
}

struct AlertActivityLockView: View {
  var context: ActivityViewContext<AlertActivityAttributes>

  var body: some View {
    let state = context.state
    let attributes = context.attributes
    let tone = activityTone(state.change, redUp: attributes.redUp)
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(Alert.base(of: attributes.symbol)).font(.system(size: 16, weight: .semibold))
        Text(attributes.toolLabel).font(.system(size: 12)).foregroundStyle(.secondary)
      }
      Spacer(minLength: 8)
      VStack(alignment: .trailing, spacing: 3) {
        if context.isStale {
          Text("价格已停更").font(.system(size: 16, weight: .semibold)).foregroundStyle(.secondary)
        } else {
          HStack(spacing: 8) {
            Text(priceText(state.price, attributes.decimals))
              .font(.system(size: 18, weight: .semibold).monospacedDigit())
            Text(state.changeLabel).font(.system(size: 13, weight: .medium).monospacedDigit())
          }
          .foregroundStyle(tone)
        }
        Text(statusText(state, attributes))
          .font(.system(size: 12, weight: .medium).monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
