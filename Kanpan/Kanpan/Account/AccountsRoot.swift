import Foundation

/// 账号档案的根目录（`AccountFiles` 开在这儿，每个人一个 `u-<uuid>`、访客一个 `local/<批次>`）。
///
/// 有两个地方要开它：有界面时的账号桥（`AppAccountBridge`），以及后台刷新把 app 拉起、
/// 没有界面时替自动复盘传回合的那条路（`ExchangeReviewUplink`）。两边必须落在同一棵树上，
/// 否则后台传上去的标记写进另一处，回前台又整批重传一遍。
enum AccountsRoot {
  static var url: URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("kanpan/accounts")
    // 测试档案另起一棵 `tests/<uuid>` 子树。**只在 DEBUG 构建里存在**（审查 C-02）：
    // 正式包里没有这条口子，Release 回归靠独立的测试安装沙盒隔离，不靠产品二进制
    // 自己认一个环境变量改档案目录。
    #if DEBUG
    let env = ProcessInfo.processInfo.environment
    if env["KANPAN_TEST_PROFILE"] == "1", let profile = env["KANPAN_PERSISTENCE_PROFILE"], UUID(uuidString: profile) != nil {
      return root.appendingPathComponent("tests/" + profile)
    }
    #endif
    return root
  }
}
