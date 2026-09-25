import Foundation
import KanpanCore
import KanpanData
import Synchronization
import SwiftUI

// 主力订单流 · app 这一层的胶水（唯一的一份）。
//
// 数据链路在 KanpanData（OrderFlowFeed / RoutedMarketFeed.setOrderFlow），绘制在 KanpanChart
// （ChartRenderer+OrderFlow）；这里只做四件事：
//   1. 把用户开关（`Prefs.orderFlow`）、改过的门槛 / 步长（`Prefs.orderFlowOverrides`，都跟人走、
//      随账号同步）连同「在前台」交给行情流（图表暂时看不见时照订：大单的历史不能因为切去
//      自选页看一眼就清零）；
//   2. 记下当前品种的品种事实（base、资产类型、价格步长），行情流拿它查默认门槛；
//   3. 收下行情流推来的当前大单集合，只认当前品种的；
//   4. 给图表一份可以直接塞进 `ChartState.orderFlow` 的值（横屏画线台给 nil）。
// 大单集合按品种在本机记一份小日志（24 小时内、最多 5000 条，见 OrderFlowFeed），不同步；更早的由行情流
// 从 kanpan-api 取（服务端存 3 天），图往左拖出已取区间就往前补——所以这里还要把图的可视范围交给行情流（`noteView`）。

/// 行情流在自己的执行器上问品种事实，所以得是线程安全的一张小表。
final class OrderFlowFactsTable: Sendable {
  private let table = Mutex<[String: OrderFlowFacts]>([:])
  /// 记一只；和原来那份一样就返回 false（不用再催行情流一次）。
  @discardableResult
  func set(_ facts: OrderFlowFacts, for symbol: String) -> Bool {
    table.withLock { all in
      let key = InstrumentID.canonical(symbol)
      if all[key] == facts { return false }
      all[key] = facts
      return true
    }
  }
  func facts(for symbol: String) -> OrderFlowFacts? { table.withLock { $0[InstrumentID.canonical(symbol)] } }
}

/// 十字线此刻停没停在主图上。主线程写、行情流每一拍评估时读，所以是把锁（审查第 31 项：
/// 画出来一样的帧不发，只有读数要精确金额的时候才逐拍发）。
final class OrderFlowFocus: Sendable {
  private let on = Mutex(false)
  func set(_ value: Bool) { on.withLock { $0 = value } }
  var isOn: Bool { on.withLock { $0 } }
}

@MainActor
@Observable
final class OrderFlowLink {
  /// 行情流推来的最近一帧（只会是当前品种的）。
  private(set) var snapshot: OrderFlowSnapshot?
  /// 用户开关。
  @ObservationIgnored private(set) var wanted = false
  /// 用户改过的门槛 / 步长（`Prefs.orderFlowOverrides` 的镜像）。
  @ObservationIgnored private(set) var overrides: [String: OrderFlowOverride] = [:]
  /// 开关开着、在前台——此刻是否真的订着簿。
  private(set) var active = false
  /// 当前品种的事实（面板里「恢复默认」要显示的默认值从这里算）。
  private(set) var currentFacts: OrderFlowFacts?
  @ObservationIgnored let facts = OrderFlowFactsTable()
  /// 每次交给行情流都编一个递增序号：各起一个 Task，到达先后不定，行情流按序号丢掉后到的旧调用（审查第 40 项）。
  @ObservationIgnored private var sequence: UInt64 = 0
  @ObservationIgnored let focus = OrderFlowFocus()

  /// 上一次交给行情流的可视范围（按分钟取整）：平移时每一帧都回调，分钟没变就不再跨一次 actor。
  @ObservationIgnored private var sentView: (symbol: String, from: Int64, to: Int64)?
  /// 可视范围也是每次各起一个 Task 交给行情流，同样编递增序号，后到的旧范围由行情流丢掉（审查 P2-4）。
  @ObservationIgnored private var viewSequence: UInt64 = 0

  /// 图的可视范围变了（`ChartView.onViewChanged`，经 `MarketModel.loadOI`）。开着指标才交给行情流：
  /// 它按最左边往前补服务端历史，超过 2 万条挤掉旧单时优先留可视区里的。
  func noteView(_ view: ViewWindow, symbol: String, feed: RoutedMarketFeed) {
    guard active, view.span > 0, view.from.isFinite, view.to.isFinite else { return }
    let from = Int64((view.from / 60_000).rounded(.down)) * 60_000
    let to = Int64((view.to / 60_000).rounded(.up)) * 60_000
    if let sent = sentView, sent.symbol == symbol, sent.from == from, sent.to == to { return }
    sentView = (symbol, from, to)
    viewSequence &+= 1
    let sequence = viewSequence
    Task { await feed.setOrderFlowView(symbol: symbol, fromMs: from, toMs: to, sequence: sequence) }
  }

