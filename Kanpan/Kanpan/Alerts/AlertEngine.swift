import Combine
import Foundation
import KanpanCore

/// 前台的到价判定：把一口一口的价折成 1 分钟桶，交给 `AlertEvaluator` 判。
///
/// **这是提醒在这台手机上唯一会响的那条路。** 服务端 `Backend/kanpan-api/src/alerts.rs`
/// 那份评估器判得更全（它订着币安的 1 分钟 K 线，不管用户开没开 app），但它最后一步是
/// APNs 推送，而这个项目没有 Apple 开发者会员、没有 APNs 密钥——服务端判到了只会把
/// `status=fired` 写进同步日志，用户得等下一次打开 app 拉同步才看得见。app 开着的时候
/// 要立刻响，就只能自己判一遍。这个类补的就是这一段：判定器
/// （`KanpanCore/Alerts/AlertEvaluator`）一直是对的，只是从来没有人叫它。
///
/// ## 为什么是 1 分钟桶，而不是图上那份 K 线
///
/// 图上那份（`MarketModel.series`）是**用户选的周期**。日线那一根的高低横跨一整天，
/// 拿它判 `.touch`，一条画在今天区间里的线会在用户切到日线的那一瞬间当场响——他并没有
/// 刚碰到它。服务端用的是 **1 分钟** K 线（`alerts.rs` 头注释），两边的规则要一字对一字，
/// 客户端就得自己有一份 1 分钟的东西。它从一口一口的成交价折出来，不额外订一条 K 线流。
///
/// 折出来的桶和交易所那根真的 1m K 线有一处不同，而且是**往保守那边差**：我们看到的是
/// 采样过的价（图上那只走逐笔、别的品种走 ticker 流大约一秒一帧），所以桶的高低
/// 可能比真 K 线的影线短一点。差的结果是**漏判**，不是误响——两根采样之间插进来的
/// 那根针可能判不到。这是有意的取舍（见下面「响不了的情况」）。
///
/// ## 和服务端会不会响两次
///
/// 不会，两道闸各挡一边：
/// - 本地这边 `AlertStore.markFired` 只认 `status == .active`，改完存档就不再是 active；
/// - 服务端那边 `record_fired` 的 `UPDATE … WHERE status='active'` 一行都改不到，
///   就直接返回、不写 op、也不推送（那段注释里写的就是「客户端前台先到了」这一种）。
///
/// 谁先谁后都只会有一次。慢的那一边后来拉到的那条 op 写的是同一个 `fired`，
/// 而 `AlertWatcher.announced` 按 id 记过了，不会再念第二遍；本地通知的 identifier 也是
/// `alert.<id>`，重复 `add` 只会覆盖同一条，通知中心里不会多出一条。
///
/// ## 响不了的情况（说清楚，别假装）
///
/// 1. **app 不在前台**：桶清空、流也停了。那一段归服务端判，用户下次开 app 拉同步时
///    由 `AlertWatcher` 补一条本地通知。
/// 2. **盘上没有这个品种的价**：判定只能判 `QuoteBook` 手上有价的那些。挂着活动提醒的
///    品种会被钉进它的订阅范围（`QuoteBook.setAlertedSymbols`），所以正常情况下都有；
///    但列表那条流本身要用户在前台、而且不在断网重连的空档里。
/// 3. **两次采样之间的针**：见上。
/// 4. **`.close` 那一档要连着两桶**：中间断过（切后台、断线、超过 `staleBuckets` 个
///    空桶）就把 `previousClose` 清掉，那一根不判——宁可漏一根，也不拿一个不知道是
///    哪一根的价去算穿越（`AlertEvaluator.Bar.previousClose` 的原话）。
@MainActor
final class AlertEngine: ObservableObject {
  /// 一分钟一桶——和服务端评估器订的那条 1m K 线对齐。
  static let bucketMs: Int64 = 60_000
  /// 中间空过这么多个桶之后，就不敢再把手上那口价当「上一根的收盘」了。
  ///
  /// 一分钟一口价都没有，可能是真没成交（那手上这口就还是收盘价），也可能是这条流
  /// 悄悄断了。五分钟以内按前者算，再久就把 `previousClose` 清掉。
  static let staleBuckets: Int64 = 5

  /// 正在长的那一分钟。
  private struct Bucket {
    var openTime: Int64
    var high: Double
    var low: Double
    var close: Double
    /// 上一个**已经收了的**桶的收盘价。断过就是 nil。
    var previousClose: Double?
  }

  private weak var store: AlertStore?
  private var bag: Set<AnyCancellable> = []
  private var buckets: [String: Bucket] = [:]
  /// 现在挂着活动提醒的那些品种（一律大写）。每一口价先过这一关——绝大多数 tick
  /// 在这儿就被挡掉了，不用去扫整张存档。
  private(set) var watched: Set<String> = []
  private var foreground = true

  /// 盘上要多订哪些品种。宿主接到 `QuoteBook.setAlertedSymbols(_:)`。
  var onWatchlist: ((Set<String>) -> Void)?

