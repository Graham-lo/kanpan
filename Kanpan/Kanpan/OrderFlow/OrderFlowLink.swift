import Foundation
import KanpanCore
import KanpanData
import Synchronization
import SwiftUI

// 主力订单流 · app 这一层的胶水（唯一的一份）。
//
// 数据链路在 KanpanData（OrderFlowFeed / RoutedMarketFeed.setOrderFlow），绘制在 KanpanChart
// （ChartRenderer+OrderFlow）；这里只做三件事：
//   1. 把用户开关（`Prefs.orderFlow`，跟人走、随账号同步）连同「图表可见 + 在前台」交给行情流；
//   2. 收下行情流推来的当前大单集合，只认当前品种的；
//   3. 给图表一份可以直接塞进 `ChartState.orderFlow` 的值（横屏画线台给 nil）。
// 大单集合本身永远不同步、不落盘，切品种就清。

/// 行情流在自己的执行器上问报价步长，所以步长表得是线程安全的一张小表。
final class OrderFlowTicks: Sendable {
  private let table = Mutex<[String: Double]>([:])
  func set(_ tick: Double, for symbol: String) {
    guard tick > 0, tick.isFinite else { return }
    table.withLock { $0[InstrumentID.canonical(symbol)] = tick }
  }
  func tick(for symbol: String) -> Double? { table.withLock { $0[InstrumentID.canonical(symbol)] } }
}

@MainActor
@Observable
final class OrderFlowLink {
  /// 行情流推来的最近一帧（只会是当前品种的）。
  private(set) var snapshot: OrderFlowSnapshot?
  /// 用户开关。
  @ObservationIgnored private(set) var wanted = false
  /// 开关开着、图表看得见、在前台——此刻是否真的订着簿。
  private(set) var active = false
  @ObservationIgnored let ticks = OrderFlowTicks()

  func setWanted(_ on: Bool) { wanted = on }

  /// 跟着 `MarketModel.updateMicrostructure` 走：可见性、前后台、开关、换行情流都从那儿过。
  func apply(visible: Bool, to feed: RoutedMarketFeed) {
    active = visible && wanted
    if !active { snapshot = nil }
    let on = active, ticks = self.ticks
    Task { await feed.setOrderFlow(enabled: on, tick: { ticks.tick(for: $0) }) }
  }

  /// 行情流的 `.orderFlow` 事件。别的品种的帧（切品种那一拍）不认。
  func accept(_ frame: OrderFlowSnapshot?, symbol: String) {
    guard active, let frame else { snapshot = nil; return }
    guard InstrumentID.canonical(frame.symbol) == InstrumentID.canonical(symbol) else { return }
    snapshot = frame
  }

  /// 报价步长跟着当前品种信息记下来（桶宽按步长取整）。
  func noteInfo(_ info: SymbolInfo) { ticks.set(info.tickSize, for: info.symbol) }

  /// 给图表的值：关着或横屏画线台是 nil；订着但这只品种的帧还没到，就先给「拉快照中」，
  /// 图例一直占着那一行，切品种时图不会上下跳一下。
  func chartValue(symbol: String, drawingCanvasOnly: Bool) -> OrderFlowSnapshot? {
    guard active, !drawingCanvasOnly else { return nil }
    if let snapshot, InstrumentID.canonical(snapshot.symbol) == InstrumentID.canonical(symbol) { return snapshot }
    return .loading(symbol)
  }
}

/// 把 `Prefs.orderFlow` 接到行情模型上。挂在主界面上一行 `.modifier(...)`。
struct OrderFlowObserver: ViewModifier {
  let on: Bool
  let market: MarketModel
  func body(content: Content) -> some View {
    content.onChange(of: on, initial: true) { _, now in market.setOrderFlow(now) }
  }
}
