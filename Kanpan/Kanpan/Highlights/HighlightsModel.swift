import CoreGraphics
import Foundation
import KanpanCore

/// 图上画的那一条「要点」带子：价区（横带）或时段（竖带），带一枚小标签。
struct HighlightBand: Equatable {
  enum Kind: Equatable {
    /// 图上那只品种的价格（已乘缩放）。
    case price(low: Double, high: Double)
    case span(from: Int64, to: Int64)
  }
  var kind: Kind
  var label: String
  /// 这条带子出自哪一条要点（价位 id / 事件 id）：再点同一条就收掉。
  var sourceID: String
  /// 首页定位标记也服从「分析」里的挂单墙 / 大单标记开关。
  enum Display: Equatable { case walls, signs }
  var display: Display = .walls

  func isVisible(walls: Bool, signs: Bool) -> Bool {
    switch display { case .walls: walls; case .signs: signs }
  }
}

/// 行情页点击「盘口要点」（PROJECT.md §79）：一只品种的那份答复 + 半页开关、展开了哪个价位、图上画哪条带子。
///
/// 轮询挂在入口条的 `.task(id:)` 上：入口条在（行情页、竖屏、非复盘非画线）才拉，半页开着 30 秒一轮、
/// 关着 60 秒一轮；换品种（base 变）清掉旧答复、收起半页，首页点进来的那一条（`pending`）例外。
@MainActor
@Observable
final class HighlightsModel {
  typealias Fetch = @MainActor (String) async -> HighlightsPage?

  /// 首页点一行带进来的：到了这只的答复就展开那一条、画带子，并按需自动升起半页。
  struct Pending: Equatable {
    var base: String
    var focusID: String?
    var autoOpen: Bool
  }

  private(set) var page: HighlightsPage?
  private(set) var base: String?
  private(set) var loading = false
  /// 最近一次没取到（断网、服务端不通）。有旧答复时照旧摆着、按「数据停了」灰显。
  private(set) var failed = false
  /// 半页开着吗。
  var open = false
  /// 半页那一档的高度：屏高 − 行情头下沿（`HighlightsHeaderGuard` 量）− 系统 sheet 自己多出的那一截。
  var sheetHeight: CGFloat { max(0, screenHeight - headerBottom - sheetSlack) }
  private(set) var headerBottom: CGFloat = 0
  @ObservationIgnored private var screenHeight: CGFloat = 0
  /// 系统 sheet 按 `.height(h)` 摆出来的实际顶边和要的差多少（iOS 26 的浮动 sheet 会多出十几 pt）：
  /// 半页停稳后量一次自己的顶边，差多少补多少，之后每次打开都照这个数。
  private(set) var sheetSlack: CGFloat = 0
  @ObservationIgnored private var settleTask: Task<Void, Never>?

  func noteHeader(bottom: CGFloat, screen: CGFloat) {
    screenHeight = screen
    if abs(bottom - headerBottom) > 0.5 { headerBottom = bottom }
  }

