import Foundation
import KanpanCore

/// 复盘待办到点，进提醒系统（P3.1）。
///
/// 复盘记录自己带着到期时刻（记一笔时必填的「到期」）。这儿把每一条还在等答案的记录
/// 兑现成一条 `kind == .reviewDue` 的提醒：进提醒总表、跟着账号同步上去，服务端
/// `alerts.rs` 到点把它置成 `fired` 并推送；本机 `ReviewDueNotifications` 另排一条
/// 日历通知当双保险（没有 APNs 密钥的现在，app 关着时响的是那一条）。
///
/// **提醒的 id 由记录 id 定死**（`"r" + 记录 UUID`）：同一条记录不管在哪台手机上生成，
/// 都是同一个对象，同步下来是覆盖不是多一条。
///
/// 只认列表里有的记录做增删改，不认「列表里没有」——复盘那份存档在换号、刚启动时会短暂
/// 是空的，拿一张空表对账会把全部到点提醒删一遍又建一遍。所以「记录不见了」只在到点
/// 已经过去一天之后才清。
///
/// 这一件只吃 `KanpanCore`：复盘记录（`ReviewDomain.ReviewRecord`）由宿主先折成 `Item`
/// 再交进来，好让提醒模块的测试壳（`Kanpan/Alerts`）不必链复盘那一摊。
enum ReviewDueAlerts {
  /// 到点之后留多久再自动清掉（毫秒）：一天。这一天里它在总表「已触发」那一堆里，
  /// 点得开那条记录；再往后就只是噪音。
  static let keepAfterDue: Double = 86_400_000

  /// 一条复盘记录里提醒要用的那几样。
  struct Item: Equatable, Sendable {
    /// 记录 id（UUID 串）。
    var id: String
    var symbol: String
    /// 到期时刻（毫秒）。
    var dueAt: Double
    /// 「BTC」这种短名，拼标题用。
    var short: String
    /// 还在等答案（没判、没作废、不是只记录）。
    var waiting: Bool
    /// 这条记录能不能挂进提醒：只有币安 U 本位合约的记录（提醒对象的 id 形态
    /// `binance/usd_m/<代号>/…` 只认这一个市场）。
    var eligible: Bool
  }

  /// 要做的账：建或改哪些、删哪些。
  struct Plan: Equatable, Sendable {
    var upsert: [Alert] = []
    var remove: [String] = []
    var isEmpty: Bool { upsert.isEmpty && remove.isEmpty }
  }

  static func alertID(forRecord id: String) -> String { "r" + id }

  static func title(short: String) -> String { short + " 到点了" }

  /// 拿记录对一遍账。`existing` 是提醒存档里现有的全部提醒。
  static func plan(items: [Item], existing: [Alert], now: Double) -> Plan {
    var plan = Plan()
    let byID = Dictionary(existing.filter { $0.kind == .reviewDue }.map { ($0.id, $0) },
                          uniquingKeysWith: { a, _ in a })
    var seen: Set<String> = []
    for item in items {
      let id = alertID(forRecord: item.id)
      seen.insert(id)
      let current = byID[id]
      // 判完、作废、不是这个市场的：有就删，没有就算了。
      guard item.waiting, item.eligible, item.dueAt.isFinite, item.dueAt > 0 else {
        if current != nil { plan.remove.append(id) }
        continue
      }
      if let current {
        // 响过一天了：清掉。
        if current.status == .fired, let fired = current.firedAt, now - fired > keepAfterDue {
          plan.remove.append(id)
          continue
        }
        var next = current
        next.symbol = InstrumentID.canonical(item.symbol)
        next.title = title(short: item.short)
        next.reviewID = item.id
        if current.dueAt != item.dueAt {
          // 到期被改了（编辑、服务端裁决）：按新时刻重新上膛。
          next.dueAt = item.dueAt
          if item.dueAt > now {
            next.status = .active; next.firedAt = nil; next.firedPrice = nil; next.armedAt = now
          }
        }
        if next != current { plan.upsert.append(next) }
        continue
      }
      // 到期已经过去一天的老记录不再补建。
      guard item.dueAt > now - keepAfterDue else { continue }
      plan.upsert.append(Alert(id: id, kind: .reviewDue, symbol: item.symbol, lines: [],
                               armedAt: now, dueAt: item.dueAt, reviewID: item.id,
                               title: title(short: item.short), created: now))
    }
    // 记录列表里没有的：只在到点已经过去一天之后清（见头注释）。
    for (id, alert) in byID where !seen.contains(id) {
      let due = alert.dueAt ?? 0
      let fired = alert.firedAt ?? due
      if now - max(due, fired) > keepAfterDue { plan.remove.append(id) }
    }
    plan.remove.sort()
    return plan
  }
}
