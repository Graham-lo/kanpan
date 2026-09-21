import Foundation

/// 判一条提醒这一根 K 线响不响。
///
/// 前台和服务端（`Backend/kanpan-api/src/alerts.rs`）各跑一份，规则必须一样，所以规则
/// 写在这儿、两边照着同一段文字实现：
///
/// 1. 这条提醒还在等（`status == .active`）；
/// 2. 它是图上那条线长出来的（`kind == .drawing`）——别的种类见下面那条闸；
/// 3. 这一根的开盘时刻不早于 `armedAt`——挪过线之后 `armedAt` 重置成现在，
///    历史 K 线不会把刚挪好的线当场判成已触发；
/// 4. 线在这一刻有价（落在线外、那一头又没延长的，不算）；
/// 5. 然后按 `condition` 分两种：
///    - `.touch`：这一根的最低 ≤ 线价 ≤ 最高。盘中帧也算，碰到就是碰到。
///    - `.close`：**这一根真的收了**（币安 kline 帧里的 `k.x == true`），而且
///      「上一根已收盘的收盘价」与「这一根的收盘价」分别落在线的两侧。
///
/// `.close` 为什么要两个点：只看当前收盘价在线的哪一侧，第一次评估就会把「一直在线
/// 上方」误判成「刚刚穿上去」。穿越要有前后两个状态才成立。**正好收在线上算穿过**
/// （从严格的一侧走到线上，用户眼里那就是穿到了），但从线上走开不算——那一下在上一根
/// 就已经算过了。盘中来回穿、穿完又收回去的，一概不算：那正是用户选这一档想避开的。
///
/// 线价对趋势线这类提醒是随时间变的，`.touch` 与 `.close` 取的是**同一个**值：
/// 线在这一根 K 线开盘时刻上的价。两根收盘价都跟它比。
public enum AlertEvaluator {

  /// 一根 K 线里提醒关心的那几个数。
  ///
  /// 前三个 `.touch` 就够了；后三个是 `.close` 要的，`.touch` 一概不看，所以它们有
  /// 出厂值——老的三参数写法照样能用。
  public struct Bar: Sendable, Equatable {
    /// 开盘时刻（毫秒）。线在这一刻的价就是这一根拿去比的价。
    public var openTime: Double
    public var high: Double
    public var low: Double
    /// 这一根的收盘价。盘中帧里它是「此刻的价」，收了之后才是真正的收盘价。
    public var close: Double?
    /// 这一根真的收了吗——币安 kline 帧里的 `k.x`。盘中帧是 `false`。
    public var isClosed: Bool
    /// 上一根**已经收了的** K 线的收盘价。没有（刚开始盯、或者中间断过线）就是 nil，
    /// 那时 `.close` 不判——宁可漏一根，也不拿一个不知道是哪一根的价去算穿越。
    public var previousClose: Double?

    public init(openTime: Double, high: Double, low: Double,
                close: Double? = nil, isClosed: Bool = false, previousClose: Double? = nil) {
      self.openTime = openTime; self.high = high; self.low = low
      self.close = close; self.isClosed = isClosed; self.previousClose = previousClose
    }
  }

  /// 响了的话，响在哪条线、哪个价上。
  public struct Hit: Sendable, Equatable {
    /// `alert.lines` 里的下标。
    public var line: Int
    /// 线在这一刻的价（不是现价；现价由调用方另外带）。
    public var price: Double
    public init(line: Int, price: Double) {
      self.line = line; self.price = price
    }
  }

  public static func hit(_ alert: Alert, bar: Bar) -> Hit? {
    guard alert.status == .active else { return nil }
    // **`.price` / `.reviewDue` 在这里被显式挡住，不是悄悄落进 else。**
    //
    // `.reviewDue` 本来就不是价格提醒：它是复盘待办到点，走本地排程的时间通知，
    // 跟 K 线没有关系，落到这儿只会是调用方传错了。
    //
    // `.price`（裸价格「到价提醒」）是另一回事：它在协议白名单与值规则里都有位置
    // （`Alert.Kind` / 服务端 `sync.rs` 的 `ALERT_FIELDS`），但**客户端没有任何入口
    // 能产生它**——表 2.2 也没有给它一个放目标价的字段，目标价只能挂在 `lines` 里，
    // 而那套几何是画线摊出来的。所以现在它是一种存得下、永远不会出现的东西。
    // 谁要开这个入口：**先在这里（以及服务端 `alerts.rs` 的同一处）把判定实现掉，
    // 再去开界面**，否则用户又会拿到一条界面答应了、评估器不认的死提醒。
    guard alert.kind == .drawing else { return nil }
    guard bar.openTime >= alert.armedAt else { return nil }
    switch alert.condition {
    case .touch: return touchHit(alert, bar: bar)
    case .close: return closeHit(alert, bar: bar)
    }
  }

  /// `.touch`：这一根的 `[low, high]` 夹住线价。
  private static func touchHit(_ alert: Alert, bar: Bar) -> Hit? {
    guard bar.high.isFinite, bar.low.isFinite else { return nil }
    let lo = min(bar.low, bar.high), hi = max(bar.low, bar.high)
    for (i, line) in alert.lines.enumerated() {
      guard let p = line.price(at: bar.openTime), p.isFinite else { continue }
      if p >= lo, p <= hi { return Hit(line: i, price: p) }
    }
    return nil
  }

  /// `.close`：这一根收了，而且两根收盘价分别在线的两侧。
  private static func closeHit(_ alert: Alert, bar: Bar) -> Hit? {
    // 没收的那一根一个字都不判——盘中价格来回穿正是这一档要避开的东西。
    guard bar.isClosed else { return nil }
    guard let close = bar.close, close.isFinite else { return nil }
    guard let previous = bar.previousClose, previous.isFinite else { return nil }
    for (i, line) in alert.lines.enumerated() {
      guard let p = line.price(at: bar.openTime), p.isFinite else { continue }
      if crosses(previous: previous, close: close, line: p) { return Hit(line: i, price: p) }
    }
    return nil
  }

  /// 上一根收在线的某一侧，这一根收到了另一侧或者正好收在线上。
  ///
  /// `previous == line` 时一律 `false`：上一根就已经在线上了，那一下该由上一根去响
  /// （提醒 `once`，响完就是 `fired`），在这儿再响一次就是重复。
  static func crosses(previous: Double, close: Double, line: Double) -> Bool {
    (previous < line && close >= line) || (previous > line && close <= line)
  }

  public static func fires(_ alert: Alert, bar: Bar) -> Bool { hit(alert, bar: bar) != nil }

  /// 现价离这条提醒最近的那条线有多远，按比例（0.008 就是 0.8%）。
  ///
  /// 自选页的「离提醒线最近」用它。取不到价（线在别的时间段上、两端又不延）的
  /// 那些线跳过；一条都取不到就返回 nil，那一行不显示副标题、排在最后。
  public static func distance(from price: Double, to alert: Alert, at t: Double) -> Double? {
    guard alert.isActive, price > 0, price.isFinite else { return nil }
    var best: Double?
    for line in alert.lines {
      guard let p = line.price(at: t), p.isFinite else { continue }
      let d = abs(p - price) / price
      if best == nil || d < best! { best = d }
    }
    return best
  }

  /// 一组提醒里离现价最近的那个距离。
  public static func nearestDistance(from price: Double, among alerts: [Alert], at t: Double) -> Double? {
    alerts.compactMap { distance(from: price, to: $0, at: t) }.min()
  }
}
