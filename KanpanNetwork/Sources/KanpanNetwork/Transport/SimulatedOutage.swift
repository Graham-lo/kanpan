#if DEBUG

  import Foundation

  // ============================================================ 只断这一个 app 的网
  //
  // M5 A5.3 要「仅中断被测 app 的网络 30 秒后恢复」，而且不许动 Mac 的网络配置
  // （模拟器和宿主机共用网卡，拔 Mac 的网等于把 Surge、别的窗口一起断了）。
  // 所以在本包的出口处断：启动环境带 `KANPAN_TEST_NET_OUTAGE=<开始的 Unix 秒>:<持续秒数>`
  // 时，这段时间里
  //   - 已经连着的 WebSocket 收到下一帧就当连接丢了（`URLError.networkConnectionLost`），
  //     和手机关掉 Wi-Fi 时系统报给已有连接的一样；
  //   - 新建 WebSocket、发 HTTP 一律 `URLError.notConnectedToInternet`，和没网时系统立刻拒掉一样；
  //   - 保活 ping 当作没回 pong。
  // 时间一过全部放行，补缺口、重连都走 app 自己的正常路径。
  //
  // 只有 DEBUG 包认这个环境变量；Release 与 `kanpan-feed` 的发布构建里这个文件整段不编。
  public enum SimulatedOutage {
    private static let window: (start: Double, end: Double)? = {
      guard let raw = ProcessInfo.processInfo.environment["KANPAN_TEST_NET_OUTAGE"] else { return nil }
      let parts = raw.split(separator: ":").compactMap { Double($0) }
      guard parts.count == 2, parts[1] > 0 else { return nil }
      return (parts[0], parts[0] + parts[1])
    }()

    public static var active: Bool {
      guard let window else { return false }
      let now = Date().timeIntervalSince1970
      return now >= window.start && now < window.end
    }
  }

#endif
