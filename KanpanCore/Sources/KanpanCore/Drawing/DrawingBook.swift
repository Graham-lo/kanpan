import Foundation

/// 画线的**唯一真值**：所有品种的线、每个品种的撤销栈、每品种条数上限，都在这一本里。
///
/// 从前画线有四份（审查 1.3 / 23）：磁盘上的 `DrawStore`、图上的 `ChartState.drawings`、
/// 宿主 `DrawingController.archive`、分享时从图上抄下来的那份。图先改自己那份，再经
/// `onDrawingsChanged` 喊宿主抄回存档；撤销栈一份挂在图的关联对象上、一份按品种存在宿主里，
/// 图一重建就要靠宿主「接力」灌回去；宿主拷贝 `ChartState` 时还得记得把线从旧的那份抄过来。
/// 哪一步漏了，两份就对不上。
///
/// 现在是一份：
///
/// - **这一本是真值**。图（`ChartView`）绑上它之后，`ChartState.drawings` 只是它按
///   `ChartState.series.symbol` 投影出来的那一桶，图上的每一笔编辑（落笔、拖、删、撤销）
///   都先写进这里，再投影回图。
/// - **`DrawStore` 只是持久层**：宿主听 `.edited` 把整本存档落盘，和从前一样先存档后文件。
/// - `DrawingController` 的 `items`、分享卡片的那摞线，都只是读这本的投影。
///
/// 为什么住在 `KanpanCore`：图表包（KanpanChart）和 app 都要读写它，Core 是两者唯一的
/// 公共下层；而它用到的 `DrawArchive` / `DrawHistory` / 上限本来就在 Core。它只是内存里的
/// 纯模型——不碰文件、不碰 UIKit，落盘由 app 层接 `observe` 去做。
///
/// 两类改动分得很清：
///
/// - **本地编辑**（`commit` / `add` / `undo` / `redo`）：进撤销栈，报 `.edited`；
///   宿主据此落盘并通知提醒模块对账。
/// - **整批外部替换**（`replace`，换账号、云端推下来、单测灌数据）：上一套撤销步骤
///   撤回去会撤成别人数据的中间态，所以**真变了的那几桶**撤销栈一并清掉，报 `.replaced`；
///   不报 `.edited`——那一份不是本机改出来的，不该再落一遍盘、也不该让提醒去对账。
@MainActor
public final class DrawingBook {
  public enum Change: Sendable, Equatable {
    /// 这一桶被本机编辑过了（键是规范写法）。
    case edited(String)
    /// 这几桶被整批换掉了，撤销栈已清。
    case replaced(Set<String>)
  }

  public private(set) var archive: DrawArchive
  private var histories: [String: DrawHistory] = [:]
  /// 按订阅先后排：通知顺序确定，不随字典散列变。
  private var observers: [Observer] = []

  private struct Observer {
    weak var owner: AnyObject?
    var handler: @MainActor (Change) -> Void
  }

  public init(_ archive: DrawArchive = DrawArchive()) {
    self.archive = archive
  }

  // MARK: - 读

  public func items(_ symbol: String) -> [Drawing] { archive[symbol] }

  public func history(_ symbol: String) -> DrawHistory {
    histories[InstrumentID.canonical(symbol)] ?? DrawHistory()
  }

  /// 撤销栈整摞换掉。单测与迁移用；**空栈不占格子**——一轮下来路过几百个品种，
  /// 没画过线的不该留下任何东西。
  public func setHistory(_ history: DrawHistory, for symbol: String) {
    let key = InstrumentID.canonical(symbol)
    histories[key] = history.canUndo || history.canRedo ? history : nil
  }

  /// 画线偏好（样式、磁吸、连续画）跟着存档走，但改它不算「画线被编辑了」，不发通知。
  public var preferences: DrawingPreferences {
    get { archive.preferences }
    set { archive.preferences = newValue }
  }

  // MARK: - 上限

  /// 这一桶还能再放 `count` 条吗（每品种 `DrawArchive.perSymbolLimit` 条）。
  ///
  /// 上限是产品规矩，不是图的事：满了不画、也不偷偷挤掉最早那条——用户多半根本
  /// 没看见它被挤掉。提示由宿主定（`DrawingController.full`）。
  public func hasRoom(_ symbol: String, adding count: Int = 1) -> Bool {
    archive[symbol].count + count <= DrawArchive.perSymbolLimit
  }

