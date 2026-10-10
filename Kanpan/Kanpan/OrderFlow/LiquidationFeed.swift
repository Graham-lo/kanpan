import Foundation
import KanpanCore

// 爆仓分钟账 · app 这一层唯一的一份（2026-10-08，大单与爆仓气泡并进爆仓之后）。
//
// 图上的大单与爆仓气泡、「大单与爆仓」弹层共读这一本 `LiquidationBook`：每 30 秒从 kanpan-api /liq
// 增量补一页（`LiquidationBook.fetchFrom / merge / pollMs`），只留 3 天。
// 什么时候拉由 `MarketModel.syncLiquidations` 定：在前台、品种有订单流、不是现货 / 宏观品种，并且
// 图上气泡开着且图看得见、或弹层开着。退到后台、换品种、开关都关了就停；同一只再开起来接着旧账增量补。

@MainActor
@Observable
final class LiquidationFeed {
  /// 取一页：(base, fromMs, toMs) → 一页；失败给 nil。
  typealias Fetch = @MainActor (String, Int64, Int64) async -> LiquidationPage?

  /// 当前这只的爆仓账（换了 base 就换一本新的；停了留着，同一只再开接着补）。
  private(set) var book: LiquidationBook?
  /// 一页都没取到过且取失败（弹层显示「暂无爆仓数据」）。
  private(set) var unavailable = false
  private(set) var updatedAtMs: Int64?
  /// 此刻在拉哪只（nil = 停着）。
  @ObservationIgnored private(set) var running: String?
  @ObservationIgnored private var task: Task<Void, Never>?

  /// 开 / 换 / 停：`base` 为 nil 就停。和正在拉的同一只什么都不做。
  func run(base: String?, fetch: @escaping Fetch) {
    guard base != running else { return }
    task?.cancel(); task = nil
    running = base
    guard let base else { return }
    if book?.base != base { book = LiquidationBook(base: base); unavailable = false; updatedAtMs = nil }
    task = Task { [weak self] in await self?.poll(base: base, fetch: fetch) }
  }

  private func poll(base: String, fetch: Fetch) async {
    while !Task.isCancelled {
      let now = Self.nowMs()
      let from = book?.fetchFrom(nowMs: now) ?? now - LiquidationBook.keepMs
      let page = await fetch(base, from, now + 60_000)
      guard !Task.isCancelled, running == base, book?.base == base else { return }
      if let page {
        book?.merge(page, nowMs: now)
        unavailable = false
        updatedAtMs = Self.nowMs()
      } else if book?.tracked == nil {
        unavailable = true
      }
      try? await Task.sleep(for: .milliseconds(LiquidationBook.pollMs))
    }
  }

  static func nowMs(_ date: Date = Date()) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }
}
