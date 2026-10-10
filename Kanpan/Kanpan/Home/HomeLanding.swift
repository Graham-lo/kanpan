import Foundation

/// 冷启动落在哪一格。2026-10-10 起默认是「首页」（PROJECT.md §79）。
///
/// UI 用例（`KANPAN_TEST_PROFILE=1`）照旧按档案判自选 / 行情——几百条用例都从行情页或自选页起手；
/// 要测首页的用例另加 `KANPAN_TEST_LANDING=home`。
enum HomeLanding {
  static var enabled: Bool {
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_LANDING"] == "home" { return true }
    return env["KANPAN_TEST_PROFILE"] != "1"
  }
}
