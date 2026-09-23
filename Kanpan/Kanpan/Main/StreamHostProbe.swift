import Foundation

/// 真机上的推送域名体检（只在 `KANPAN_WS_SWEEP=1` 时跑，平时这段代码不执行）。
///
/// 为什么非要在手机上跑：Mac 这边的 DNS 与出口都被代理接管，探出来的结果是代理
/// 出口的网络，不是手机的网络。同一个域名在两边可以一个通一个不通，拿 Mac 的
/// 结论去改 app 的默认域名等于瞎猜。这段只做一件事——挨个拨候选域名，只认
/// 「真收到一帧带 `stream` 字段的行情」，握手成功但不发数据的空壳一律判失败。
///
/// 候选只列生产盘的域名。合约测试网推的不是生产数据，拿来当对照组也没有意义，不在这张表里。
enum StreamHostProbe {
  static let hosts = [
    "dstream.binance.me",           // 出厂默认：生产盘，国内直连
    "dstream.binance.com",          // 同一族的主域名，国内要走代理
    "fstream.binance.com",          // 旧默认，只剩盘口流
    "fstream.binance.me",
    "fstream.binance.info",
    "data-stream.binance.vision",   // 现货镜像，通了也只能当参考
  ]

  /// 一条流拨出去，最多等 `timeout` 秒第一帧行情。
  ///
  /// 订的是 `bookTicker`：它跟着盘口走，只要域名活着就一直有；`markPrice`/`ticker`
  /// 这类成交面的流会被币安自己的故障掐断（2026-09-18 就整段没数据），拿它们当
  /// 探针会把好域名误判成空壳。后面再挂一个 `markPrice@1s` 只为顺带看它有没有恢复。
  private static func probe(_ host: String, timeout: TimeInterval = 6) async -> String {
    var c = URLComponents()
    c.scheme = "wss"; c.host = host; c.path = "/stream"
    c.queryItems = [URLQueryItem(name: "streams", value: "btcusdt@bookTicker/btcusdt@markPrice@1s")]
    guard let url = c.url else { return "地址无效" }
    let cfg = URLSessionConfiguration.ephemeral
    cfg.timeoutIntervalForRequest = timeout
    let session = URLSession(configuration: cfg)
    let task = session.webSocketTask(with: url)
    task.resume()
    let start = Date()
    defer { session.invalidateAndCancel() }
    return await withTaskGroup(of: String.self) { group in
      group.addTask {
        while true {
          do {
            let message = try await task.receive()
            guard case .string(let text) = message else { continue }
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            if text.contains("\"stream\"") { return "✅ 有行情 \(ms)ms \(text.prefix(90))" }
            return "⚠️ 收到非行情帧 \(ms)ms \(text.prefix(90))"
          } catch {
            return "❌ \(Int(Date().timeIntervalSince(start) * 1000))ms \(error)"
          }
        }
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(timeout))
        // 必须亲手掐掉连接：`receive()` 不理会任务取消，不掐它那条子任务就永远不
        // 返回，而 `withTaskGroup` 退出前要等齐所有孩子——整轮体检会卡死在这一个
        // 域名上（第一版就是这么停在第一行的）。
        task.cancel(with: .goingAway, reason: nil)
        return "❌ \(Int(timeout * 1000))ms 握手过了但一帧不发（空壳）"
      }
      let first = await group.next()!
      group.cancelAll()
      task.cancel(with: .goingAway, reason: nil)
      return first
    }
  }

  /// **只在 DEBUG 构建里认这个开关**（审查 C-02）：正式包不该被一个环境变量支使着
  /// 去挨个拨候选域名。它不会替换图表行情，但正式二进制里不留这条口子。
  static func runIfRequested() {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["KANPAN_WS_SWEEP"] == "1" else { return }
    Task.detached(priority: .utility) {
      print("== 推送域名体检开始 ==")
      for host in hosts {
        let line = await probe(host)
        print("体检 \(host) → \(line)")
      }
      print("== 推送域名体检结束 ==")
    }
    #endif
  }
}