  func attach(_ store: AlertStore) {
    guard self.store !== store else { return }
    bag.removeAll()
    self.store = store
    settle(store.archive)
    store.$archive
      .receive(on: RunLoop.main)
      .sink { [weak self] archive in self?.settle(archive) }
      .store(in: &bag)
    // 复盘到点不看价，按钟判：前台每半分钟看一眼（日历通知只精确到分钟，这个粒度够）。
    Timer.publish(every: Self.dueTick, on: .main, in: .common)
      .autoconnect()
      .sink { [weak self] _ in self?.settleDue() }
      .store(in: &bag)
  }

  /// 前后台。`MainScreen` 那一处 `AppLifecycle` 把话递过来，和 `AlertWatcher` 同一拍。
  func setForeground(_ value: Bool) {
    guard value != foreground else { return }
    foreground = value
    // 断过就不算连着：回来那一下手上的桶既不完整，`previousClose` 也不知道是哪一根了。
    if !value { buckets.removeAll(keepingCapacity: true) }
    else { settleDue() }
  }

  // ---------------------------------------------------------------- 复盘到点

  static let dueTick: TimeInterval = 30

  /// 复盘到点那一种（`kind == .reviewDue`）：到了就标 `fired`，不带价。
  ///
  /// 和价格提醒同一道闸去重：服务端 `settle_due` 先到，本地这边 `markFired` 被
  /// `status == .active` 挡掉；本地先到，服务端那条 `UPDATE … WHERE status='active'`
  /// 一行都改不到。app 不在前台时不判——那一段归服务端和本机那条日历通知。
  func settleDue(now: Double = Date().timeIntervalSince1970 * 1000) {
    guard foreground, let store else { return }
    for alert in store.all where AlertEvaluator.dueHit(alert, now: now) {
      store.markFired(id: alert.id, at: now, price: nil)
    }
  }

  /// 存档变了：重算要盯的品种；刚同步下来、已经过了点的复盘到点当场判掉。
  private func settle(_ archive: AlertArchive) {
    if archive.alerts.contains(where: { $0.kind == .reviewDue && $0.isActive }) {
      // 下一拍再判：这一拍还在 `$archive` 的回调里，当场 `markFired` 就是在发布途中改它。
      Task { @MainActor [weak self] in self?.settleDue() }
    }
    let next = Set(
      archive.alerts
        .filter { $0.isActive && ($0.kind == .drawing || $0.kind == .price) && !$0.lines.isEmpty }
        .map { InstrumentID.canonical($0.symbol) }
        .filter { !$0.isEmpty })
    if next != watched {
      #if DEBUG
      let added = next.subtracting(watched)
      #endif
      watched = next
      #if DEBUG
      if !added.isEmpty { Task { @MainActor [weak self] in self?.feedTestTouch(added) } }
      #endif
      // 不再盯的品种把桶丢掉：留着只会在它重新挂上提醒时拿一段陈价当「上一根」。
      buckets = buckets.filter { next.contains($0.key) }
    }
    // **每次都报一遍，哪怕这一份和上一份一样。** 收话的那头
    // （`QuoteBook.setAlertedSymbols`）自己会挡住重复，而它在换档案时会把钉进去的
    // 那批清空——只有无条件重报，换号之后新的那份才一定回得去。
    onWatchlist?(next)
  }

  /// 再报一遍要盯的品种。换号之后宿主把新的自选表交给报价簿的同一拍上叫一次
  /// （`MainScreen.settleFavorites`）：那一刻报价簿刚把上一个人的那批清掉。
  func republishWatchlist() { onWatchlist?(watched) }

  // ---------------------------------------------------------------- 喂价

  /// 报价簿那一批（自选、看得见的行、以及被钉进来的提醒品种）。
  func observe(_ tickers: [Ticker]) {
    guard foreground, !watched.isEmpty else { return }
    for ticker in tickers { observe(symbol: ticker.symbol, price: ticker.last, timeMs: ticker.timeMs ?? 0) }
  }

  /// 一口价。`timeMs` 是交易所时刻，取不到就传 0，这儿用本机的顶上。
  ///
  /// 桶只是分钟对齐，差几十毫秒不影响判定；但交易所时刻能用就用——手机的钟比
  /// 交易所偏一点的时候，用本机时刻会把桶切在错的地方。
  func observe(symbol: String, price: Double, timeMs: Int64) {
    guard foreground, price.isFinite, price > 0 else { return }
    let key = InstrumentID.canonical(symbol)
    guard watched.contains(key) else { return }
    let stamp = timeMs > 0 ? timeMs : Int64(Date().timeIntervalSince1970 * 1000)
    guard stamp > 0 else { return }
    let open = stamp - stamp % Self.bucketMs

    guard let bucket = buckets[key] else {
      buckets[key] = Bucket(openTime: open, high: price, low: price, close: price, previousClose: nil)
      evaluateLive(key)
      return
    }
    if open == bucket.openTime {
      var next = bucket
      next.high = max(next.high, price)
      next.low = min(next.low, price)
      next.close = price
      buckets[key] = next
      evaluateLive(key)
      return
    }
    // 乱序：比手上这桶还早的一口价一概不要（`FeedComposer` 那儿也是这么挡的）。
    guard open > bucket.openTime else { return }
    // 桶换了 ⇒ 上一桶收了。先拿收了的那一根判一次（`.close` 只在这一刻有机会响），
    // 再开新桶。顺序不能反：反了就是拿这一根和自己比。
    closeOut(key, bucket: bucket)
    let gap = (open - bucket.openTime) / Self.bucketMs
    buckets[key] = Bucket(openTime: open, high: price, low: price, close: price,
                          previousClose: gap <= Self.staleBuckets ? bucket.close : nil)
    evaluateLive(key)
  }

