import Observation
import ReviewUI
import SwiftUI
import Testing
import UIKit

@testable import Kanpan

/// 整机压测 2026-09-26：宿主跟着逐笔成交重画时，复盘角标不能跟着把整本复盘记录过滤一遍。
///
/// 当时角标挂在顶栏的复盘按钮上；2026-09-27 顶栏那颗按钮撤了，角标搬到底栏「我的」记号的右上角
/// （`TabBar` → `ReviewCountBadge`）。底栏同样挂在跟着行情重画的 `MainScreen` 身上，所以这条照样要守。
@MainActor
struct ReviewBadgeIsolationTests {
  @Observable final class Tick { var n = 0 }
  final class Count { var bodies = 0 }

  struct Host: View {
    let tick: Tick
    let review: ReviewFeature
    let count: Count
    var body: some View {
      let _ = count.bodies += 1
      // 父视图读 tick：每跳一口它就重算，和底栏的宿主跟着行情重画是同一回事。
      // `onPick` 抓着这一口的数：闭包每次都是新的，底栏自己的 body 一定跟着重算。
      let n = tick.n
      TabBar(theme: PanelTheme(dark: false), current: .chart, review: review, onPick: { _ in _ = n })
    }
  }

  @Test func tickingHeaderDoesNotRecountReviews() {
    let tick = Tick(); let review = ReviewFeature(); let host = Count()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 120))
    let controller = UIHostingController(rootView: Host(tick: tick, review: review, count: host))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.layoutIfNeeded()
    // 首屏落定（窗口、安全区第一趟会再排一次）之后再起算。
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    controller.view.layoutIfNeeded()
    let first = ReviewCountBadge.bodies; let hostFirst = host.bodies
    #expect(first >= 1, "角标一次都没画出来，量不到")
    for n in 1...20 {
      tick.n = n
      // Observation 的失效在下一趟 run loop 才落到视图上：转一下再布局。不量时间，只是让它落地。
      RunLoop.main.run(until: Date().addingTimeInterval(0.02))
      controller.view.setNeedsLayout()
      controller.view.layoutIfNeeded()
    }
    // 宿主确实跟着重画了……
    #expect(host.bodies - hostFirst >= 20, "父视图只重算了 \(host.bodies - hostFirst) 次，这条量不到")
    // ……而角标一次都没重算。
    #expect(ReviewCountBadge.bodies == first, "宿主跳 20 口，角标重算了 \(ReviewCountBadge.bodies - first) 次")
    window.isHidden = true
  }
}