  // MARK: - 本地编辑

  /// 把这一桶改成 `next`，改之前那份进撤销栈。没变就什么都不做，返回 `false`。
  @discardableResult
  public func commit(_ next: [Drawing], for symbol: String) -> Bool {
    let key = InstrumentID.canonical(symbol)
    let before = archive[key]
    guard next != before else { return false }
    var h = histories[key] ?? DrawHistory()
    h.commit(before: before)
    histories[key] = h
    archive[key] = next
    post(.edited(key))
    return true
  }

  /// 追加几条新线：一步撤销。容量不够时整批不写，返回 `false`；已有的 id 跳过。
  @discardableResult
  public func add(_ incoming: [Drawing], to symbol: String) -> Bool {
    let before = archive[symbol]
    let known = Set(before.map(\.id))
    let added = incoming.filter { !known.contains($0.id) }
    guard added.allSatisfy(\.isValid), hasRoom(symbol, adding: added.count) else { return false }
    guard !added.isEmpty else { return true }
    commit(before + added, for: symbol)
    return true
  }

  @discardableResult
  public func undo(_ symbol: String) -> Bool {
    let key = InstrumentID.canonical(symbol)
    guard var h = histories[key], let prev = h.undo(current: archive[key]) else { return false }
    histories[key] = h
    archive[key] = prev
    post(.edited(key))
    return true
  }

  @discardableResult
  public func redo(_ symbol: String) -> Bool {
    let key = InstrumentID.canonical(symbol)
    guard var h = histories[key], let next = h.redo(current: archive[key]) else { return false }
    histories[key] = h
    archive[key] = next
    post(.edited(key))
    return true
  }

  // MARK: - 整批外部替换

  /// 整本换掉（换账号、云端推下来）。
  ///
  /// 只有**真变了的桶**清撤销栈、进 `.replaced`：存档是所有品种共用的一份，别的设备上
  /// 给 ETH 画了一条线，BTC 这一桶一个字没动，就没有理由把人正在 BTC 上画的撤销栈抹掉
  /// （A-07）。`resetAllHistory` 给换账号用：上一个账号的撤销栈撤回去就是别人的数据。
  public func replace(_ next: DrawArchive, resetAllHistory: Bool = false) {
    let keys = Set(archive.bySymbol.keys).union(next.bySymbol.keys)
    var changed = Set(keys.filter { archive.bySymbol[$0] != next.bySymbol[$0] })
    if resetAllHistory {
      changed.formUnion(histories.keys)
      histories.removeAll()
    } else {
      for key in changed { histories[key] = nil }
    }
    archive = next
    if !changed.isEmpty { post(.replaced(changed)) }
  }

  /// 单独换一桶，撤销栈清掉。**不管值变没变都算一次替换**：调用方说的是「这张图换了一整套」。
  public func replace(_ items: [Drawing], for symbol: String) {
    let key = InstrumentID.canonical(symbol)
    archive[key] = items
    histories[key] = nil
    post(.replaced([key]))
  }

  /// 不进撤销栈、不发通知地把一桶摆成 `items`。
  ///
  /// 只给**没绑宿主的图**用：复盘回放那种图，线是外面按快照塞进 `ChartState` 的，
  /// 图私有的那一本只是跟着它走，谈不上「编辑」也谈不上「替换」。
  public func mirror(_ items: [Drawing], for symbol: String) {
    archive[InstrumentID.canonical(symbol)] = items
  }

  // MARK: - 观察

  /// 订阅变化。`owner` 释放了就自动退订；同一个 `owner` 再订一次会覆盖上一次。
  public func observe(_ owner: AnyObject, _ handler: @escaping @MainActor (Change) -> Void) {
    stopObserving(owner)
    observers.append(Observer(owner: owner, handler: handler))
  }

  public func stopObserving(_ owner: AnyObject) {
    observers.removeAll { $0.owner == nil || $0.owner === owner }
  }

  private func post(_ change: Change) {
    observers.removeAll { $0.owner == nil }
    for observer in observers { observer.handler(change) }
  }
}
