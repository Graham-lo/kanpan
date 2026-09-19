import Foundation

/// 「正在把别处来的值装进本机」这段保护区，外加**离开保护区之后**才做的那些事。
///
/// 为什么不是桥接层里一个 `Bool`：合并完云端那份之后那句「本地还脏就反过来推上去」
/// 原本写在保护区里面，而记账那一步的第一道门就是 `!applying`，于是那句回推
/// 一条操作都产生不了——用户在 A 机上改的设置，被 B 机推上来的旧值一合并，
/// 就再也没人把 A 的那一版送出去了。把「保护区」和「出去之后补做」做成同一个
/// 东西，这种写法就再也写不出来了。
///
/// `epoch`：登记的时候记一次代次，离开时对不上就丢掉。换账号、或者中途又起了
/// 一轮应用时，上一轮攒下的那个快照已经过期，不能再推上去。
@MainActor public final class ApplyGate {
  public private(set) var isApplying = false
  public private(set) var epoch = UUID()
  private var deferred: [(epoch: UUID, work: @MainActor () -> Void)] = []
  public init() {}

  /// 进入保护区。
  public func enter() { isApplying = true }

  /// 离开保护区，并把这一代次登记的补做动作依次跑掉。
  public func leave() {
    isApplying = false
    let now = epoch
    let work = deferred
    deferred.removeAll()
    for item in work where item.epoch == now { item.work() }
  }

  /// 换一代。上一代登记的补做动作作废。
  public func rotate() {
    epoch = UUID()
    deferred.removeAll()
  }

  /// 登记一件「出了保护区再做」的事。不在保护区里就当场做。
  public func afterApplying(_ work: @MainActor @escaping () -> Void) {
    guard isApplying else { work(); return }
    deferred.append((epoch, work))
  }
}
