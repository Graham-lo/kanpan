import SwiftUI

@main
struct KanpanApp: App {
  /// MetricKit 的 payload 是系统攒着、隔天推一次的。订阅得赶在装机之后的第一次启动，
  /// 晚订阅一次就少一天的数据——所以放在这儿，不等界面起来。幂等，重复叫没事。
  init() { DiagnosticsCenter.shared.start() }

  var body: some Scene {
    WindowGroup {
      MainScreen()
    }
  }
}
