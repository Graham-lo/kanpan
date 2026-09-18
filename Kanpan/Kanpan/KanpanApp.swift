import SwiftUI

@main
struct KanpanApp: App {
  /// 横竖屏由 app 自己说了算（§10.7 的「回竖屏」按钮），系统的自动转向只是默认值。
  /// 这条桥必须挂在 `@main` 上才有人问它——`Orientation.rotate(to:)` 改的就是它。
  @UIApplicationDelegateAdaptor(OrientationBridge.self) private var appDelegate

  /// MetricKit 的 payload 是系统攒着、隔天推一次的。订阅得赶在装机之后的第一次启动，
  /// 晚订阅一次就少一天的数据——所以放在这儿，不等界面起来。幂等，重复叫没事。
  init() {
    DiagnosticsCenter.shared.start()
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
  }

  var body: some Scene {
    WindowGroup {
      MainScreen()
    }
  }
}
