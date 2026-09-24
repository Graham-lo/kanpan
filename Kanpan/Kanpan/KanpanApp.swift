import SwiftUI

@main
struct KanpanApp: App {
  /// 横竖屏由 app 自己说了算（§10.7 的「回竖屏」按钮），系统的自动转向只是默认值。
  /// 这条桥必须挂在 `@main` 上才有人问它——`Orientation.rotate(to:)` 改的就是它。
  @UIApplicationDelegateAdaptor(OrientationBridge.self) private var appDelegate

  /// MetricKit 的 payload 是系统攒着、隔天推一次的。订阅得赶在装机之后的第一次启动，
  /// 晚订阅一次就少一天的数据——所以放在这儿，不等界面起来。幂等，重复叫没事。
  init() {
    // KanpanTests 是挂在 app 上跑的单测（`TEST_HOST`）：app 进程照样起来，
    // 但这时候不该拨行情、订 MetricKit、写真沙盒——那些会和用例抢同一份状态。
    guard !Self.hostsUnitTests else { return }
    DiagnosticsCenter.shared.start()
    // 老版本留在 defaults 里、已经没人读的镜像键，清一次（见 `LaunchMirror.retiredKeys`）。
    LaunchMirror.sweepRetired()
    // 趁界面还没起来，把到行情域名的连接先握好（见 `LaunchPrewarm`）。
    LaunchPrewarm.run()
    // 系统喊内存紧张时得有人去放 K 线缓存。通知只能在这儿听，
    // 真正要收的 `MarketModel` 在 `MainScreen` 里，中间隔一个转接。
    MemoryWarningRelay.shared.start()
    // 前后台、以及被杀之前那最后一下，全 app 只有 `AppLifecycle` 一个听众。
    // 谁要在那一刻落盘，去它那儿登记，顺序由它排。
    AppLifecycle.shared.start()
    // 只有 `KANPAN_WS_SWEEP=1` 时才动：真机上挨个拨候选推送域名，看哪条真收得到行情。
    StreamHostProbe.runIfRequested()
    // 开日志时每秒报一次主线程滞后：界面冻住和行情没到，日志里长得不一样。
    MainThreadHeartbeat.startIfRequested()
    // 点通知冷启动时，系统在 app 启动完成的那一刻就把它交回来——代理得赶在
    // 那之前挂上，晚一步那一下就没人接了。这儿不申请任何通知权限。
    AlertNotifications.shared.install()
    // 桌面长按图标那几格：这儿只是把「怎么摆」装上去，摆什么由「最近看过」
    // 变化时自己算（见 `HomeShortcuts`）。
    HomeShortcutsBridge.install()
  }

  /// 这个进程是不是 KanpanTests 的宿主。只看 XCTest 有没有被注入进来，
  /// 不读启动环境（Release 不留读环境的后门，见 `ReleaseHookScanTests`）；
  /// 只编进 DEBUG 与 `KANPAN_TEST_SUPPORT`（`make *-test-release`）两种包，正式 Release 恒为 false。
  /// UI 用例的 app 进程里不注入 XCTest，所以它们照常走完整启动。
  static let hostsUnitTests: Bool = {
    #if DEBUG || KANPAN_TEST_SUPPORT
    return NSClassFromString("XCTestCase") != nil
    #else
    return false
    #endif
  }()

  var body: some Scene {
    WindowGroup {
      if Self.hostsUnitTests {
        Color.clear
      } else {
        root
      }
    }
  }

  private var root: some View {
    MainScreen()
      // 系统「文字大小」整个 app 跟到 .xxxLarge 为止（P2.13）。再往上的辅助功能大字
      // （AX1–AX5）会把自选行、板块表这种一行一只的密集列表撑成一屏两三行，
      // 这儿一处封顶，面板、弹层、整页都从环境里继承。行情页头部那一行封得更低，
      // 见 `MainHeaderView`。K 线画布里的字不走动态字体，不受这一条影响。
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      // 外面进来的链接全走这一个口：桌面快捷入口、通知点击、共享链接。
      // 这儿只负责交给路由，去哪儿由 `MainScreen` 一处消费（见 `DeepLink`）。
      .onOpenURL { DeepLinkRouter.shared.open($0) }
      // Handoff（P3.4）：另一台设备上正看着的那张图，化成同一条深链走同一个口。
      .onContinueUserActivity(ChartHandoff.activityType) { activity in
        guard let link = ChartHandoff.link(from: activity.userInfo ?? [:]) else { return }
        DeepLinkRouter.shared.open(link)
      }
  }
}
