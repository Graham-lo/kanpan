// 手机网页版 · 主力订单流的数据源：把共用的 OrderFlowFeed（src/orderflow/feed.ts，PC 版同一套三家聚合的簿）
// 包成图表要的 OrderFlowSnapshot（state.overlay.orderFlow）。
//
// 只做三件事：
//   1. 起停：同一品种重复 start 不重订（只更新出帧间隔），换品种先停旧的、先交一个 null 让图上立刻清掉旧品种的线。
//   2. 拷一份：feed 的模型原地改单子（push、改 notional / status），直接交出去的话图表那边按「同一块数组」认缓存会认错，
//      所以每帧把单子逐条浅拷贝成一份不再变的快照（几千单一次拷贝 < 1 ms，500 ms 一帧）。
//   3. 拼上品种与默认门槛：symbol 用 feed 规范化后的代号，defaults 取 feed.defaults()（面板「恢复默认」用）。
//
// 线路（直连 / 网关）与用户改过的门槛由调用方按需传 options，或随后 setRoute / setOverride；默认直连、不叠用户门槛。

import { OrderFlowFeed, type Route } from '../../orderflow/feed'
import type { Snapshot } from '../../orderflow/model'
import type { Override } from '../../orderflow/settings'
import type { OrderFlowSnapshot } from './orderflowGroup'

export interface OrderFlowSourceOptions {
  /** 是不是加密货币（美股、贵金属等传 false：默认门槛按标定走）。默认 true。 */
  crypto?: boolean
  /** 24h 成交额（山寨币的默认门槛按它定）。默认 null。 */
  turnover24h?: number | null
  /** 行情线路：直连 / 网关。默认直连。 */
  route?: Route
  /** 用户改过的门槛与步长（全端同步的指标设置）。默认 null。 */
  override?: Override | null
}

export class OrderFlowSource {
  private feed: OrderFlowFeed | null = null
  private symbol: string | null = null
  private intervalMs = 0
  private lastEmit = -Infinity
  private generation = 0

  constructor(private readonly onSnapshot: (s: OrderFlowSnapshot | null) => void) {}

  /** 正在订的品种（大写）；没在订是 null。 */
  get current(): string | null { return this.symbol }

  /**
   * 开始订这一只。intervalMs 是两帧之间至少隔多久交给图表（默认 0：feed 出一帧交一帧，即每 500 ms）；
   * 同一品种再调只更新它和 options 里的线路 / 门槛，不重订。
   */
  start(symbol: string, intervalMs?: number, options: OrderFlowSourceOptions = {}): void {
    const sym = symbol.toUpperCase()
    this.intervalMs = Math.max(0, intervalMs ?? 0)
    if (this.feed && this.symbol === sym) {
      if (options.route) this.feed.setRoute(options.route)
      if (options.override !== undefined) this.feed.setOverride(options.override)
      return
    }
    if (this.feed) this.stop()
    this.symbol = sym
    this.lastEmit = -Infinity
    const gen = ++this.generation
    const feed: OrderFlowFeed = new OrderFlowFeed({
      symbol: sym,
      crypto: options.crypto ?? true,
      turnover24h: options.turnover24h ?? null,
      tick: null,
      route: options.route ?? 'direct',
      override: options.override ?? null,
      onFrame: s => this.frame(gen, feed, s),
    })
    this.feed = feed
    void feed.start()
  }

  /** 停掉并交一个 null（图上清掉）。 */
  stop(): void {
    if (!this.feed) return
    this.generation++
    this.feed.stop()
    this.feed = null
    this.symbol = null
    this.onSnapshot(null)
  }

  setRoute(route: Route): void { this.feed?.setRoute(route) }
  setOverride(o: Override | null): void { this.feed?.setOverride(o) }
  /** 图最左 / 最右那一刻（往左拖出去了 feed 往前补历史）。 */
  setVisible(from: number | null, to: number | null): void { this.feed?.setVisible(from, to) }

  private frame(gen: number, feed: OrderFlowFeed, s: Snapshot): void {
    if (gen !== this.generation || feed !== this.feed) return
    const now = Date.now()
    if (this.intervalMs > 0 && now - this.lastEmit < this.intervalMs) return
    this.lastEmit = now
    this.onSnapshot(toChartSnapshot(feed.symbol, s, feed.defaults()))
  }
}

/** feed 的一帧 → 图表的快照：单子逐条浅拷贝（feed 原地改它们），门槛拷一份。 */
export function toChartSnapshot(symbol: string, s: Snapshot, defaults?: OrderFlowSnapshot['defaults']): OrderFlowSnapshot {
  return {
    symbol,
    phase: s.phase,
    orders: s.orders.map(o => ({ ...o })),
    asOfMs: s.asOfMs,
    thresholds: { ...s.thresholds },
    defaults: defaults ? { ...defaults } : undefined,
    venues: s.venues.map(v => ({ ...v })),
  }
}
