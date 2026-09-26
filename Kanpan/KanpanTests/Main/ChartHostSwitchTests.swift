import Foundation
import KanpanChart
import KanpanCore
import Observation
import SwiftUI
import Testing
import UIKit

@testable import Kanpan

// 整机压测（2026-09-26）· 快切品种时宿主这一层的两处漏账：
// 1. 空过一轮（冷切到没快照的品种）之后，`ChartHost` 拿 `proxy.savedState` 里那份陈年存档当
//    「上一张图」，切回那只时把很久以前的视野、十字线原样搬回来，而不是回到最新。
// 2. 扫图横滑欠的那笔「铺到某段时间」兑现过一次后，每来一根新 K 线都再把视野夹回左缘，
//    人在这几秒里的拖动全被拽回去。
// 真挂进一个窗口，走 SwiftUI → `updateUIView` 那条真路。

@MainActor @Observable private final class Feed { var state: ChartState? }

private struct Harness: View {
  let feed: Feed
  let proxy: ChartProxy
  var body: some View {
    ChartHost(state: feed.state, proxy: proxy).frame(width: 390, height: 520)
  }
}

@MainActor
private func series(_ symbol: String, count: Int = 600, t0: Int64 = 1_700_000_000_000) -> BarSeries {
  var o: [Double] = [], h: [Double] = [], l: [Double] = [], c: [Double] = [], v: [Double] = []
  var p = 100.0
  for i in 0..<count {
    let close = p * (1 + (Double(i % 7) - 3) * 0.002)
    o.append(p); h.append(max(p, close) * 1.001); l.append(min(p, close) * 0.999); c.append(close); v.append(10)
    p = close
  }
  return BarSeries(symbol: symbol, interval: .h1, t0: t0, open: o, high: h, low: l, close: c, volume: v)
}

@MainActor
private func state(_ s: BarSeries) -> ChartState {
  ChartState(series: s, symbol: SymbolInfo(symbol: s.symbol, base: "X", pricePrecision: 2, tickSize: 0.01),
             view: ViewWindow(to: Double(s.lastTime), span: Double(s.step) * 80))
}

@MainActor
@Suite("ChartHost 快切换", .serialized, .timeLimit(.minutes(1)))
struct ChartHostSwitchTests {
  private func mount() -> (UIWindow, Feed, ChartProxy) {
    let feed = Feed(), proxy = ChartProxy()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 520))
    window.rootViewController = UIHostingController(rootView: Harness(feed: feed, proxy: proxy))
    window.makeKeyAndVisible()
    window.layoutIfNeeded()
    return (window, feed, proxy)
  }

  /// 等 SwiftUI 把新 state 递进 `updateUIView` 并让图排好版。等的是条件，不是时长。
  private func settle(_ window: UIWindow, until done: () -> Bool) async {
    for _ in 0..<100 {
      window.layoutIfNeeded(); window.rootViewController?.view.layoutIfNeeded()
      if done() { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test("空过一轮再切回同一只：回到最新，不搬陈年的视野和十字线")
  func emptyRoundDropsStaleSavedState() async throws {
    let (window, feed, proxy) = mount()
    defer { window.isHidden = true }
    let a = series("AAAUSDT")
    feed.state = state(a)
    await settle(window) { proxy.box?.chart.chartLayout != nil && proxy.box?.chart.state?.series.symbol == "AAAUSDT" }
    let chart = try #require(proxy.box?.chart)
    #expect(chart.isAtLatest, "前提：开张在最新")
    // 人把图拖进历史、留了一条十字线。
    var s = try #require(chart.state)
    s.view = ViewWindow(to: Double(a.time(at: 200)), span: s.view.span)
    s.crosshair = Crosshair(index: 150, price: 100)
    chart.state = s
    #expect(proxy.savedState?.view.to == Double(a.time(at: 200)), "前提：存档记下了这份视野")

    // 冷切到一只没有快照的品种：图空一轮。
    feed.state = nil
    await settle(window) { proxy.box?.chart.state == nil }
    // 数据回来的正好是原来那只（快切里「点回去」）。
    feed.state = state(a)
    await settle(window) { proxy.box?.chart.state?.series.symbol == "AAAUSDT" }
    let back = try #require(proxy.box?.chart)
    #expect(back.isAtLatest, "切回来被搬回了很久以前那段历史")
    #expect(back.state?.crosshair == nil, "切回来冒出了上一次的十字线")
  }

  @Test("扫图欠的「铺到某段时间」兑现后，新 K 线不再把人拖动过的视野拽回左缘")
  func windowDebtDoesNotFightTheUser() async throws {
    let (window, feed, proxy) = mount()
    defer { window.isHidden = true }
    let a = series("AAAUSDT")
    feed.state = state(a)
    await settle(window) { proxy.box?.chart.chartLayout != nil && proxy.box?.chart.state?.series.symbol == "AAAUSDT" }
    // 在看 A 的一段早于 B 上市的历史时横滑到 B：B 的数据只从 A 中段开始。
    let want = ViewWindow(to: Double(a.time(at: 120)), span: Double(a.step) * 80)
    proxy.show(window: want, symbol: "BBBUSDT", interval: .h1)
    var b = series("BBBUSDT", count: 300, t0: a.time(at: 300))
    feed.state = state(b)
    await settle(window) { proxy.box?.chart.state?.series.symbol == "BBBUSDT" }
    let chart = try #require(proxy.box?.chart)
    let clamped = try #require(chart.state?.view)
    #expect(clamped.from <= Double(b.firstTime) + Double(b.step) * 2, "前提：账兑现了一次，视野夹在 B 的左缘")

    // 人往右拖了一段（直接改图上的视野，和手势写回的是同一个字段）。
    var s = try #require(chart.state)
    let dragged = ViewWindow(to: Double(b.time(at: 200)), span: clamped.span)
    s.view = dragged
    chart.state = s
    // 行情照常一根根来。
    for k in 0..<3 {
      _ = b.upsert(Bar(openTime: b.lastTime + b.step, open: 100, high: 101, low: 99, close: 100, volume: Double(k)))
      feed.state = state(b)
      await settle(window) { proxy.box?.chart.state?.series.count == b.count }
      #expect(proxy.box?.chart.state?.view.to == dragged.to, "第 \(k + 1) 根新 K 线把视野拽回了左缘")
    }
  }
}
