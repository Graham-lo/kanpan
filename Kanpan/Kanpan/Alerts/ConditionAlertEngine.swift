import Foundation
import KanpanCore
import KanpanNetwork

/// 条件提醒（费率 / 持仓量 / 均线 / 大单墙）的前台判定。
///
/// 条件提醒的主判定在服务端（`docs/条件提醒-协议-2026-09-27.md` 第 2 节，worker 的 `conditions`
/// 任务）；app 在前台时自己也按同一套口径判一遍（`ConditionJudge`，纯函数和服务端一字不差），
/// **谁先判到谁响**：判到了就 `AlertStore.markFired(id:observation:)`，靠 `status == .active` 那道闸
/// 只响一次——服务端先响，同步下来的是已触发，这边 `markFired` 什么也不做；这边先响，标记跟着
/// 同步上去，服务端的 `record_fired` 同样被 `status='active'` 挡掉。
///
/// 数据从哪儿来（拿不到就不判，交给服务端）：
/// - **费率**：`FundingBook` 知道每只的下一次结算时刻；进了结算前 15 分钟的窗口，单品种接口问一口
///   最新预测费率判一次，每个结算点每条提醒只判一次。
/// - **持仓量**：`openInterestHist` 5m，每段结束 30 s 后拉 13 个点，最新点与恰好 1 小时前的点比，
///   同一个点只判一次；没拿到新点每 30 s 再问。
/// - **均线**：每根收盘 2 s 后拉 K 线（N + 2 根），去掉没收盘的那根，按边沿判；拿不到收盘那根每 5 s
///   再问，60 s 放弃这一根。
/// - **大单墙**：只看图上那只、且开着主力订单流时的聚合簿（`OrderFlowLink.snapshot`），
///   武装后第一次看到时的老墙记基线不响。
///
/// 只走币安本家的数据（网关线路上币安被替身顶着时不判——替身的费率、持仓量与币安不是一回事）。
/// 只在前台跑；后台交给服务端。
@MainActor
final class ConditionAlertEngine {
  /// 多久醒一次。各条件自己的节奏由下面的「下一次什么时候问」管，这只是最细的那一格。
  static let tick: Duration = .seconds(5)
  static let oiDelayMs: Double = 30_000
  static let oiRetryMs: Double = 30_000
  static let maDelayMs: Double = 2_000
  static let maRetryMs: Double = 5_000
  static let maGiveUpMs: Double = 60_000
  /// 簿里的结算时刻多旧还能拿来定窗口。
  static let fundingBookAge: TimeInterval = 30 * 60

  private weak var store: AlertStore?
  private var loop: Task<Void, Never>?
  private var foreground = true
  private var busy = false

  /// 某个品种此刻的价（通知正文、`firedPrice` 用）。宿主给：图上那只与报价簿。
  var price: (String) -> Double? = { _ in nil }
  /// 图上那只的主力订单流聚合簿（关着就是 nil）。
  var orderFlow: () -> OrderFlowSnapshot? = { nil }
  /// 取数的提供者；测试可以换。
  var provider: (String) -> any MarketProvider = { RouteResolver.current.provider(forSymbol: $0) }

  // 判过哪一次：按提醒 id 记。
  private var fundingJudged: [String: Double] = [:]
  private var oiJudged: [String: Double] = [:]
  private var maJudged: [String: Double] = [:]
  /// 大单墙的基线：武装时刻 + 那一刻的老墙。武装时刻变了（编辑过）就重取。
  private var wallBaselines: [String: (armedAt: Double, keys: Set<String>)] = [:]
  // 下一次什么时候问：持仓量按品种，均线按「品种|周期」。
  private var oiNext: [String: Double] = [:]
  private var oiLastPoint: [String: Double] = [:]
  private var maNext: [String: Double] = [:]
  private var maExpected: [String: Double] = [:]

  func attach(_ store: AlertStore) {
    guard self.store !== store else { return }
    self.store = store
    reset()
    start()
  }

  func setForeground(_ value: Bool) {
    guard value != foreground else { return }
    foreground = value
    if value { start() } else { loop?.cancel(); loop = nil }
  }

  /// 换档案（登录 / 退登）时忘掉判过的记录。
  func reset() {
    fundingJudged.removeAll(); oiJudged.removeAll(); maJudged.removeAll(); wallBaselines.removeAll()
    oiNext.removeAll(); oiLastPoint.removeAll(); maNext.removeAll(); maExpected.removeAll()
  }