  /// 盘中那一帧：只有 `.touch` 会在这儿响，`.close` 被 `isClosed == false` 挡在外面。
  private func evaluateLive(_ symbol: String) {
    guard let bucket = buckets[symbol] else { return }
    let bar = AlertEvaluator.Bar(openTime: Double(bucket.openTime), high: bucket.high, low: bucket.low,
                                 close: bucket.close, isClosed: false, previousClose: bucket.previousClose)
    evaluate(symbol, bar: bar, price: bucket.close)
  }

  /// 这一根收了。`.close` 在这儿判；`.touch` 再判一次是无害的——它要么在盘中那几帧
  /// 里已经响过（`once`，`markFired` 第二次进来会被 `status` 挡掉），要么这一根
  /// 压根不该它响（`armedAt` 之前开盘的）。
  private func closeOut(_ symbol: String, bucket: Bucket) {
    let bar = AlertEvaluator.Bar(openTime: Double(bucket.openTime), high: bucket.high, low: bucket.low,
                                 close: bucket.close, isClosed: true, previousClose: bucket.previousClose)
    evaluate(symbol, bar: bar, price: bucket.close)
  }

  /// 判一遍，响了就标 `fired`。
  ///
  /// 往下的整条路是现成的：`markFired` 走 `AlertStore.write` 那一个出口（落盘排在
  /// 同步存档之后，由写盘队列保证顺序），顺手 `onChange` → `AppAccountBridge.captureAlerts`
  /// 把这一版记账上行；`@Published archive` 一变，`AlertWatcher` 就震一下、让宿主说
  /// 一句「BTC 触到你画的趋势线 · 查看」，并在通知中心留一条。
  ///
  /// `firedPrice` 记的是**现价**，不是线价——和服务端 `fire(…, candle.close, at)`
  /// 一致，通知正文那句「现价 X」说的也是它。
  private func evaluate(_ symbol: String, bar: AlertEvaluator.Bar, price: Double) {
    guard let store, !store.all.isEmpty else { return }
    // 先取一份快照：`markFired` 会当场换掉 `archive`。
    let candidates = store.all.filter { $0.isActive && InstrumentID.canonical($0.symbol) == symbol }
    guard !candidates.isEmpty else { return }
    let now = Date().timeIntervalSince1970 * 1000
    for alert in candidates where AlertEvaluator.hit(alert, bar: bar) != nil {
      store.markFired(id: alert.id, at: now, price: price)
    }
  }

  // ---------------------------------------------------------------- 测试用

  #if DEBUG
  /// UI 用例「输一个价建提醒，然后它响了」要一段一定会碰到那个价的行情：真行情下一分钟
  /// 未必走到。启动环境 `KANPAN_TEST_ALERT_TOUCH=<代号>`（配 `KANPAN_TEST_PROFILE=1`）时，
  /// 这只品种一挂上裸价格提醒，就往它身上喂两口夹住目标价的价（高一点、低一点）。
  /// 时间戳放在一天以后：`armedAt` 那一关照样要过，真行情的帧全比它早、按乱序挡掉。
  /// 往下走的是和真行情完全一样的一条路：桶 → `AlertEvaluator.hit` → `markFired`
  /// → `AlertWatcher` 浮条 + 通知 → 总表「已触发」。
  private func feedTestTouch(_ symbols: Set<String>,
                             environment: [String: String] = ProcessInfo.processInfo.environment) {
    guard environment["KANPAN_TEST_PROFILE"] == "1",
          let symbol = environment["KANPAN_TEST_ALERT_TOUCH"].map(InstrumentID.canonical), symbols.contains(symbol),
          let store else { return }
    let future = Int64(Date().timeIntervalSince1970 * 1000) + 86_400_000
    for alert in store.all where alert.kind == .price && alert.isActive && InstrumentID.canonical(alert.symbol) == symbol {
      guard let target = alert.targetPrice else { continue }
      observe(symbol: symbol, price: target * 1.001, timeMs: future)
      observe(symbol: symbol, price: target * 0.999, timeMs: future + 1)
    }
  }

  /// 用例拿它看桶折得对不对（品种 → 开盘时刻/高/低/收/上一根收盘）。
  func bucketState(_ symbol: String) -> (openTime: Int64, high: Double, low: Double, close: Double, previousClose: Double?)? {
    guard let b = buckets[InstrumentID.canonical(symbol)] else { return nil }
    return (b.openTime, b.high, b.low, b.close, b.previousClose)
  }
  #endif
}
