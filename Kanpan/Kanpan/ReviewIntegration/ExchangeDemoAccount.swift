#if DEBUG
import Foundation
import KanpanCore

/// 测试沙盒里的交易所账户（只在 DEBUG 包里，Release 里一行都没有）。
///
/// `KANPAN_TEST_PROFILE=1` + `KANPAN_PERSISTENCE_PROFILE=<UUID>` 时，Key、同步状态、回合
/// 都换到这一轮测试自己的位置（Keychain service 与文件夹都带着那个 UUID），不碰这台机器上
/// 真正接着的账户。再加 `KANPAN_EXCHANGE_FIXTURE=1` 就连交易所也换成一份写死的演示账户
/// （`ExchangeDemoProvider`）——没有真 Key 也能把接入、拒收、同步、复盘本整条路走通。
/// `KANPAN_EXCHANGE_FIXTURE_KEY=<任意串>` 让它一启动就接上。
enum ExchangeDemoAccount {
  struct Setup {
    let store: ExchangeCredentialStore
    let stateURL: URL
    let roundsURL: URL
    let fixture: Bool
    let autoKey: String?
  }

  static func setup(venue: ExchangeAccountRegistry.Venue) -> Setup? {
    let env = ProcessInfo.processInfo.environment
    guard env["KANPAN_TEST_PROFILE"] == "1", let raw = env["KANPAN_PERSISTENCE_PROFILE"],
          let uuid = UUID(uuidString: raw) else { return nil }
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let folder = base.appendingPathComponent("kanpan/tests/\(uuid.uuidString)", isDirectory: true)
    let key = env["KANPAN_EXCHANGE_FIXTURE_KEY"].flatMap { $0.isEmpty ? nil : $0 }
    return Setup(store: ExchangeCredentialStore(service: "kanpan.exchange.tests.\(uuid.uuidString)"),
                 stateURL: folder.appendingPathComponent("exchange-\(venue.venue)-\(venue.market).json"),
                 roundsURL: folder.appendingPathComponent("exchange-rounds-\(venue.venue)-\(venue.market).json"),
                 fixture: env["KANPAN_EXCHANGE_FIXTURE"] == "1", autoKey: key)
  }
}

/// 演示账户：上周三个平掉的回合（一只多头加过一次仓、一只空头带一笔资金费、一只多头），
/// 外加昨晚开的一只空头至今没平。成交价取那一刻的真实行情（取不到用一个固定价），
/// 所以复盘图上的箭头落在真 K 线上。
///
/// Key 里带 `TRADE` 当成开着交易权限（拒收），带 `OFFLINE` 当成断网，带 `BAD` 当成 Key 不对。
struct ExchangeDemoProvider: ExchangeAccountProvider {
  let venue: String
  let market: String
  let credentials: ExchangeCredentials
  let priceAt: @Sendable (String, Int64) async -> Double?

  init(venue: ExchangeAccountRegistry.Venue, credentials: ExchangeCredentials,
       priceAt: @escaping @Sendable (String, Int64) async -> Double?) {
    self.venue = venue.venue; self.market = venue.market
    self.credentials = credentials; self.priceAt = priceAt
  }

  func verifyReadOnly() async throws {
    try await Task.sleep(for: .milliseconds(400))
    let key = credentials.apiKey.uppercased()
    if key.contains("TRADE") { throw ExchangeAccountError.notReadOnly }
    if key.contains("OFFLINE") { throw ExchangeAccountError.offline }
    if key.contains("BAD") { throw ExchangeAccountError.invalidKey }
  }

  private struct Leg {
    let id: String, symbol: String, hour: Int64, side: TradeSide, notional: Double, qtyDigits: Int
    let closes: String?
  }

