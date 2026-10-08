/* Hkline Web · 主力订单流 · 数据层（照 KanpanData/OrderFlow/OrderFlowFeed.swift）
 *
 * 打开一只品种：向 kanpan-api 查这只币在各家交易所的全部簿（/v1/market/orderflow/instruments，
 * 查不到用注册表登记的保底簿；表在本机留 24 小时，开图不再等这一问），按线路分连接订上，每 500 ms 评估一轮，
 * 出帧按 pace.ts 的节奏（画面没变不发、金额 5 秒一换）；服务端历史先取 6 小时，
 * 之后每分钟取一次增量（往前退 5 分钟），图往左拖出去了再往前补。
 *
 * 交易所的一切（地址、订阅、解帧、序号模型、REST 快照、参考簿）都在 src/venues 注册表里，
 * 这里只按注册表给的连接规格开连接、按动作重订或重连，不认任何一家的名字。
 */
import type { Action, Thresholds, Trade, Venue, Product, Notional } from './types'
import { usdOf, venueId } from './types'
import { OrderFlowModel, parseHistory, latestMs, type Snapshot } from './model'
import { BucketScheme } from './bucket'
import { admit, coolingFor, noteStatus } from '../market/limit'
import { viaRoute } from '../market/rest'
import { wireSymbol } from '../market/identity'
import { D, applyOverride, baseOfSymbol, calibratedThreshold, defaultThresholds, isValidBase, needsCalibration, SCALED_PREFIXES, type Override } from './settings'
import {
  type ConnSpec, type DepthBook, type Route, connectionSpecs, fallbackBooks, isKnownExchange, isPrimary, makeVenue, PRIMARY, venueAdapter,
} from '../venues'
import { ago, before } from '../util/clock'
import { FramePacer } from './pace'
import { cachedCalibration, cachedStep, storeCalibration, storeStep } from './startCache'

export type { Route } from '../venues'
export const API_ORIGIN = 'https://kanpan.43-160-232-253.sslip.io'

export const EVALUATE_MS = 500
const HIDDEN_EVALUATE_MS = 2_000
/** 首次取挂着的 + 最近 6 小时；往前一页也是 6 小时（2026-09-29 起服务端带 limit 分页） */
const HISTORY_SPAN_MS = 6 * 3_600_000
/** 一页最多多少条已结束的（服务端上限 5000；挂着的不算、不封顶） */
export const HISTORY_PAGE = 5_000
const HISTORY_EVERY_MS = 60_000
const HISTORY_OVERLAP_MS = 5 * 60_000
const HISTORY_RETRY_MS = 30_000
const BACKFILL_RETRY_MS = 30_000
const BACKFILL_MIN_LIFE_MS = 5 * 60_000
const SNAPSHOT_TIMEOUT_MS = 15_000
const SILENCE_MS = 30_000

/** 网关的 WebSocket 主机：线上与页面同源；本机开发（localhost）直接连线上那台。 */
function gwHost(): string {
  if (typeof location !== 'undefined' && /^https:$/.test(location.protocol) && !/^localhost|^127\./.test(location.hostname)) return location.host
  return new URL(API_ORIGIN).host
}
/** 参考簿（币安 U 本位，推步长的前一日收盘、保底簿）上这只的代号：图上本来就是 xxxUSDT 的（币安 / OKX / Bybit）原样；
 *  别家的（Hyperliquid 的 BTC / KPEPE、Coinbase 的 BTC-USD）按 base 与缩放拼回币安的写法（BTCUSDT、1000PEPEUSDT）。
 *  原来直接拿 BTC、BTC-USD 去要币安的日线：回 400，步长推不出来，还按退避白打 6 次（2026-10-08 四家交叉）；
 *  保底簿那条也是 PEPEUSDT（币安没有，应是 1000PEPEUSDT） */
export function primarySymbolOf(wire: string, base: string, scale: number): string {
  if (/USDT$/.test(wire)) return wire
  const prefix = scale === 1 ? '' : SCALED_PREFIXES.find(([, s]) => s === scale)?.[0] ?? ''
  return prefix + base + 'USDT'
}

/** REST 走同源 /v1（开发时 vite 代理到线上）。 */
const api = (path: string): string => path

