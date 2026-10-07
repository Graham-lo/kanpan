// 手机网页版 · 主力订单流的数据源：把共用的 OrderFlowFeed（src/orderflow/feed.ts，PC 版同一套三家聚合的簿）
// 包成图表要的 OrderFlowSnapshot（state.overlay.orderFlow）。
//
// 只做三件事：
//   1. 起停：同一品种重复 start 不重订（只更新出帧间隔）；换品种把旧的那只交给 FeedKeeper 先留着（最多两只、三分钟，
//      切回来接着用、不从头连），新的那只先交一帧「还在接」的空快照（图例写卡在哪一步），图上立刻清掉旧品种的线。
//   2. 拷一份：feed 的模型原地改单子（push、改 notional / status），直接交出去的话图表那边按「同一块数组」认缓存会认错，
//      所以每帧把单子逐条浅拷贝成一份不再变的快照（几千单一次拷贝 < 1 ms，500 ms 一帧）。
//   3. 拼上品种与默认门槛：symbol 用 feed 规范化后的代号，defaults 取 feed.defaults()（面板「恢复默认」用）。
//
// 线路（直连 / 网关）与用户改过的门槛由调用方按需传 options，或随后 setRoute / setOverride；默认直连、不叠用户门槛。

import { OrderFlowFeed, type Route } from '../../orderflow/feed'
import { S, on as onMarket } from '../../market'
import { stopWhenHiddenLong } from '../../orderflow/idle'
import { FeedKeeper } from '../../orderflow/keep'
import type { BarSeries, Interval } from './series'
import type { ViewWindow } from './geometry'
import type { Snapshot } from '../../orderflow/model'
import type { Override } from '../../orderflow/settings'
import type { OrderFlowSnapshot } from './orderflowGroup'
import { ago } from '../../util/clock'

export interface OrderFlowSourceOptions {
  /** 是不是加密货币（美股、贵金属等传 false：默认门槛按标定走）。默认 true。 */
  crypto?: boolean
  /** 24h 成交额（山寨币的默认门槛按它定）。默认 null。 */
  turnover24h?: number | null
  /** 行情线路：直连 / 网关。默认直连。 */
  route?: Route
  /** 用户改过的门槛与步长（全端同步的指标设置）。默认 null。 */
  override?: Override | null
  /** 十字线此刻停在色块上（读数要精确金额，feed 逐拍发、不按住金额）。默认一直否。 */
  precise?: () => boolean
}

export class OrderFlowSource {
  private feed: OrderFlowFeed | null = null
  private symbol: string | null = null
  /** 留着的键：品种 + 是不是加密（表到了以后类型变了的那只不能拿旧的接着用） */
  private key: string | null = null
  private intervalMs = 0
  private lastEmit = -Infinity
  private readonly keeper = new FeedKeeper<OrderFlowFeed>()

  constructor(private readonly onSnapshot: (s: OrderFlowSnapshot | null) => void) {}

  /** 留着的几只（诊断、测试用） */
  get keptKeys(): string[] { return this.keeper.keys() }

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
    const crypto = options.crypto ?? true
    const key = `${sym}|${crypto ? 1 : 0}`
    if (this.feed) this.park()
    this.symbol = sym
    this.key = key
    this.lastEmit = -Infinity
    const kept = this.keeper.take(key)
    if (kept) {
      // 刚看过的：连接与簿都还在，换回来马上出一帧
      this.feed = kept
      if (options.route) kept.setRoute(options.route)
      if (options.override !== undefined) kept.setOverride(options.override)
      kept.unpark()
      return
    }
    const feed: OrderFlowFeed = new OrderFlowFeed({
      symbol: sym,
      crypto,
      turnover24h: options.turnover24h ?? null,
      tick: null,
      route: options.route ?? 'direct',
      override: options.override ?? null,
      precise: options.precise,
      onFrame: s => this.frame(feed, s),
    })
    this.feed = feed
    void feed.start()
    // 第一帧要等品种表 / 盘口：先交一份空的「还在接」，图例马上写卡在哪一步
    this.onSnapshot(toChartSnapshot(feed.symbol, { phase: 'loading', orders: [], asOfMs: Date.now(), thresholds: feed.model.thresholds, venues: [] }, feed.defaults(), feed.stage))
  }

  /** 正在订的这只先留着（换品种、行情页切走），交一个 null（图上清掉）。 */
  park(): void {
    const f = this.feed, key = this.key
    if (!f || !key) return
    this.feed = null
    this.symbol = null
    this.key = null
    this.keeper.park(key, f)
    this.onSnapshot(null)
  }

  /** 停掉（连同留着的几只）并交一个 null（图上清掉）。only = true：只停正在订的这只，留着的不动。 */
  stop(only = false): void {
    if (!only) this.keeper.clear()
    if (!this.feed) return
    this.feed.stop()
    this.feed = null
    this.symbol = null
    this.key = null
    this.onSnapshot(null)
  }

  setRoute(route: Route): void { this.feed?.setRoute(route) }
  setOverride(o: Override | null): void { this.feed?.setOverride(o) }
  /** 图最左 / 最右那一刻（往左拖出去了 feed 往前补历史）。 */
  setVisible(from: number | null, to: number | null): void { this.feed?.setVisible(from, to) }

  private frame(feed: OrderFlowFeed, s: Snapshot): void {
    if (feed !== this.feed) return
    const now = Date.now()
    if (this.intervalMs > 0 && ago(this.lastEmit, now) < this.intervalMs) return
    this.lastEmit = now
    this.onSnapshot(toChartSnapshot(feed.symbol, s, feed.defaults(), s.phase === 'ready' ? undefined : feed.stage))
  }
}