  /// 十字线变了（`ChartView.onCrosshairChanged`）：停在主图上时读数要精确金额。
  func noteCrosshair(onMain: Bool) { focus.set(onMain) }

  func setWanted(_ on: Bool) { wanted = on }
  func setOverrides(_ next: [String: OrderFlowOverride]) { overrides = next }

  /// 跟着 `MarketModel.updateMicrostructure` 走：前后台、开关、改门槛、换行情流、品种信息到了
  /// 都从那儿过（传进来的是「在前台」）。重复调用无害：行情流那一侧已经在跑同一只就不重订。
  func apply(visible: Bool, to feed: RoutedMarketFeed) {
    active = visible && wanted
    if !active { snapshot = nil; sentView = nil }
    sequence &+= 1
    let on = active, table = self.facts, overrides = self.overrides, focus = self.focus, sequence = self.sequence
    Task { await feed.setOrderFlow(enabled: on, overrides: overrides, facts: { table.facts(for: $0) },
                                   precise: { focus.isOn }, sequence: sequence) }
  }

  /// 行情流的 `.orderFlow` 事件。别的品种的帧（切品种那一拍）不认。
  func accept(_ frame: OrderFlowSnapshot?, symbol: String) {
    guard active, let frame else { snapshot = nil; return }
    guard InstrumentID.canonical(frame.symbol) == InstrumentID.canonical(symbol) else { return }
    snapshot = frame
  }

  /// 当前品种信息到了：记下事实。返回 true 表示这只的事实是新的，调用方要再催行情流一次
  /// （开着指标时，品种信息晚于首帧到达，行情流那一拍因为查不到事实没起来）。
  func noteInfo(_ info: SymbolInfo) -> Bool {
    let next = OrderFlowFacts(info: info, turnover24h: nil)
    currentFacts = next
    return facts.set(next, for: info.symbol)
  }

  /// 面板上显示的「此刻生效」的门槛与步长：行情流已经算好的那份优先（含按收盘推出来的步长、
  /// 按成交额分出来的档位），还没有就拿默认表叠用户改过的项。
  func effectiveThresholds(symbol: String) -> OrderFlowThresholds? {
    if let snapshot, InstrumentID.canonical(snapshot.symbol) == InstrumentID.canonical(symbol),
       OrderFlowProduct.allCases.contains(where: { snapshot.thresholds[$0] != nil }) { return snapshot.thresholds }
    guard let facts = facts.facts(for: symbol) else { return nil }
    return facts.defaults.applying(overrides[facts.overrideKey])
  }

  /// 行情流算好的这只品种的默认门槛与步长（`OrderFlowSnapshot.defaults`，按成交额分过档）。
  /// 这只的帧还没来（或只是「拉快照中」的占位）就是 nil。
  func feedDefaults(symbol: String) -> OrderFlowThresholds? {
    guard let snapshot, InstrumentID.canonical(snapshot.symbol) == InstrumentID.canonical(symbol),
          OrderFlowProduct.allCases.contains(where: { snapshot.defaults[$0] != nil }) else { return nil }
    return snapshot.defaults
  }

  /// 给图表的值：关着或横屏画线台是 nil；订着但这只品种的帧还没到，就先给「拉快照中」，
  /// 图例一直占着那一行，切品种时图不会上下跳一下。
  func chartValue(symbol: String, drawingCanvasOnly: Bool) -> OrderFlowSnapshot? {
    guard active, !drawingCanvasOnly else { return nil }
    if let snapshot, InstrumentID.canonical(snapshot.symbol) == InstrumentID.canonical(symbol) { return snapshot }
    return .loading(symbol)
  }
}

/// 把 `Prefs.orderFlow` 与 `Prefs.orderFlowOverrides` 接到行情模型上。挂在主界面上一行 `.modifier(...)`。
struct OrderFlowObserver: ViewModifier {
  let on: Bool
  let overrides: [String: OrderFlowOverride]
  let market: MarketModel
  func body(content: Content) -> some View {
    content
      .onChange(of: overrides, initial: true) { _, now in market.setOrderFlowOverrides(now) }
      .onChange(of: on, initial: true) { _, now in market.setOrderFlow(now) }
  }
}
