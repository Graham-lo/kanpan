import Foundation

/// 「同一件事到底算了几遍」的计数口径（A6 第二轮审查：先测量再改）。
///
/// 十字线跟手时每移动一次就赋一次 `ChartView.state`，而 `ChartRenderer.recalc` 从前
/// 对**任何** state 变化都换一只新的 `GeometryCache`——指标输入一个没动，布局、价格
/// 区间、隐藏输出掩码却全部作废，下一帧再原样算一遍。这几个计数就是那笔账的读数：
/// 改之前它们跟着移动次数走，改之后应当恒定。
public enum ChartWork: String, Sendable, CaseIterable, CustomStringConvertible {
  /// 新建了一只输入层几何缓存（`ChartRenderer.InputCache`）：指标掩码、叠加线、
  /// 图例内缩、刻度字宽全部作废。只有 `state.input` 变了才会走。
  case geometryCache
  /// 新建了一只视野层几何缓存（`ChartRenderer.ViewportCache`）：布局、价格区间作废。
  /// 拖图、捏合、拖分隔线走这一档，输入层留着。
  case viewportCache
  /// `computeLayout` 真的跑了一趟（轴宽要量字、还要先求一次价格区间）。
  case layout
  /// `KanpanCore.priceRange` 真的扫了一趟可见段。
  case priceRange
  /// 隐藏输出那条整列 NaN 掩码真的分配了一次。
  case hiddenMask
  /// `ChartView.onCrosshairChanged` 真的回调了一次。
  case crosshairCallback

  public var description: String { rawValue }
}

/// 计数器本体。**只有 DEBUG 才有存储**，Release 下 `bump` 是一个空函数体、计数一律读 0，
/// 热路径上不留任何开销。
///
/// 计数按**线程**分开记（`Thread.threadDictionary`）：测试是并行跑的，别的套件也在造
/// 渲染器，记在一个全局桶里的话谁的账都算不清；而十字线这条路本来就全在主线程上，
/// 按线程记既够用又不用加锁。
public enum ChartWorkCounter {
  #if DEBUG
  private static let slot = "kanpan.chartWorkCounter"

  private static func table() -> NSMutableDictionary {
    let thread = Thread.current.threadDictionary
    if let hit = thread[slot] as? NSMutableDictionary { return hit }
    let fresh = NSMutableDictionary()
    thread[slot] = fresh
    return fresh
  }
  #endif

  @inline(__always)
  public static func bump(_ kind: ChartWork) {
    #if DEBUG
    let t = table()
    t[kind.rawValue] = ((t[kind.rawValue] as? Int) ?? 0) + 1
    #endif
  }

  /// 本线程上这件事算了几遍。
  public static func count(_ kind: ChartWork) -> Int {
    #if DEBUG
    return (table()[kind.rawValue] as? Int) ?? 0
    #else
    return 0
    #endif
  }

  public static func reset() {
    #if DEBUG
    table().removeAllObjects()
    #endif
  }

  public static func snapshot() -> [ChartWork: Int] {
    #if DEBUG
    var out: [ChartWork: Int] = [:]
    for kind in ChartWork.allCases { out[kind] = count(kind) }
    return out
    #else
    return [:]
    #endif
  }

  /// 一行能 grep 的读数：`CHARTWORK <label> geometryCache=0 layout=0 ...`
  public static func line(_ label: String) -> String {
    let body = ChartWork.allCases.map { "\($0.rawValue)=\(count($0))" }.joined(separator: " ")
    return "CHARTWORK \(label) \(body)"
  }
}