  private func start() {
    guard foreground, loop == nil else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        await self?.step()
        try? await Task.sleep(for: Self.tick)
      }
    }
  }

  /// 现在还挂着的、认得的条件提醒。
  private var armed: [Alert] {
    (store?.all ?? []).filter { $0.kind == .condition && $0.isActive && $0.rule?.isKnown == true }
  }

  private func step() async {
    guard foreground, !busy else { return }
    let alerts = armed
    forgetGone(alerts)
    guard !alerts.isEmpty else { return }
    busy = true
    defer { busy = false }
    let now = Date().timeIntervalSince1970 * 1000
    judgeWalls(alerts, now: now)
    await judgeFunding(alerts, now: now)
    await judgeOpenInterest(alerts, now: now)
    await judgeMA(alerts, now: now)
  }

  private func forgetGone(_ alerts: [Alert]) {
    let ids = Set(alerts.map(\.id))
    for id in Array(fundingJudged.keys) where !ids.contains(id) { fundingJudged[id] = nil }
    for id in Array(oiJudged.keys) where !ids.contains(id) { oiJudged[id] = nil }
    for id in Array(maJudged.keys) where !ids.contains(id) { maJudged[id] = nil }
    for id in Array(wallBaselines.keys) where !ids.contains(id) { wallBaselines[id] = nil }
  }

  /// 本家的提供者（条件提醒只建在 `Alert.market` 上，本家就是服务端判的那一家）；
  /// 网关线路下被替身顶着（`upstream ≠ venue`，数据是别家的）就 nil，交给服务端判。
  private func binance(_ symbol: String) -> (any MarketProvider)? {
    let p = provider(symbol)
    return p.capabilities.upstream == p.capabilities.venue ? p : nil
  }

  private func fire(_ alert: Alert, _ observation: ConditionObservation) {
    guard let store, store.all.contains(where: { $0.id == alert.id && $0.isActive }) else { return }
    store.markFired(id: alert.id, observation: observation)
  }

  private func currentPrice(_ symbol: String, provider: any MarketProvider) async -> Double {
    if let p = price(symbol), p.isFinite, p > 0 { return p }
    return (try? await provider.ticker24h(symbol: symbol, timeout: 5).last) ?? 0
  }

  // ---------------------------------------------------------------- 费率

  private func judgeFunding(_ alerts: [Alert], now: Double) async {
    for alert in alerts {
      guard case let .funding(side, rate) = alert.rule, let p = binance(alert.symbol) else { continue }
      let key = InstrumentID.canonical(alert.symbol)
      guard let next = FundingBook.shared.entry(for: key, upstream: p.capabilities.upstream, maxAge: Self.fundingBookAge)?
        .nextFundingTimeMs.map(Double.init) else {
        FundingBook.shared.refreshIfStale(provider: p)
        continue
      }
      // 结算时刻过了，簿还停在上一期：催它换表，这一拍不判。
      if next <= now { FundingBook.shared.refreshIfStale(provider: p); continue }
      guard ConditionJudge.inFundingWindow(now: now, nextFunding: next, armedAt: alert.armedAt),
            fundingJudged[alert.id] != next else { continue }
      guard let fresh = try? await p.funding(symbol: key) else { continue }
      let settle = fresh.nextFundingTimeMs.map(Double.init) ?? next
      guard settle == next else { continue }
      fundingJudged[alert.id] = next
      FundingBook.shared.note(rate: fresh.rate, nextFundingTimeMs: fresh.nextFundingTimeMs, for: key,
                              upstream: p.capabilities.upstream)
      let at = Date().timeIntervalSince1970 * 1000
      let mark = await currentPrice(key, provider: p)
      if let hit = ConditionJudge.funding(side: side, rate: rate, predicted: Decimal(string: String(fresh.rate)) ?? Decimal(fresh.rate),
                                          mark: mark, nextFunding: next, now: at) {
        fire(alert, hit)
      }
    }
  }

  // ---------------------------------------------------------------- 持仓量

  private func judgeOpenInterest(_ alerts: [Alert], now: Double) async {
    let bySymbol = Dictionary(grouping: alerts.filter {
      if case .openInterestChange = $0.rule { true } else { false }
    }) { InstrumentID.canonical($0.symbol) }
    for (key, group) in bySymbol {
      guard now >= oiNext[key] ?? 0, let p = binance(key), p.capabilities.hasOpenInterestHistory else { continue }
      guard let raw = try? await p.openInterestHist(symbol: key, period: "5m", limit: 13, startTime: nil, endTime: nil),
            let last = raw.map(\.time).max() else {
        oiNext[key] = now + Self.oiRetryMs
        continue
      }
      let lastAt = Double(last)
      // 没出新点：30 s 后再问；出了新点就等下一段结束（整 5 分钟）后 30 s。
      if oiLastPoint[key] == lastAt {
        oiNext[key] = now + Self.oiRetryMs
      } else {
        let boundary = (now / ConditionJudge.oiPeriodMs).rounded(.down) * ConditionJudge.oiPeriodMs
        oiNext[key] = boundary + ConditionJudge.oiPeriodMs + Self.oiDelayMs
      }
      oiLastPoint[key] = lastAt
      let points = raw.map { ConditionJudge.OIPoint(at: Double($0.time), amount: $0.value) }
      var price: Double?
      for alert in group {
        guard case let .openInterestChange(threshold) = alert.rule, oiJudged[alert.id] != lastAt,
              lastAt >= alert.armedAt else { continue }
        oiJudged[alert.id] = lastAt
        if price == nil { price = await currentPrice(key, provider: p) }
        if let hit = ConditionJudge.openInterest(threshold: threshold, points: points, armedAt: alert.armedAt,
                                                 price: price ?? 0, now: Date().timeIntervalSince1970 * 1000) {
          fire(alert, hit)
        }
      }
    }
  }

  // ---------------------------------------------------------------- 均线

  private func judgeMA(_ alerts: [Alert], now: Double) async {
    let byKey = Dictionary(grouping: alerts.compactMap { alert -> (String, Interval, Alert)? in
      guard case let .maCross(raw, _, _) = alert.rule, let interval = Interval(rawValue: raw) else { return nil }
      return (InstrumentID.canonical(alert.symbol), interval, alert)
    }) { $0.0 + "|" + $0.1.rawValue }
    for (slot, items) in byKey {
      guard now >= maNext[slot] ?? 0, let (key, interval, _) = items.first, let p = binance(key) else { continue }
      let longest = items.compactMap { if case let .maCross(_, n, _) = $0.2.rule { n } else { nil } }.max() ?? 1
      guard let bars = try? await p.klines(symbol: key, interval: interval, limit: min(longest + 2, 1500)),
            !bars.isEmpty else {
        maNext[slot] = now + Self.maRetryMs
        continue
      }
      let at = Date().timeIntervalSince1970 * 1000
      let closed = bars.map {
        ConditionJudge.ClosedBar(openTime: Double($0.openTime), close: $0.close,
                                 closeTime: Self.closeTime(openTime: $0.openTime, interval: interval))
      }.filter { $0.closeTime <= at }
      // 下一根什么时候收：没收盘那根的收盘时刻；都收了就按最后一根往后推一格。
      let lastEnd = bars.last.map { Self.closeTime(openTime: $0.openTime, interval: interval) } ?? at
      let nextClose = lastEnd > at ? lastEnd : Self.closeTime(openTime: Int64(lastEnd), interval: interval)
      // 该收的那根没到（交易所还没吐出来）：每 5 s 再问，过了 60 s 放弃这一根。
      if let expected = maExpected[slot], (closed.last?.closeTime ?? 0) < expected, at < expected + Self.maGiveUpMs {
        maNext[slot] = at + Self.maRetryMs
        continue
      }
      maExpected[slot] = nextClose
      maNext[slot] = nextClose + Self.maDelayMs
      guard let last = closed.last else { continue }
      for (_, _, alert) in items {
        guard case let .maCross(_, length, side) = alert.rule, maJudged[alert.id] != last.closeTime else { continue }
        maJudged[alert.id] = last.closeTime
        if let hit = ConditionJudge.maCross(length: length, side: side, bars: closed, armedAt: alert.armedAt, now: at) {
          fire(alert, hit)
        }
      }
    }
  }

  /// 一根 K 线的收盘时刻：开盘 + 周期；月线按日历月。
  static func closeTime(openTime: Int64, interval: Interval) -> Double {
    guard interval == .mo1 else { return Double(openTime + interval.stepMs) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let start = Date(timeIntervalSince1970: Double(openTime) / 1000)
    let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start.addingTimeInterval(30 * 86_400)
    return end.timeIntervalSince1970 * 1000
  }

  // ---------------------------------------------------------------- 大单墙

  private func judgeWalls(_ alerts: [Alert], now: Double) {
    guard let snapshot = orderFlow(), snapshot.phase == .ready else { return }
    let key = InstrumentID.canonical(snapshot.symbol)
    let walls = snapshot.orders.filter { $0.status == .live && $0.endMs == nil }.map {
      ConditionJudge.Wall(key: $0.id, exchange: $0.exchange, product: $0.product.rawValue, side: $0.side.rawValue,
                          price: $0.price, notional: $0.notional, firstSeen: Double($0.firstSeenMs))
    }
    for alert in alerts where InstrumentID.canonical(alert.symbol) == key {
      guard case let .orderflowWall(text) = alert.rule,
            let threshold = AlertRule.decimal(text).map({ NSDecimalNumber(decimal: $0).doubleValue }) else { continue }
      guard let base = wallBaselines[alert.id], base.armedAt == alert.armedAt else {
        wallBaselines[alert.id] = (alert.armedAt, ConditionJudge.wallBaseline(walls: walls, threshold: threshold,
                                                                                armedAt: alert.armedAt))
        continue
      }
      if let hit = ConditionJudge.wall(threshold: threshold, walls: walls, baseline: base.keys,
                                       armedAt: alert.armedAt, now: now) {
        fire(alert, hit)
      }
    }
  }
}
