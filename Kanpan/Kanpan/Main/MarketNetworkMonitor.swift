import Foundation
import Network

/// Observe real reachability/interface transitions, not latency jitter. One callback per path change.
@MainActor final class MarketNetworkMonitor {
  private let queue = DispatchQueue(label: "kanpan.network.path")
  private var monitor: NWPathMonitor?

  func start(_ changed: @escaping @Sendable (Bool) -> Void) {
    stop()
    let monitor = NWPathMonitor()
    self.monitor = monitor
    let snapshot = PathSnapshot()
    monitor.pathUpdateHandler = { path in
      let online = path.status == .satisfied
      let interface = path.usesInterfaceType(.wifi) ? "wifi"
        : path.usesInterfaceType(.cellular) ? "cellular"
        : path.usesInterfaceType(.wiredEthernet) ? "wired" : "other"
      let key = "\(online)-\(interface)"
      defer { snapshot.key = key }
      guard let old = snapshot.key, old != key else { return }
      changed(online)
    }
    monitor.start(queue: queue)
  }
  func stop() { monitor?.cancel(); monitor = nil }
}

/// Accessed only on the monitor's private serial queue.
private final class PathSnapshot: @unchecked Sendable { var key: String? }
