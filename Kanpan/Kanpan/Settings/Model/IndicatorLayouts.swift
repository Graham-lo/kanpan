import Foundation
import KanpanCore

// MARK: - 指标按周期分组记忆（2026-09-27，方案 §4）
//
// 周期分三组：分钟组（1m…30m）、小时组（1h…12h）、日组（1d 起）。一组的「布局」是
// 主图指标与参数、副图指标与参数、隐藏输出、副图高度、K 线画法、价格轴类型——
// 皮肤、网格、价格线这些显示项跟人不跟周期，不在里面。
//
// 规则是**继承直到分叉**：三组起初共用一份（新装、老档案都是：老档案里那一份就是共同源）；
// 用户在某一组里改了任一项，那一组才分出自己的一份，别的组照旧共用。没改过的人看不到任何变化。
//
// ## 内存里长什么样
//
// 读指标的地方很多（图、面板、复盘、分享……），它们一律读 `Prefs` 顶层那几项
// （`overlays` / `subs` / `params` / …）。所以顶层那几项永远是**当前周期所在组**的那一份，
// 其余两组放在 `Prefs.indicatorLayouts` 里：
//
// - 当前组没分叉：顶层那几项就是共用的那份，`shared` 为 nil（不另存一遍）。
// - 当前组分叉了：顶层那几项是这一组自己的，`shared` 存着共用的那份。
// - `others`：当前组以外、已经分叉的组各自那一份。
//
// 这样一份 JSON 只对应一种内存形状（换周期由 `settleIndicatorLayouts(after:)` 重新投影），
// 直接改顶层字段的老代码和老测试照旧成立。
//
// ## 落盘 / 线上长什么样
//
// - 老键（`overlays` / `subs` / `params` / `subHeightOverrides` /
//   `candleKind` / `priceMode`）写**共用的那份**：老客户端只认这一份，照旧同步；它就是迁移源。
// - 新键 `indicatorLayouts` = `{minute?, hour?, day?}`，只写分了叉的组，每组一个对象，
//   对象里是同名的那六个键（2026-09-28 前还有 `hiddenOutputs`，老档里读时忽略）、值的写法和顶层一样。线上拍平成 `indicatorLayouts/<组>`，
//   `null` 就是「这一组回到共用」。

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

  /// 这一组第一次分叉时浮的那句话（每组只说一次：分叉是单向的，只有「恢复出厂」会并回去）。
  var forkNotice: String {
    switch self {
    case .minute: "分钟周期的指标现在单独记"
    case .hour: "小时周期的指标现在单独记"
    case .day: "日线及以上的指标现在单独记"
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

  /// 出厂那一份（「恢复这一组的默认」回到的就是它）。
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

/// 三组的全貌：共用的一份 + 分了叉的组各自那份。
struct IndicatorLayoutBook: Sendable, Equatable {
  var shared: IndicatorLayout
  var forks: [IntervalGroup: IndicatorLayout] = [:]

  func layout(for group: IntervalGroup) -> IndicatorLayout { forks[group] ?? shared }
  func isForked(_ group: IntervalGroup) -> Bool { forks[group] != nil }
}

/// `Prefs` 上存的那一格：当前组以外的记忆。形状见文件头。
struct IndicatorLayoutMemory: Sendable, Equatable {
  /// 当前组分了叉时，共用的那一份；当前组没分叉时为 nil（共用的就是顶层那份）。
  var shared: IndicatorLayout?
  /// 当前组以外、已经分叉的组。
  var others: [IntervalGroup: IndicatorLayout] = [:]
}

extension Prefs {
  /// 当前周期所在组的布局（就是顶层那六项）。
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

  /// 这一组分叉了没有。
  func isLayoutForked(_ group: IntervalGroup) -> Bool { layoutBook.isForked(group) }

  /// 一次改动（`before` → 现在这份）之后把分组记忆理顺。`PrefsStore` 的每一条改法都过这里。
  ///
  /// - 顶层那几项被改了：改的是**改完之后周期所在的那一组**（只改指标时就是当前组；
  ///   同一下里既换了组又写了指标，写下的那份就是新组的——调用方要看到的正是它）。
  ///   那一组原来还是共用的，就此分叉；共用的那份保持原样，别的组不受牵连。
  /// - 只换了周期、跨了组：顶层换成新组那份——和换周期是同一次赋值，图在同一帧拿到新布局。
  /// - 调用方连 `indicatorLayouts` 一起写了（整份换成另一份 `Prefs`、撤销还原）：
  ///   那份就是答案，只按现在的周期重新投影，不另算分叉。
  ///
  /// - Returns: 这一下新分叉出来的组（调用方拿它说一句 `forkNotice`），没有就是 nil。
  @discardableResult
  mutating func settleIndicatorLayouts(after before: Prefs) -> IntervalGroup? {
    guard indicatorLayouts == before.indicatorLayouts else {
      adopt(layoutBook)
      return nil
    }
    var book = before.layoutBook
    let group = layoutGroup
    var forked: IntervalGroup?
    if indicatorLayout != before.indicatorLayout, indicatorLayout != book.layout(for: group) {
      if !book.isForked(group) { forked = group }
      book.forks[group] = indicatorLayout
    }
    adopt(book)
    return forked
  }
}
