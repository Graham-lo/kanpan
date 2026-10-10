import Foundation
import KanpanCore

// MARK: - 指标布局：一人一份，不分周期（2026-10-03）
//
// 一份「布局」是主图指标与参数、副图指标与参数、副图高度、K 线画法、价格轴类型。
// **它跟人走，任何周期都是同一份**：在 1 小时换了指标、调了副图顺序和高度，切到 4 小时、日线
// 看到的就是刚调的那份；同一账号的手机网页版、电脑网页版、iPad 改了也经云端互相生效。
//
// 2026-09-27 到 10-02 这里做过「周期分组记忆」（分钟 / 小时 / 日线三组各记一份，继承直到分叉）。
// 10-03 用户在网页版上「在一小时周期调整了指标区域大小和顺序，切换周期发现又被改回去了」，
// 随后把规矩说死：「应该是通用的啊，不管什么周期」——分组整套拆掉，删除前的代码在
// tag `before-remove-interval-indicator-groups-2026-10-03`。
//
// 当时还留了一段「读老档」：老档（与老客户端写在云端的）`indicatorLayouts = {minute?, hour?, day?}`
// 里的分叉取当前周期那组当唯一那份，存档写空表、云端残留的分叉发 null 清掉。2026-10-10 那个键三端退役
// （10-03 之前的老客户端已经没了，手机与网页都装着最新版），这段迁移连同 `Prefs.indicatorLayouts`
// 一起删掉：老存档里的那个键解码时忽略，云端残留由服务端 `strip_retired` 洗掉。删除前的代码在
// tag `sync-fields-before-retire-2026-10-10`。

/// 一份指标布局（就是 `Prefs` 顶层那六项）。
struct IndicatorLayout: Sendable, Equatable {
  var overlays: [IndicatorID]
  var subs: [IndicatorID]
  var params: [IndicatorID: [Int]]
  var subHeightOverrides: [IndicatorID: Double]
  var candleKind: CandleKind
  var priceMode: PriceMode

  /// 出厂那一份（「恢复默认指标」回到的就是它）。
  static var factory: IndicatorLayout { Prefs.defaults.indicatorLayout }

  /// 落盘前夹一道，和 `PrefsCodec.sanitized` 对其余字段做的一样。
  var sanitized: IndicatorLayout {
    var l = self
    // 副图名额和读档同一把尺子：成交量不占，别的最多三个（`Prefs.cappedSubs`）。
    l.subs = Prefs.cappedSubs(l.subs)
    l.subHeightOverrides = l.subHeightOverrides.compactMapValues { $0.isFinite ? min(SubPaneResize.maximumScale, max(SubPaneResize.minimumScale, $0)) : nil }
    return l
  }
}

extension Prefs {
  /// 这个人的指标布局（就是顶层那六项）。
  var indicatorLayout: IndicatorLayout {
    get {
      IndicatorLayout(overlays: overlays, subs: subs, params: params,
                      subHeightOverrides: subHeightOverrides, candleKind: candleKind, priceMode: priceMode)
    }
    set {
      overlays = newValue.overlays; subs = newValue.subs; params = newValue.params
      subHeightOverrides = newValue.subHeightOverrides
      candleKind = newValue.candleKind; priceMode = newValue.priceMode
    }
  }
}