/** 历史请求：带 limit 走分页（服务端封顶 5000 条已结束的、回 nextBefore；挂着的全给）。 */
export const historyQuery = (base: string, from: number, to: number): string =>
  `/v1/market/orderflow/history?base=${encodeURIComponent(base)}&from=${Math.floor(from)}&to=${Math.floor(to)}&limit=${HISTORY_PAGE}`

/** 这一页把历史覆盖到了哪儿：封顶时是 nextBefore（更早的下一页取），否则是请求的 from。 */
export const coveredFrom = (p: { fromMs: number; nextBefore: number | null }): number =>
  p.nextBefore != null && p.nextBefore > p.fromMs ? p.nextBefore : p.fromMs

export async function getJSON(url: string, ms: number): Promise<{ status: number; body: unknown }> {
  // 主机在限流冷却里就不发，当作 429 回去；一分钟权重快满了先排队（见 market/limit.ts）
  if (coolingFor(url) > 0) return { status: 429, body: null }
  let gw = false
  try { gw = await admit(url) } catch { return { status: 429, body: null } }
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), ms)
  try {
    const r = await fetch(viaRoute(url), { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store' })
    noteStatus(url, r.status, r.headers.get('Retry-After'), Date.now(), gw)
    const body = r.ok ? await r.json() : null
    return { status: r.status, body }
  } finally { clearTimeout(t) }
}

// ------------------------------------------------------------------ 品种表

interface Row { exchange: string; product: Product; instrument: string; notional: Notional; expiryMs: number | null; priceScale: number; tick: number | null }

const venueOf = (exchange: string, product: Product, instrument: string, notional: Notional): Venue => makeVenue(exchange, product, instrument, notional)

export function parseCatalog(json: unknown): Row[] | null {
  const v = (json as { venues?: unknown })?.venues
  if (!Array.isArray(v)) return null
  const out: Row[] = []
  for (const r of v as Record<string, unknown>[]) {
    const ex = r.exchange, pr = r.product, inst = r.instrument, n = r.notional as Record<string, unknown> | undefined
    if (typeof ex !== 'string' || !isKnownExchange(ex) || typeof inst !== 'string' || !/^[A-Za-z0-9_\-.]{1,40}$/.test(inst)) continue
    if (pr !== 'spot' && pr !== 'usdtPerp' && pr !== 'coinPerp' && pr !== 'delivery') continue
    let notional: Notional
    if (n?.kind === 'linear' && typeof n.multiplier === 'number' && n.multiplier > 0) notional = { kind: 'linear', multiplier: n.multiplier }
    else if (n?.kind === 'inverse' && typeof n.contractUsd === 'number' && n.contractUsd > 0) notional = { kind: 'inverse', contractUsd: n.contractUsd }
    else continue
    const scale = typeof r.priceScale === 'number' && r.priceScale > 0 ? r.priceScale : 1
    out.push({ exchange: ex, product: pr, instrument: inst, notional, expiryMs: typeof r.expiryMs === 'number' ? r.expiryMs : null, priceScale: scale, tick: typeof r.tick === 'number' ? r.tick : null })
  }
  return out
}

/** 品种表的本机缓存（localStorage）：10 分钟内直接用；24 小时内先用着、后台再问一次；再旧就当没有。
 *  开图那一问 0.6 秒整是一次往返，第二次打开同一只不该再等它（2026-10-07）。 */
export const CATALOG_CACHE_KEY = 'hkline-orderflow-catalog-v1'
export const CATALOG_FRESH_MS = 10 * 60_000
export const CATALOG_STALE_MS = 24 * 3_600_000
const CATALOG_CACHE_MAX = 64
type CatalogCache = Record<string, { atMs: number; venues: Row[] }>
function readCatalogCache(): CatalogCache {
  if (typeof localStorage === 'undefined') return {}
  try {
    const v = JSON.parse(localStorage.getItem(CATALOG_CACHE_KEY) ?? '{}') as unknown
    return v && typeof v === 'object' && !Array.isArray(v) ? v as CatalogCache : {}
  } catch { return {} }
}
/** 缓存里这只 base 的表：fresh = 10 分钟内；没有或超过 24 小时是 null */
export function cachedCatalog(base: string, now: number): { rows: Row[]; fresh: boolean } | null {
  const e = readCatalogCache()[base]
  if (!e || typeof e.atMs !== 'number') return null
  const age = ago(e.atMs, now)
  if (age > CATALOG_STALE_MS) return null
  const rows = parseCatalog({ venues: e.venues })
  return rows?.length ? { rows, fresh: age < CATALOG_FRESH_MS } : null
}
export function storeCatalog(base: string, rows: Row[], now: number): void {
  if (typeof localStorage === 'undefined') return
  try {
    let all = readCatalogCache()
    if (Object.keys(all).length >= CATALOG_CACHE_MAX) all = {}
    all[base] = { atMs: now, venues: rows }
    localStorage.setItem(CATALOG_CACHE_KEY, JSON.stringify(all))
  } catch { /* 满了、隐私模式：不缓存而已 */ }
}
/** 向服务端问这只的表；拿到就存进缓存。查不到是 null。 */
async function fetchCatalog(base: string): Promise<Row[] | null> {
  try {
    const r = await getJSON(api(`/v1/market/orderflow/instruments?base=${encodeURIComponent(base)}`), 6000)
    const rows = r.status === 200 ? parseCatalog(r.body) : null
    if (rows?.length) { storeCatalog(base, rows, Date.now()); return rows }
  } catch { /* 查不到用保底 */ }
  return null
}

function booksOf(rows: Row[], chartScale: number, now: number): DepthBook[] {
  const seen = new Set<string>()
  const out: DepthBook[] = []
  for (const r of rows) {
    if (r.expiryMs != null && r.expiryMs <= now) continue
    const venue = venueOf(r.exchange, r.product, r.instrument, r.notional)
    const id = venueId(venue)
    if (seen.has(id)) continue
    seen.add(id)
    out.push({ id, venue, priceFactor: chartScale / r.priceScale, expiryMs: r.expiryMs, tick: r.tick })
  }
  return out
}

// ------------------------------------------------------------------ 一条连接

class Conn {
  ws: WebSocket | null = null
  private urlIndex = 0
  private retry = 0
  private timer: ReturnType<typeof setTimeout> | null = null
  private pingTimer: ReturnType<typeof setInterval> | null = null
  private lastMsg = 0
  private stopped = false
  open = false
  constructor(readonly spec: ConnSpec, readonly feed: OrderFlowFeed) {}

  start(): void {
    if (this.stopped) return
    const url = this.spec.urls[this.urlIndex % this.spec.urls.length]
    let ws: WebSocket
    try { ws = new WebSocket(url) } catch { this.schedule(); return }
    this.ws = ws
    this.lastMsg = Date.now()
    ws.onopen = () => {
      if (this.ws !== ws) return
      this.open = true
      this.retry = 0
      for (const m of this.spec.subscribe()) ws.send(m)
      for (const b of this.spec.books) this.feed.handle(b.id, this.feed.model.connectionOpened(b.id))
      if (this.spec.ping) { const p = this.spec.ping; this.pingTimer = setInterval(() => { if (ws.readyState === 1) ws.send(p.text) }, p.everyMs) }
    }
    ws.onmessage = e => {
      if (this.ws !== ws) return
      this.lastMsg = Date.now()
      this.feed.frames++
      const text = typeof e.data === 'string' ? e.data : ''
      if (!text) return
      for (const [id, m] of this.spec.decode(text)) this.feed.ingest(id, m)
    }
    ws.onclose = () => { if (this.ws === ws) this.fail() }
    ws.onerror = () => { try { ws.close() } catch { /* 已关 */ } }
  }
  /** 半分钟（或这家登记的时长）没有帧：当它死了重连。 */
  watchdog(now: number): void { if (this.ws && ago(this.lastMsg, now) > (this.spec.silenceMs ?? SILENCE_MS)) this.reconnect() }
  send(m: string): void { if (this.ws?.readyState === 1) this.ws.send(m) }
  reconnect(): void { this.teardown(); this.start() }
  private fail(): void {
    const wasOpen = this.open
    this.teardown()
    for (const b of this.spec.books) this.feed.model.disconnected(b.id)
    if (!wasOpen) this.urlIndex++
    this.schedule()
  }
  private schedule(): void {
    if (this.stopped) return
    const ms = Math.min(30_000, 1000 * 2 ** this.retry++) * (0.8 + Math.random() * 0.4)
    this.timer = setTimeout(() => { this.timer = null; this.start() }, ms)
  }
  private teardown(): void {
    this.open = false
    if (this.pingTimer) { clearInterval(this.pingTimer); this.pingTimer = null }
    const ws = this.ws
    this.ws = null
    if (ws) { ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null; try { ws.close() } catch { /* 已关 */ } }
  }
  stop(): void { this.stopped = true; if (this.timer) clearTimeout(this.timer); this.teardown() }
}

// ------------------------------------------------------------------ 数据层

export interface TradeEvent { book: DepthBook; trade: Trade; usd: number }

export interface FeedOptions {
  symbol: string
  crypto: boolean
  turnover24h: number | null
  tick: number | null
  route: Route
  override: Override | null
  onFrame: (s: Snapshot) => void
  onTrade?: (t: TradeEvent) => void
  /** 十字线此刻停在色块上、读数要精确金额：逐拍发、不按住金额（见 pace.ts）。默认否。 */
  precise?: () => boolean
}

export class OrderFlowFeed {
  readonly symbol: string
  readonly base: string
  readonly chartScale: number
  model: OrderFlowModel
  books: DepthBook[] = []
  fromCatalog = false
  frames = 0
  private conns: Conn[] = []
  private byId = new Map<string, DepthBook>()
  private opts: FeedOptions
  private timer: ReturnType<typeof setTimeout> | null = null
  private stopped = false
  private snapshotting = new Map<string, number>()
  private derivedStep: number | null = null
  /** derivedStep 就是今天这个参考日的（本机记着的旧一天的不算：开张先用着，照样去问） */
  private stepExact = false
  /** 还在按盘口深度标定门槛（美股、贵金属） */
  private calibrating: boolean
  /** 标定期间压着不出帧、不取历史：只有本机没有上一次标定结果时才压（有的话先拿它出帧，后台照样标） */
  private blocking: boolean
  private calibrated: number | null = null
  private calibrationDeadline: number | null = null
  /** 换走了先留着（见 park）：照收簿与成交、不出帧，评估放慢到 2 秒一拍 */
  private parked = false
  /** 留着期间要补快照的簿：不在后台和新品种抢带宽，换回来再取（见 unpark） */
  private deferredSnapshots = new Set<string>()
  private pacer = new FramePacer(() => this.opts.precise?.() ?? false)
  /** 门槛改了、历史并进来了：不等下一个 500 ms，马上出一帧（活单金额照旧按住，见 pace.ts force）。 */
  private kick(): void {
    this.pacer.force()
    if (this.stopped || !this.timer) return
    clearTimeout(this.timer); this.timer = setTimeout(() => this.loop(), 0)
  }
  // 历史
  private historyGen = 0
  private historyBusy = false
  private historyFrom: number | null = null
  private historyCursor: number | null = null
  private historyPulled = -Infinity
  private historyRetryAt = -Infinity
  private backfillRetryAt = -Infinity
  private historyTrackedSince: number | null = null
  private historyBlockedStep: number | null = null
  private visibleFrom: number | null = null
  /** 抽屉滚到底了：往前再要一页（不带寿命门槛） */
  private olderWanted = false
  /** 服务端历史最近一次的状态（诊断） */
  historyState: 'idle' | 'ok' | 'down' | 'incompatible' = 'idle'

  constructor(opts: FeedOptions) {
    this.opts = opts
    // 图上可能是别家的品种（完整键 venue/market/SYMBOL）：订单流按 base 币聚合五家，和品种属于哪家无关，取代号那一段
    this.symbol = wireSymbol(opts.symbol).toUpperCase()
    // base 按完整键查（Hyperliquid 的 kPEPE 要靠品种表里的原名认出千枚计价）
    const { base, scale } = baseOfSymbol(opts.symbol)
    this.base = base
    this.chartScale = scale
    this.calibrating = needsCalibration(base, opts.crypto)
    const now = Date.now()
    const prior = this.calibrating ? cachedCalibration(base, now) : null
    if (prior != null) this.calibrated = prior
    this.blocking = this.calibrating && prior == null
    // 本机记着的步长：模型一开始就有桶，历史不用等前一日收盘那一问
    const kept = cachedStep(this.symbol, BucketScheme.referenceDay(now))
    if (kept) { this.derivedStep = kept.step; this.stepExact = kept.exact }
    this.model = new OrderFlowModel(this.symbol, this.effective())
  }

  /** 叠用户改过的项之前的默认门槛与步长（面板的「恢复默认」用）。 */
  defaults(): Thresholds { return defaultThresholds(this.base, this.opts.crypto, this.opts.turnover24h, this.calibrated) }

  private effective(): Thresholds {
    const t = applyOverride(this.defaults(), this.opts.override)
    if (t.step == null && this.derivedStep != null) t.step = this.derivedStep
    return t
  }

  /** 还压着在标定（没有上一次的门槛可用）：图例、梯子写「定门槛」 */
  get isCalibrating(): boolean { return this.blocking }

  /** 还没出完整一帧时卡在哪一步（图例、梯子的提示）：定门槛 → 取步长 → 连盘口 */
  get stage(): 'threshold' | 'step' | 'connect' {
    return this.blocking ? 'threshold' : this.model.thresholds.step == null ? 'step' : 'connect'
  }

  get isParked(): boolean { return this.parked }

  /** 默认与用户门槛里都没有步长、要按前一日收盘推 */
  private needsDerivedStep(): boolean { return applyOverride(this.defaults(), this.opts.override).step == null }

  async start(): Promise<void> {
    if (!isValidBase(this.base)) return
    const now = Date.now()
    // 前一日收盘（推步长用）和品种表同时问，不排在它后面；本机记着今天的步长就不问
    const wantStep = this.needsDerivedStep() && !this.stepExact
    const close = wantStep ? this.referenceClose(BucketScheme.referenceDay(now)).catch(() => NaN) : null
    // 本机留着的表：新鲜的直接用；旧一点的先用着、后台刷新给下一次；没有才等服务端
    const cached = cachedCatalog(this.base, now)
    let rows: Row[] | null = cached?.rows ?? null
    if (!cached) {
      // 等表的这一个往返里，步长已经有了（本机记着 / 固定的）就先把服务端历史取上
      this.pumpHistory()
      rows = await fetchCatalog(this.base)
    } else if (!cached.fresh) void fetchCatalog(this.base)
    if (this.stopped) return
    const books = rows?.length ? booksOf(rows, this.chartScale, now) : []
    this.fromCatalog = books.length > 0
    this.books = books.length ? books : fallbackBooks(primarySymbolOf(this.symbol, this.base, this.chartScale), this.base, this.chartScale)
    for (const b of this.books) { this.byId.set(b.id, b); this.model.addVenue(b.venue) }
    if (this.calibrating) this.calibrationDeadline = Date.now() + D.calibrationTimeoutMs
    this.connect()
    this.loop()
    if (wantStep) void this.loadStep(close)
  }

  /**
   * 换品种时先留着这一只（orderflow/keep.ts 管几只、留多久）：连接与簿不断，只是不出帧、评估放慢；
   * 留着期间不取服务端历史、不拉深度快照——那是几十上百 KB 一页、串着翻十页的活，会和刚换上的那只抢同一条出口
   * （2026-10-09 实测：开着 BTC 换到 PAYP，BTC 的历史还在一页页往前补、币本位 / 交割快照还在拉，PAYP 的历史排了 10 秒）。
   * 换回来 unpark：出帧节奏从头算（下一帧照实发、金额不按住），补上留着期间欠的快照与历史，马上出一帧。
   */
  park(): void { if (!this.stopped) this.parked = true }
  unpark(): void {
    if (this.stopped || !this.parked) return
    this.parked = false
    this.pacer.reset()
    const owed = [...this.deferredSnapshots]
    this.deferredSnapshots.clear()
    for (const id of owed) { const b = this.byId.get(id); if (b && !this.model.isReady(id)) void this.fetchSnapshot(b) }
    this.pumpHistory()
    this.kick()
  }

  stop(): void {
    this.stopped = true
    if (this.timer) clearTimeout(this.timer)
    this.conns.forEach(c => c.stop())
    this.conns = []
    this.historyGen++
  }

  setRoute(route: Route): void {
    if (route === this.opts.route) return
    this.opts.route = route
    this.conns.forEach(c => c.stop())
    this.conns = []
    if (!this.stopped && this.books.length) this.connect()
  }

  setOverride(o: Override | null): void {
    this.opts.override = o
    this.retarget()
    if (this.model.thresholds.step == null) void this.loadStep()
  }

  /** 图最左边那一刻（往左拖出去了就往前补历史）。 */
  setVisible(from: number | null, to: number | null): void {
    this.visibleFrom = from
    this.model.setVisibleWindow(from != null && to != null ? [from, to] : null)
  }

  private retarget(): void {
    const next = this.effective()
    const cur = this.model.thresholds
    const same = (['spot', 'usdtPerp', 'coinPerp', 'delivery', 'step'] as const).every(k => cur[k] === next[k])
    if (same) return
    if (next.step !== cur.step) this.resetHistory()
    this.model.setThresholds(next)
    this.kick()
  }

  // ---------------------------------------------------------- 连接
  private connect(): void {
    this.conns = connectionSpecs(this.books, { route: this.opts.route, gw: `wss://${gwHost()}` }).map(s => new Conn(s, this))
    this.conns.forEach(c => c.start())
  }

  private connOf(id: string): Conn | undefined { return this.conns.find(c => c.spec.books.some(b => b.id === id)) }

  ingest(id: string, m: import('./types').DepthMessage): void {
    const now = Date.now()
    if (m.type === 'trade') {
      const b = this.byId.get(id)
      if (b && this.opts.onTrade) {
        const usd = usdOf(b.venue.notional, m.trade.price, m.trade.quantity)
        if (usd > 0) this.opts.onTrade({ book: b, trade: m.trade, usd })
      }
    }
    this.handle(id, this.model.ingest(id, m, now))
  }

  handle(id: string, a: Action): void {
    if (a === 'none' || this.stopped) return
    const b = this.byId.get(id)
    if (!b) return
    if (a === 'fetchSnapshot') { void this.fetchSnapshot(b); return }
    // resubscribe：这家登记了单本重订就只退订重订这一本（同连接其它簿不动），否则整条重连
    const c = this.connOf(id)
    if (!c) return
    if (c.spec.resubscribe) { for (const m of c.spec.resubscribe(b)) c.send(m); this.handle(id, this.model.connectionOpened(id)) }
    else c.reconnect()
  }

  private async fetchSnapshot(b: DepthBook): Promise<void> {
    if (this.parked) { this.deferredSnapshots.add(b.id); return }
    const last = this.snapshotting.get(b.id)
    const now = Date.now()
    if (last != null && ago(last, now) < 1000) {
      // 一秒内不重复拉；过一会儿再看要不要
      setTimeout(() => { if (!this.stopped && !this.model.isReady(b.id)) void this.fetchSnapshot(b) }, 1000)
      return
    }
    this.snapshotting.set(b.id, now)
    const req = venueAdapter(b.venue.exchange)?.snapshot?.(b, this.opts.route)
    if (!req) return
    const url = req.url.startsWith('/') ? api(req.url) : req.url
    try {
      const r = await getJSON(url, SNAPSHOT_TIMEOUT_MS)
      if (this.stopped) return
      const msg = r.status === 200 ? req.parse(r.body, b) : null
      if (!msg || msg.type !== 'snapshot') throw new Error('bad snapshot')
      this.handle(b.id, this.model.applySnapshot(b.id, msg.snapshot, Date.now()))
    } catch {
      if (this.stopped) return
      // 限流冷却中就等冷却完再拉，不按 3 秒一次去撞
      setTimeout(() => { if (!this.stopped && !this.model.isReady(b.id)) void this.fetchSnapshot(b) }, Math.max(3000, coolingFor(url)))
    }
  }

  // ---------------------------------------------------------- 步长（前一 UTC 日收盘推）
  /** 参考日那根日线的收盘；取不到是 NaN（网络错抛出） */
  private async referenceClose(day: number): Promise<number> {
    const p = PRIMARY.primary
    if (!p) return NaN
    const bars = await getJSON(p.referenceCloseUrl(primarySymbolOf(this.symbol, this.base, this.chartScale), day), 8000)
    return p.parseReferenceClose(bars.body, day)
  }

  /** first：start 里和品种表同时发出去的那一问（第一轮用它，不再问一次） */
  private async loadStep(first: Promise<number> | null = null): Promise<void> {
    for (let attempt = 0; !this.stopped && attempt < 6; attempt++) {
      const day = BucketScheme.referenceDay(Date.now())
      try {
        const close = attempt === 0 && first ? await first : await this.referenceClose(day)
        if (this.stopped) return
        const um = this.books.find(b => isPrimary(b.venue.exchange) && b.venue.product === 'usdtPerp' && b.tick != null)
        const step = BucketScheme.derivedStep(close, this.opts.tick ?? (um ? um.tick! * um.priceFactor : null))
        if (step != null) {
          this.derivedStep = step
          this.stepExact = true
          storeStep(this.symbol, day, step)
          this.retarget()
          return
        }
      } catch { /* 下面退避再试 */ }
      await new Promise(r => setTimeout(r, Math.min(60_000, 2000 * 2 ** attempt)))
    }
  }

  // ---------------------------------------------------------- 评估循环
  private loop(): void {
    if (this.stopped) return
    const hidden = typeof document !== 'undefined' && document.visibilityState === 'hidden'
    const now = Date.now()
    if (this.calibrating) this.calibrate(now)
    const frame = this.blocking
      ? { phase: 'loading' as const, orders: [], asOfMs: now, thresholds: this.model.thresholds, venues: [] }
      : this.model.evaluate(now)
    for (const c of this.conns) c.watchdog(now)
    this.pumpHistory()
    if (!hidden && !this.parked) { const out = this.pacer.next(frame, now); if (out) this.opts.onFrame(out) }
    this.timer = setTimeout(() => this.loop(), hidden || this.parked ? HIDDEN_EVALUATE_MS : EVALUATE_MS)
  }

  private calibrate(now: number): void {
    if (this.calibrationDeadline == null) return
    const d = this.model.calibrationDepth()
    const complete = d.total > 0 && d.ready === d.total
    if (!(complete || d.total === 0 || now >= this.calibrationDeadline)) return
    this.calibrating = false
    this.blocking = false
    this.calibrationDeadline = null
    const prior = this.calibrated
    const next = d.ready > 0 ? calibratedThreshold(d.depth) : null
    if (next != null) storeCalibration(this.base, next, now)
    // 一本簿都没就绪：有上一次的就接着用它，没有才退回默认
    this.calibrated = next ?? prior
    // 先拿上一次的门槛取过历史、这次标得更低：门槛以下被筛掉的那些要重取
    if (prior != null && this.calibrated != null && this.calibrated < prior) this.resetHistory()
    this.retarget()
  }

  // ---------------------------------------------------------- 服务端历史
  private resetHistory(): void {
    this.historyGen++
    this.historyBusy = false
    this.historyFrom = null; this.historyCursor = null; this.historyTrackedSince = null
    this.historyPulled = -Infinity; this.historyRetryAt = -Infinity; this.backfillRetryAt = -Infinity
    this.historyBlockedStep = null
    this.olderWanted = false
  }

  /** 抽屉滚到底时调：服务端还有更早的就往前再取一页（6 小时、最多 5000 条已结束的）。 */
  loadOlder(): void {
    if (this.stopped || this.historyFrom == null || this.olderWanted) return
    const floor = Math.max(this.historyTrackedSince ?? -Infinity, Date.now() - D.retentionMs)
    if (this.historyFrom <= floor) return
    this.olderWanted = true
    this.backfillRetryAt = -Infinity
    this.pumpHistory()
  }

  /** 服务端还有没有比已取到的更早的（抽屉底部提示用）。 */
  get hasOlder(): boolean {
    if (this.historyFrom == null) return false
    return this.historyFrom > Math.max(this.historyTrackedSince ?? -Infinity, Date.now() - D.retentionMs)
  }

  private nextJob(now: number): { kind: 'initial' | 'increment' | 'backfill'; from: number; to: number; minLife: boolean } | null {
    const step = this.model.thresholds.step
    if (step == null || this.historyBlockedStep === step) return null
    const oldest = now - D.retentionMs
    if (this.historyCursor == null || this.historyFrom == null) {
      return !before(this.historyRetryAt, HISTORY_RETRY_MS, now) ? { kind: 'initial', from: now - HISTORY_SPAN_MS, to: now, minLife: false } : null
    }
    if (ago(this.historyPulled, now) >= HISTORY_EVERY_MS) {
      return { kind: 'increment', from: Math.max(oldest, Math.min(this.historyCursor, now) - HISTORY_OVERLAP_MS), to: now, minLife: false }
    }
    // 往前一页：抽屉滚到底（全要），或图往左拖出了已取的范围（只要活过 5 分钟的，图上短命的看不出来）。
    const scrolled = this.visibleFrom != null && this.visibleFrom < this.historyFrom
    if ((this.olderWanted || scrolled) && !before(this.backfillRetryAt, BACKFILL_RETRY_MS, now)) {
      const floor = Math.max(this.historyTrackedSince ?? oldest, oldest)
      if (this.historyFrom <= floor) { this.olderWanted = false; return null }
      return { kind: 'backfill', from: Math.max(floor, this.historyFrom - HISTORY_SPAN_MS), to: this.historyFrom, minLife: !this.olderWanted }
    }
    return null
  }

  private pumpHistory(): void {
    if (this.stopped || this.blocking || this.historyBusy || this.parked) return
    const job = this.nextJob(Date.now())
    if (!job) return
    this.historyBusy = true
    const gen = this.historyGen
    void (async () => {
      const q = historyQuery(this.base, job.from, job.to)
      let page = null
      try {
        let r = await getJSON(api(job.minLife ? `${q}&minLifeMs=${BACKFILL_MIN_LIFE_MS}` : q), 15_000)
        if (r.status === 400 && job.minLife) r = await getJSON(api(q), 15_000)
        if (r.status === 200) { page = parseHistory(r.body, job.from, job.to); if (page && page.base !== this.base) page = null }
      } catch { page = null }
      if (gen !== this.historyGen || this.stopped) return
      this.historyBusy = false
      const now = Date.now()
      if (job.kind === 'increment') this.historyPulled = now
      if (!page) {
        this.historyState = 'down'
        if (job.kind === 'initial') this.historyRetryAt = now + HISTORY_RETRY_MS
        if (job.kind === 'backfill') { this.backfillRetryAt = now + BACKFILL_RETRY_MS; this.olderWanted = false }
        return
      }
      this.historyTrackedSince = page.trackedSinceMs
      const res = this.model.mergeHistory(page, this.chartScale, now)
      if (res === 'merged') {
        this.historyState = 'ok'
        const latest = latestMs(page)
        // 封顶了（nextBefore 不为 null）：已取到的只算到 nextBefore，更早的留给下一页。
        let reached = coveredFrom(page)
        // 退化情形（五千多条挤在同一毫秒）：nextBefore 等于这页的 to，挪不动就按整页算，免得原地重取。
        if (job.kind === 'backfill' && reached >= job.to) reached = page.fromMs
        if (job.kind === 'initial') { this.historyFrom = reached; this.historyCursor = latest ?? page.toMs; this.historyPulled = now }
        else if (job.kind === 'increment') this.historyCursor = Math.max(this.historyCursor ?? -Infinity, latest ?? page.fromMs + HISTORY_OVERLAP_MS)
        else { this.historyFrom = Math.min(this.historyFrom ?? reached, reached); if (!job.minLife) this.olderWanted = false }
        this.kick()
      } else if (res === 'incompatible') {
        this.olderWanted = false
        this.historyState = 'incompatible'
        if (page.thresholds.step == null) { this.historyRetryAt = now + HISTORY_RETRY_MS; this.backfillRetryAt = now + BACKFILL_RETRY_MS }
        else this.historyBlockedStep = this.model.thresholds.step ?? null
      }
    })()
  }

  /** 诊断：各连接与各簿的状态。 */
  debug(): { conns: { key: string; open: boolean; url: string }[]; ready: string[]; notReady: string[]; frames: number; history: string } {
    const ready: string[] = [], notReady: string[] = []
    for (const b of this.books) (this.model.isReady(b.id) ? ready : notReady).push(b.id)
    return { conns: this.conns.map(c => ({ key: c.spec.key, open: c.open, url: c.ws?.url ?? '' })), ready, notReady, frames: this.frames, history: this.historyState }
  }
}
