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
// 留下来的只有「读老档」：老档（与老客户端写在云端的）`indicatorLayouts = {minute?, hour?, day?}`
// 里可能还有分叉。读进来时取**当前周期所在组**那一份当作唯一那份（那是用户此刻正看着的），
// 其余一律丢掉；`Prefs.indicatorLayouts` 从此永远是空的，存档与线上写 `{}`，
// 云端残留的 `indicatorLayouts/<组>` 在下一次推送时发 `null` 清掉（`PersonalSyncCodec.ownedKeys`）。

/// 周期分组。`rawValue` 是存档与线上的键名，和服务端 `sync_validation.rs` 逐字相同。
enum IntervalGroup: String, CaseIterable, Sendable, CodingKey {
  case minute, hour, day

  init(_ interval: Interval) {
    switch interval {
    case .m1, .m3, .m5, .m15, .m30: self = .minute
    case .h1, .h2, .h4, .h6, .h12: self = .hour
    case .d1, .w1, .mo1, .y1: self = .day
    }
  }
}

extension Interval {
  var layoutGroup: IntervalGroup { IntervalGroup(self) }
}

/// 一组的布局。
struct IndicatorLayout: Sendable, Equatable {
  var overlays: [IndicatorID]
  var subs: [IndicatorID]
  var params: [IndicatorID: [Int]]
  var subHeightOverrides: [IndicatorID: Double]
  var candleKind: CandleKind
  var priceMode: PriceMode

  /// 出厂那一份（「恢复默认指标」回到的就是它）。
  static var factory: IndicatorLayout { Prefs.defaults.indicatorLayout }

  /// 落盘前夹一道，和 `PrefsCodec.sanitized` 对顶层那份做的一样。
  var sanitized: IndicatorLayout {
    var l = self
    // 副图名额和读档同一把尺子：成交量不占，别的最多三个（`Prefs.cappedSubs`）。
    l.subs = Prefs.cappedSubs(l.subs)
    l.subHeightOverrides = l.subHeightOverrides.compactMapValues { $0.isFinite ? min(2, max(0.5, $0)) : nil }
    return l
  }
}

/// 老档里三组的全貌：共用的一份 + 分了叉的组各自那份（只为读老档）。
struct IndicatorLayoutBook: Sendable, Equatable {
  var shared: IndicatorLayout
  var forks: [IntervalGroup: IndicatorLayout] = [:]

  func layout(for group: IntervalGroup) -> IndicatorLayout { forks[group] ?? shared }
  func isForked(_ group: IntervalGroup) -> Bool { forks[group] != nil }
}

/// `Prefs` 上存的那一格：老档里当前组以外的分叉。读档与 `settleIndicatorLayouts` 之后永远是空的，
/// 只在「读老档、装云端老客户端写的那份」那一瞬间非空。
struct IndicatorLayoutMemory: Sendable, Equatable {
  /// 当前组分了叉时，共用的那一份；当前组没分叉时为 nil（共用的就是顶层那份）。
  var shared: IndicatorLayout?
  /// 当前组以外、已经分叉的组。
  var others: [IntervalGroup: IndicatorLayout] = [:]
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

  /// 当前周期所在组。
  var layoutGroup: IntervalGroup { interval.layoutGroup }

  /// 三组全貌。
  var layoutBook: IndicatorLayoutBook { layoutBook(activeGroup: layoutGroup) }

  /// 把顶层那份当成 `group` 那一组来读出三组全貌（换周期那一下，顶层还是旧组的）。
  func layoutBook(activeGroup group: IntervalGroup) -> IndicatorLayoutBook {
    var forks = indicatorLayouts.others
    forks[group] = nil
    guard let shared = indicatorLayouts.shared else { return IndicatorLayoutBook(shared: indicatorLayout, forks: forks) }
    forks[group] = indicatorLayout
    return IndicatorLayoutBook(shared: shared, forks: forks)
  }

  /// 按当前周期把三组全貌装回来：顶层换成当前组那份，其余进记忆。
  mutating func adopt(_ book: IndicatorLayoutBook) {
    let group = layoutGroup
    indicatorLayout = book.layout(for: group)
    var others = book.forks
    others[group] = nil
    indicatorLayouts = IndicatorLayoutMemory(shared: book.isForked(group) ? book.shared : nil, others: others)
  }

  /// 一次改动（`before` → 现在这份）之后把指标布局收拢成一份。`PrefsStore` 的每一条改法都过这里。
  ///
  /// - 调用方连 `indicatorLayouts` 一起写了（整份换成另一份 `Prefs`、撤销还原、老档）：
  ///   取当前周期所在组那一份当作唯一那份。
  /// - 其余情况（改指标、换周期）：顶层那份就是答案，换周期不换指标。
  mutating func settleIndicatorLayouts(after before: Prefs) {
    if indicatorLayouts != before.indicatorLayouts { adopt(layoutBook) }
    collapseIndicatorLayouts()
  }

  /// 只留顶层那一份，老档的分叉丢掉。
  mutating func collapseIndicatorLayouts() {
    if indicatorLayouts != IndicatorLayoutMemory() { indicatorLayouts = IndicatorLayoutMemory() }
  }
}
