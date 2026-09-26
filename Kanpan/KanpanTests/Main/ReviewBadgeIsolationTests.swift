import Observation
import ReviewUI
import SwiftUI
import Testing
import UIKit

@testable import Kanpan

/// 整机压测 2026-09-26：顶栏跟着逐笔成交重画时，复盘角标不能跟着把整本复盘记录过滤一遍。
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
      // 父视图读 tick：每跳一口它就重算，和顶栏跟着行情重画是同一回事。
      TopBar(theme: PanelTheme(dark: false), symbol: "BTC \(tick.n)", review: review,
             onReview: {}, onSearch: {})
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
    // 顶栏确实跟着重画了……
    #expect(host.bodies - hostFirst >= 20, "父视图只重算了 \(host.bodies - hostFirst) 次，这条量不到")
    // ……而角标一次都没重算。
    #expect(ReviewCountBadge.bodies == first, "顶栏跳 20 口，角标重算了 \(ReviewCountBadge.bodies - first) 次")
    window.isHidden = true
  }
}