  /// 半页自己的顶边（全局坐标）。动画里一路在变，停 0.4 秒不动才算数。
  func noteSheetTop(_ top: CGFloat) {
    settleTask?.cancel()
    settleTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard let self, !Task.isCancelled, self.open, self.headerBottom > 0 else { return }
      let gap = self.headerBottom - top
      if abs(gap) > 1, abs(gap) < 80 { self.sheetSlack += gap }
    }
  }
  /// 展开的那个价位。
  private(set) var expanded: String?
  /// 图上那条带子。
  private(set) var band: HighlightBand?
  /// 半页要滚到哪一条（首页点进来时）。
  private(set) var scrollTarget: String?
  @ObservationIgnored private(set) var pending: Pending?

  /// 现在这只的缩放（1000PEPE 为 1000）与价格位数：拼字和画带子都要。
  @ObservationIgnored var scale: Double = 1
  @ObservationIgnored var decimals: Int?

  /// 数据停了：服务端说停了，或者这一轮没取到而手里是旧的。
  var stale: Bool { page.map { $0.staleMs != nil || failed } ?? false }

  /// 「数据停于 HH:MM」用的那一刻。
  var stoppedAtMs: Int64? {
    guard let page, stale else { return nil }
    return page.generatedAtMs - (page.staleMs ?? 0)
  }

  /// 首页点进来：记下要展开哪一条，等这只的答复到了再落。
  func expect(base: String, focusID: String?, autoOpen: Bool) {
    pending = Pending(base: base, focusID: focusID, autoOpen: autoOpen)
    if self.base == base, page != nil { consumePending() }
  }

  /// 拉一轮、睡一轮，直到任务被取消（入口条消失、换了 base、半页开关变了）。
  func poll(base: String, fetch: Fetch) async {
    if self.base != base {
      self.base = base
      page = nil; failed = false; expanded = nil; band = nil; scrollTarget = nil
      if pending?.base != base { pending = nil; open = false }
    }
    loading = page == nil
    while !Task.isCancelled {
      let next = await fetch(base)
      guard !Task.isCancelled, self.base == base else { return }
      if let next, next.base == base {
        page = next; failed = false
        if pending?.base == base { consumePending() }
        // 展开的价位这一轮没了（被吃穿、出了范围）：收起，带子跟着撤。
        if let id = expanded, !next.levels.contains(where: { $0.id == id }) {
          expanded = nil
          if band?.sourceID == id { band = nil }
        }
      } else {
        failed = true
      }
      loading = false
      try? await Task.sleep(for: open ? .seconds(30) : .seconds(60))
    }
  }

  /// 品种不支持（没有订单流）或入口条被藏起来：清掉。
  func clear() {
    base = nil; page = nil; loading = false; failed = false
    expanded = nil; band = nil; open = false; pending = nil; scrollTarget = nil
  }

  // MARK: 价位与带子

  /// 点一个价位：展开并画带子；再点同一个就收起、撤带子。
  func toggle(level: HighlightLevel) {
    if expanded == level.id {
      expanded = nil
      if band?.sourceID == level.id { band = nil }
    } else {
      expanded = level.id
      band = Self.band(for: level, scale: scale)
    }
  }

  /// 点一条事件：画它的带子（同一条再点不撤，回图就是要看它）。
  func show(event: HighlightEvent) {
    band = Self.band(for: event, scale: scale, decimals: decimals)
  }

  func clearBand() { band = nil }

  func consumedScroll() { scrollTarget = nil }

  private func consumePending() {
    guard let p = pending, let page, page.base == p.base else { return }
    pending = nil
    if let id = p.focusID {
      if let level = page.levels.first(where: { $0.id == id }) {
        expanded = level.id
        band = Self.band(for: level, scale: scale)
        scrollTarget = level.id
      } else if let event = page.events.first(where: { $0.id == id }) {
        band = Self.band(for: event, scale: scale, decimals: decimals)
        scrollTarget = event.id
      }
    }
    if p.autoOpen { open = true }
  }

  static func band(for level: HighlightLevel, scale: Double) -> HighlightBand {
    let amount = level.wallUsd > 0 ? HighlightsText.usd(level.wallUsd)
      : HighlightTerm.fillMeta.fill(["v": HighlightsText.usd(level.fillUsd)])
    return HighlightBand(kind: .price(low: level.low * scale, high: level.high * scale),
                         label: HighlightsText.zoneName(level.side) + " " + amount, sourceID: level.id,
                         display: level.wallUsd > 0 ? .walls : .signs)
  }

  static func band(for event: HighlightEvent, scale: Double, decimals: Int?) -> HighlightBand? {
    let runs = HighlightsText.eventSentence(event, decimals: decimals, scale: scale, withPrice: false)
    // 带子上的签只要「事 + 数」：去掉「 · 距价 / 价格」那半句。
    let label = runs.plain.components(separatedBy: " · ").first ?? runs.plain
    let display: HighlightBand.Display = [.flowBurst, .liqWave, .oiJump].contains(event.t) ? .signs : .walls
    if let a = event.fromMs, let b = event.toMs { return HighlightBand(kind: .span(from: a, to: b), label: label, sourceID: event.id, display: display) }
    if let p = event.price { return HighlightBand(kind: .price(low: p * scale, high: p * scale), label: label, sourceID: event.id, display: display) }
    if let lo = event.low, let hi = event.high {
      return HighlightBand(kind: .price(low: lo * scale, high: hi * scale), label: label, sourceID: event.id, display: display)
    }
    if let t = event.atMs { return HighlightBand(kind: .span(from: t, to: t + 5 * 60_000), label: label, sourceID: event.id, display: display) }
    return nil
  }
}
