import Foundation

/// 一个凭据槽上的刷新协调者：**进程级**，按槽唯一。
///
/// A-06（多客户端互踢）。refresh 令牌是一次性的：服务端（`Backend/kanpan-api/src/auth.rs`
/// 的 refresh 路径）看到同一把 refresh 被用第二次，判定为令牌重用，当场吊销整个会话
/// 家族——用户被登出。过去单飞保护（`refreshFlight`）和代际（`generation`）是
/// `AccountClient` 的**实例字段**，两个客户端指着同一份钥匙串凭据时各刷各的、各带各的
/// `request_id`，等于没有保护。全 app 现在只有一处构造客户端，所以触发不了；
/// 但「触发不了」不是防护。
///
/// 所以这两样东西跟着**槽**走，不跟着实例走：同一个槽上任何时刻只有一趟刷新真的出门，
/// 其余的人等它、复用它的结果。代际也一样——退登 / 换人登录让在途请求作废这件事，
/// 必须让共用这份凭据的所有客户端都看见。
actor RefreshCoordinator {
  private var flight: Task<AccountTokens, Error>?
  /// 这一槽的代际。换人（登录、退登）就往前走一格，在途的结果一律作废。
  private(set) var generation = UUID()
  /// 搭上别人那班车的次数。只给测试看：用来证明「其余实例真的在等」，
  /// 而不是碰巧错开了时间。
  private(set) var joinedFlights = 0

  /// 领跑或者搭车。第一个进来的人真的去刷（跑 `work`），其余的人等同一个结果。
  ///
  /// `work` 只有领跑者会跑到，所以「读凭据、写 request_id、发请求」这一串
  /// 也只发生一次——搭车的人连钥匙串都不用碰。
  func refresh(_ work: @escaping @Sendable () async throws -> AccountTokens) async throws -> AccountTokens {
    if let flight {
      joinedFlights += 1
      return try await flight.value
    }
    let task = Task { try await work() }
    flight = task
    // 这一趟落地（成了或者砸了）就把班车撤掉，下一次请求才能重新发起。
    // 中途被 `invalidate()` 换掉的话不要把新的那班车误删。
    defer { if flight == task { flight = nil } }
    return try await task.value
  }
  /// 这一槽的凭据换人了（登录、退登）：在途的那趟作废，代际往前走一格。
  func invalidate() {
    flight?.cancel()
    flight = nil
    generation = UUID()
  }
}

extension RefreshCoordinator {
  /// 按槽取协调者。同一个槽名在这个进程里永远拿到同一个——这就是「进程级」的落点。
  static func shared(slot: String) -> RefreshCoordinator { registry.coordinator(slot) }
  private static let registry = Registry()
  private final class Registry: @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [String: RefreshCoordinator] = [:]
    func coordinator(_ slot: String) -> RefreshCoordinator {
      lock.lock(); defer { lock.unlock() }
      if let existing = slots[slot] { return existing }
      let made = RefreshCoordinator()
      slots[slot] = made
      return made
    }
  }
}