/** feed 的一帧 → 图表的快照：单子逐条浅拷贝（feed 原地改它们），门槛拷一份。stage：还在接时卡在哪一步。 */
export function toChartSnapshot(symbol: string, s: Snapshot, defaults?: OrderFlowSnapshot['defaults'], stage?: OrderFlowSnapshot['stage']): OrderFlowSnapshot {
  return {
    symbol,
    ...(stage ? { stage } : {}),
    phase: s.phase,
    orders: s.orders.map(o => ({ ...o })),
    asOfMs: s.asOfMs,
    thresholds: { ...s.thresholds },
    defaults: defaults ? { ...defaults } : undefined,
    venues: s.venues.map(v => ({ ...v })),
  }
}

/** createChart 的 OrderFlowPort 那一面（index.ts 里的接口，这里按结构写一份，免得反向 import）。 */
export interface OrderFlowSourcePort {
  setWanted(on: boolean, symbol: string, interval: Interval): void
  noteView(view: ViewWindow, series: BarSeries): void
  /** 十字线停到 / 离开色块：停着时 feed 逐拍发精确金额，离开后金额又按 5 秒一换 */
  setPrecise(on: boolean): void
  dispose(): void
}

/**
 * 默认的订单流口子：createChart 没传 orderFlowSource 时用它。
 * - 品种类型与 24h 成交额从全市场表（market S.symbols）取，表还没到时先按加密、到了之后重订一次让默认门槛对上；
 * - 线路跟着 market 的 S.route 走（设置里切线路会发 ws 事件）；
 * - 视野变化交 setVisible（往左拖出去 feed 往前补历史），右沿多给一根，与 PC 版 g.timeOf(g.to + 1) 同口径；
 * - override 由调用方给（全端同步的门槛设置）；没给就用默认门槛。
 */
export function createOrderFlowPort(
  push: (snap: OrderFlowSnapshot | null) => void,
  opts: { override?: (symbol: string) => Override | null } = {},
): OrderFlowSourcePort {
  const src = new OrderFlowSource(push)
  let wanted: string | null = null
  let knewSymbol = false
  let precise = false
  const info = (sym: string) => {
    const m = S.symbols.get(sym)
    return { known: !!m, crypto: (m?.kind ?? 'crypto') === 'crypto', turnover24h: m?.vol ?? null }
  }
  const start = (sym: string) => {
    const i = info(sym)
    knewSymbol = i.known
    src.start(sym, 0, { crypto: i.crypto, turnover24h: i.turnover24h, route: S.route, override: opts.override?.(sym) ?? null, precise: () => precise })
  }
  const off = onMarket(e => {
    if (!wanted || bg) return
    if (e.type === 'ws') src.setRoute(S.route)
    else if (e.type === 'universe' && !knewSymbol && info(wanted).known) { src.stop(true); start(wanted) }
  })
  // 整页藏到后台一分钟就停掉订阅，回到前台重开（与行情页的 createPagePort 同一条规矩，见 orderflow/idle.ts）
  let bg = false
  let seen: [number, number] | null = null
  const offHidden = stopWhenHiddenLong(
    () => { bg = true; src.stop() },
    () => { bg = false; if (!wanted) return; start(wanted); if (seen) src.setVisible(seen[0], seen[1]) },
  )
  return {
    setWanted(on, symbol) {
      const sym = symbol.toUpperCase()
      if (!on) { wanted = null; src.stop(); return }
      if (sym !== wanted) seen = null
      if (bg) { wanted = sym; return }
      if (wanted === sym && src.current === sym) return
      wanted = sym
      start(sym)
    },
    noteView(view, series) {
      if (!wanted) return
      seen = [view.from, view.to + Math.max(0, series.step)]
      if (!bg) src.setVisible(seen[0], seen[1])
    },
    setPrecise(on) { precise = on },
    dispose() { off(); offHidden(); wanted = null; src.stop() },
  }
}