  func fetch(from: Int64, to: Int64) async throws -> ExchangeAccountBatch {
    if credentials.apiKey.uppercased().contains("OFFLINE") { throw ExchangeAccountError.offline }
    let calendar = Calendar.current
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    let (lastMonday, _) = WeeklyReport.lastWeekBounds(now: now, calendar: calendar)
    let today = Int64(calendar.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
    let hour: Int64 = 3_600_000
    // 时刻都按整点：同一天里反复拉，成交 id 与时刻不变，回合 id 也就不变。
    let legs: [Leg] = [
      Leg(id: "d1", symbol: "BTCUSDT", hour: 24 + 10, side: .buy, notional: 6000, qtyDigits: 3, closes: nil),
      Leg(id: "d2", symbol: "BTCUSDT", hour: 24 + 14, side: .buy, notional: 6000, qtyDigits: 3, closes: nil),
      Leg(id: "d3", symbol: "BTCUSDT", hour: 48 + 9, side: .sell, notional: 0, qtyDigits: 3, closes: "d1,d2"),
      Leg(id: "d4", symbol: "ETHUSDT", hour: 72 + 20, side: .sell, notional: 5000, qtyDigits: 2, closes: nil),
      Leg(id: "d5", symbol: "ETHUSDT", hour: 96 + 2, side: .buy, notional: 0, qtyDigits: 2, closes: "d4"),
      Leg(id: "d6", symbol: "SOLUSDT", hour: 120 + 9, side: .buy, notional: 4000, qtyDigits: 0, closes: nil),
      Leg(id: "d7", symbol: "SOLUSDT", hour: 120 + 15, side: .sell, notional: 0, qtyDigits: 0, closes: "d6"),
    ]
    let fallback: [String: Double] = ["BTCUSDT": 60000, "ETHUSDT": 3000, "SOLUSDT": 150]
    var opened: [String: (qty: Double, price: Double, side: TradeSide)] = [:]
    var fills: [Fill] = []
    func round(_ value: Double, _ digits: Int) -> Decimal {
      Decimal(string: String(format: "%.\(digits)f", value)) ?? Decimal(value)
    }
    func make(_ id: String, _ symbol: String, _ time: Int64, _ side: TradeSide, _ price: Double,
              _ qty: Double, _ digits: Int, pnl: Double) -> Fill {
      let p = round(price, 2), q = round(qty, digits)
      let fee = round(price * qty * 0.0005, 4)
      return Fill(id: id, orderId: "o-\(id)", symbol: symbol, time: time, side: side, positionSide: .both,
                  price: p, qty: q, commission: fee, commissionAsset: "USDT",
                  realizedPnl: round(pnl, 4), maker: false, marginAsset: "USDT")
    }
    for leg in legs {
      let time = lastMonday + leg.hour * hour
      let price = await priceAt(leg.symbol, time) ?? fallback[leg.symbol] ?? 1
      if let closes = leg.closes {
        let parts = closes.split(separator: ",").compactMap { opened.removeValue(forKey: String($0)) }
        var pnl = 0.0, qty = 0.0
        for part in parts {
          qty += part.qty
          pnl += (part.side == .buy ? price - part.price : part.price - price) * part.qty
        }
        fills.append(make(leg.id, leg.symbol, time, leg.side, price, qty, leg.qtyDigits, pnl: pnl))
      } else {
        let factor = pow(10, Double(leg.qtyDigits))
        let qty = max(1 / factor, (leg.notional / price * factor).rounded() / factor)
        opened[leg.id] = (qty, (price * 100).rounded() / 100, leg.side)
        fills.append(make(leg.id, leg.symbol, time, leg.side, price, qty, leg.qtyDigits, pnl: 0))
      }
    }
    // 昨晚 20:00 开的空头，至今没平。
    let openTime = today - 4 * hour
    let openPrice = await priceAt("BTCUSDT", openTime) ?? 60000
    let openQty = max(0.001, (3000 / openPrice * 1000).rounded() / 1000)
    fills.append(make("d8", "BTCUSDT", openTime, .sell, openPrice, openQty, 3, pnl: 0))
    let funding = [FundingEntry(id: "f1", symbol: "ETHUSDT", time: lastMonday + (96 + 0) * hour,
                                amount: Decimal(string: "-0.8")!, asset: "USDT")]
    return ExchangeAccountBatch(
      fills: fills.filter { $0.time >= from && $0.time <= to },
      funding: funding.filter { $0.time >= from && $0.time <= to },
      leverage: ["BTCUSDT": 10, "ETHUSDT": 5, "SOLUSDT": 3],
      markPrices: [:],
      positions: [PositionKey(symbol: "BTCUSDT", positionSide: .both): -Decimal(string: String(format: "%.3f", openQty))!])
  }
}
#endif
