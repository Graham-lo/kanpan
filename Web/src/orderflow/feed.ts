/* Hkline Web · 主力订单流 · 数据层（照 KanpanData/OrderFlow/OrderFlowFeed.swift）
 *
 * 打开一只品种：向 kanpan-api 查这只币在三家交易所的全部簿（/v1/market/orderflow/instruments，
 * 查不到用保底三本），按线路分连接订上，每 500 ms 评估一轮出一帧；服务端历史先取 24 小时，
 * 之后每分钟取一次增量（往前退 5 分钟），图往左拖出去了再往前补。
 *
 * 线路（与手机端一致）：
 * - 直连：币安 U 本位深度 fstream /public、成交 fstream /market，币本位 dstream，现货 data-stream.binance.vision；
 *   OKX 直连 ws.okx.com，连不上退到网关中继；Coinbase 恒直连。
 * - 网关：币安合约走 /v1/market/ws/binance 中继（一条 ≤ 8 路流）、快照走 /v1/market/depth；现货仍直连 vision；
 *   OKX 走 /v1/market/ws/okx；Coinbase 直连。
 * 一律不用 *.binancefuture.com（那是合约测试网）。
 */
import type { Action, Thresholds, Trade, Venue, Product, Notional } from './types'
import { usdOf, venueId } from './types'
import { OrderFlowModel, parseHistory, latestMs, type Snapshot } from './model'
import { BucketScheme } from './bucket'
import { D, applyOverride, baseOfSymbol, calibratedThreshold, defaultThresholds, isValidBase, needsCalibration, type Override } from './settings'
import {
  type DepthBook, type BinanceMarket, binanceMarket, binanceSnapshot, binanceStreams, BINANCE_SNAPSHOT_LEVELS,
  decodeBinance, decodeOKX, decodeCoinbase, okxSubscribe, okxResubscribe, coinbaseSubscribe, OKX_MAX_BOOKS, type Out,
} from './adapters'

export type Route = 'direct' | 'gateway'
export const API_ORIGIN = 'https://kanpan.107-174-172-10.sslip.io'
const EXCHANGES: Record<string, string> = { binance: '币安', okx: 'OKX', coinbase: 'Coinbase' }

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
/** REST 走同源 /v1（开发时 vite 代理到线上）。 */
const api = (path: string): string => path

/** 历史请求：带 limit 走分页（服务端封顶 5000 条已结束的、回 nextBefore；挂着的全给）。 */
export const historyQuery = (base: string, from: number, to: number): string =>
  `/v1/market/orderflow/history?base=${encodeURIComponent(base)}&from=${Math.floor(from)}&to=${Math.floor(to)}&limit=${HISTORY_PAGE}`

/** 这一页把历史覆盖到了哪儿：封顶时是 nextBefore（更早的下一页取），否则是请求的 from。 */
export const coveredFrom = (p: { fromMs: number; nextBefore: number | null }): number =>
  p.nextBefore != null && p.nextBefore > p.fromMs ? p.nextBefore : p.fromMs

export async function getJSON(url: string, ms: number): Promise<{ status: number; body: unknown }> {
  const ctl = new AbortController()
  const t = setTimeout(() => ctl.abort(), ms)
  try {
    const r = await fetch(url, { signal: ctl.signal, referrerPolicy: 'no-referrer', cache: 'no-store' })
    const body = r.ok ? await r.json() : null
    return { status: r.status, body }
  } finally { clearTimeout(t) }
}

// ------------------------------------------------------------------ 品种表

interface Row { exchange: string; product: Product; instrument: string; notional: Notional; expiryMs: number | null; priceScale: number; tick: number | null }

function venueOf(exchange: string, product: Product, instrument: string, notional: Notional): Venue {
  const okx = exchange === 'okx', cb = exchange === 'coinbase'
  return {
    exchange, label: EXCHANGES[exchange] ?? exchange, product, instrument, notional,
    sequenceModel: okx ? 'previousFinalExact' : cb ? 'strictIncrementing' : product === 'spot' ? 'rangeOverlap' : 'previousFinalOverlap',
    snapshotInBand: okx || cb,
  }
}

export function parseCatalog(json: unknown): Row[] | null {
  const v = (json as { venues?: unknown })?.venues
  if (!Array.isArray(v)) return null
  const out: Row[] = []
  for (const r of v as Record<string, unknown>[]) {
    const ex = r.exchange, pr = r.product, inst = r.instrument, n = r.notional as Record<string, unknown> | undefined
    if (typeof ex !== 'string' || !EXCHANGES[ex] || typeof inst !== 'string' || !/^[A-Za-z0-9_\-.]{1,40}$/.test(inst)) continue
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

function fallbackBooks(symbol: string, base: string, chartScale: number): DepthBook[] {
  const mk = (ex: string, p: Product, inst: string, factor: number): DepthBook => {
    const venue = venueOf(ex, p, inst, { kind: 'linear', multiplier: 1 })
    return { id: venueId(venue), venue, priceFactor: factor, expiryMs: null, tick: null }
  }
  return [mk('binance', 'usdtPerp', symbol, 1), mk('binance', 'spot', base + 'USDT', chartScale), mk('coinbase', 'spot', base + '-USD', chartScale)]
}

// ------------------------------------------------------------------ 一条连接

interface ConnSpec {
  key: string
  urls: string[]            // 依次尝试
  books: DepthBook[]
  subscribe: () => string[]
  decode: (text: string) => Out[]
  ping?: { text: string; everyMs: number }
}

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
  /** 半分钟没有帧：当它死了重连。 */
  watchdog(now: number): void { if (this.ws && now - this.lastMsg > SILENCE_MS) this.reconnect() }
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
  private calibrating: boolean
  private calibrated: number | null = null
  private calibrationDeadline: number | null = null
  /** 门槛改了、历史并进来了：不等下一个 500 ms，马上出一帧。 */
  private kick(): void { if (this.stopped || !this.timer) return; clearTimeout(this.timer); this.timer = setTimeout(() => this.loop(), 0) }
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
    this.symbol = opts.symbol.toUpperCase()
    const { base, scale } = baseOfSymbol(this.symbol)
    this.base = base
    this.chartScale = scale
    this.calibrating = needsCalibration(base, opts.crypto)
    this.model = new OrderFlowModel(this.symbol, this.effective())
  }

  /** 叠用户改过的项之前的默认门槛与步长（面板的「恢复默认」用）。 */
  defaults(): Thresholds { return defaultThresholds(this.base, this.opts.crypto, this.opts.turnover24h, this.calibrated) }

  private effective(): Thresholds {
    const t = applyOverride(this.defaults(), this.opts.override)
    if (t.step == null && this.derivedStep != null) t.step = this.derivedStep
    return t
  }

  get isCalibrating(): boolean { return this.calibrating }

  async start(): Promise<void> {
    if (!isValidBase(this.base)) return
    const now = Date.now()
    let rows: Row[] | null = null
    try {
      const r = await getJSON(api(`/v1/market/orderflow/instruments?base=${encodeURIComponent(this.base)}`), 6000)
      if (r.status === 200) rows = parseCatalog(r.body)
    } catch { /* 查不到用保底 */ }
    if (this.stopped) return
    const books = rows?.length ? booksOf(rows, this.chartScale, now) : []
    this.fromCatalog = books.length > 0
    this.books = books.length ? books : fallbackBooks(this.symbol, this.base, this.chartScale)
    for (const b of this.books) { this.byId.set(b.id, b); this.model.addVenue(b.venue) }
    if (this.calibrating) this.calibrationDeadline = Date.now() + D.calibrationTimeoutMs
    this.connect()
    this.loop()
    if (this.model.thresholds.step == null) void this.loadStep()
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
    const route = this.opts.route
    const gw = `wss://${gwHost()}`
    const specs: ConnSpec[] = []
    const byMarket: Record<BinanceMarket, DepthBook[]> = { um: [], cm: [], spot: [] }
    const okx: DepthBook[] = [], cb: DepthBook[] = []
    for (const b of this.books) {
      if (b.venue.exchange === 'binance') byMarket[binanceMarket(b.venue)].push(b)
      else if (b.venue.exchange === 'okx') okx.push(b)
      else if (b.venue.exchange === 'coinbase') cb.push(b)
    }
    const chunk = <T>(a: T[], n: number): T[][] => { const o: T[][] = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o }
    const binanceSpec = (key: string, books: DepthBook[], url: (streams: string) => string, streams: (b: DepthBook) => string[]): ConnSpec => {
      const map = new Map(books.map(b => [b.venue.instrument.toUpperCase(), b]))
      return { key, books, urls: [url(books.flatMap(streams).join('/'))], subscribe: () => [], decode: t => decodeBinance(t, map) }
    }
    for (const m of ['um', 'cm', 'spot'] as BinanceMarket[]) {
      const list = byMarket[m]
      if (!list.length) continue
      if (m === 'spot') {
        specs.push(binanceSpec('binance-spot', list, s => `wss://data-stream.binance.vision/stream?streams=${s}`, binanceStreams))
      } else if (route === 'gateway') {
        chunk(list, 4).forEach((c, i) => specs.push(binanceSpec(`binance-${m}-gw${i}`, c, s => `${gw}/v1/market/ws/binance?streams=${s}`, binanceStreams)))
      } else if (m === 'um') {
        // 直连 U 本位：深度在 /public、成交在 /market，两条连接；成交那条不负责簿（books 为空时不触发 connectionOpened）
        const map = new Map(list.map(b => [b.venue.instrument.toUpperCase(), b]))
        specs.push({ key: 'binance-um-depth', books: list, urls: [`wss://fstream.binance.com/public/stream?streams=${list.map(b => binanceStreams(b)[0]).join('/')}`], subscribe: () => [], decode: t => decodeBinance(t, map) })
        specs.push({ key: 'binance-um-trade', books: [], urls: [`wss://fstream.binance.com/market/stream?streams=${list.map(b => binanceStreams(b)[1]).join('/')}`], subscribe: () => [], decode: t => decodeBinance(t, map) })
      } else {
        specs.push(binanceSpec('binance-cm', list, s => `wss://dstream.binance.com/stream?streams=${s}`, binanceStreams))
      }
    }
    chunk(okx, OKX_MAX_BOOKS).forEach((c, i) => {
      const map = new Map(c.map(b => [b.venue.instrument, b]))
      const relay = `${gw}/v1/market/ws/okx`
      specs.push({
        key: `okx${i}`, books: c, urls: route === 'gateway' ? [relay] : ['wss://ws.okx.com:8443/ws/v5/public', relay],
        subscribe: () => okxSubscribe(c), decode: t => decodeOKX(t, map), ping: { text: 'ping', everyMs: 20_000 },
      })
    })
    for (const b of cb) specs.push({ key: `coinbase-${b.venue.instrument}`, books: [b], urls: ['wss://advanced-trade-ws.coinbase.com'], subscribe: () => coinbaseSubscribe(b), decode: t => decodeCoinbase(t, b) })
    this.conns = specs.map(s => new Conn(s, this))
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
    // resubscribe：OKX 发退订 + 订阅；Coinbase 整条重连
    const c = this.connOf(id)
    if (!c) return
    if (b.venue.exchange === 'okx') { for (const m of okxResubscribe(b)) c.send(m); this.handle(id, this.model.connectionOpened(id)) }
    else c.reconnect()
  }

  private async fetchSnapshot(b: DepthBook): Promise<void> {
    const last = this.snapshotting.get(b.id)
    const now = Date.now()
    if (last != null && now - last < 1000) {
      // 一秒内不重复拉；过一会儿再看要不要
      setTimeout(() => { if (!this.stopped && !this.model.isReady(b.id)) void this.fetchSnapshot(b) }, 1000)
      return
    }
    this.snapshotting.set(b.id, now)
    const m = binanceMarket(b.venue)
    const sym = encodeURIComponent(b.venue.instrument)
    const limit = BINANCE_SNAPSHOT_LEVELS[m]
    const url = m === 'spot' ? `https://data-api.binance.vision/api/v3/depth?symbol=${sym}&limit=${limit}`
      : this.opts.route === 'gateway' ? api(`/v1/market/depth?symbol=${sym}&limit=1000&market=${m}`)
      : m === 'um' ? `https://fapi.binance.com/fapi/v1/depth?symbol=${sym}&limit=${limit}`
      : `https://dapi.binance.com/dapi/v1/depth?symbol=${sym}&limit=${limit}`
    try {
      const r = await getJSON(url, SNAPSHOT_TIMEOUT_MS)
      if (this.stopped) return
      const msg = r.status === 200 ? binanceSnapshot(r.body, b) : null
      if (!msg || msg.type !== 'snapshot') throw new Error('bad snapshot')
      this.handle(b.id, this.model.applySnapshot(b.id, msg.snapshot, Date.now()))
    } catch {
      if (this.stopped) return
      setTimeout(() => { if (!this.stopped && !this.model.isReady(b.id)) void this.fetchSnapshot(b) }, 3000)
    }
  }

  // ---------------------------------------------------------- 步长（前一 UTC 日收盘推）
  private async loadStep(): Promise<void> {
    for (let attempt = 0; !this.stopped && attempt < 6; attempt++) {
      const day = BucketScheme.referenceDay(Date.now())
      try {
        const bars = await getJSON(`https://fapi.binance.com/fapi/v1/klines?symbol=${encodeURIComponent(this.symbol)}&interval=1d&startTime=${day}&limit=2`, 8000)
        const rows = Array.isArray(bars.body) ? (bars.body as unknown[][]) : []
        const exact = rows.find(r => Number(r[0]) === day) ?? rows.filter(r => Number(r[0]) < day + 86_400_000).pop()
        const close = exact ? parseFloat(String(exact[4])) : NaN
        const um = this.books.find(b => b.venue.exchange === 'binance' && b.venue.product === 'usdtPerp' && b.tick != null)
        const step = BucketScheme.derivedStep(close, this.opts.tick ?? (um ? um.tick! * um.priceFactor : null))
        if (step != null) {
          this.derivedStep = step
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
    const frame = this.calibrating
      ? { phase: 'loading' as const, orders: [], asOfMs: now, thresholds: this.model.thresholds, venues: [] }
      : this.model.evaluate(now)
    for (const c of this.conns) c.watchdog(now)
    this.pumpHistory()
    if (!hidden) this.opts.onFrame(frame)
    this.timer = setTimeout(() => this.loop(), hidden ? HIDDEN_EVALUATE_MS : EVALUATE_MS)
  }

  private calibrate(now: number): void {
    if (this.calibrationDeadline == null) return
    const d = this.model.calibrationDepth()
    const complete = d.total > 0 && d.ready === d.total
    if (!(complete || d.total === 0 || now >= this.calibrationDeadline)) return
    this.calibrating = false
    this.calibrationDeadline = null
    this.calibrated = d.ready > 0 ? calibratedThreshold(d.depth) : null
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
      return now >= this.historyRetryAt ? { kind: 'initial', from: now - HISTORY_SPAN_MS, to: now, minLife: false } : null
    }
    if (now - this.historyPulled >= HISTORY_EVERY_MS) {
      return { kind: 'increment', from: Math.max(oldest, Math.min(this.historyCursor, now) - HISTORY_OVERLAP_MS), to: now, minLife: false }
    }
    // 往前一页：抽屉滚到底（全要），或图往左拖出了已取的范围（只要活过 5 分钟的，图上短命的看不出来）。
    const scrolled = this.visibleFrom != null && this.visibleFrom < this.historyFrom
    if ((this.olderWanted || scrolled) && now >= this.backfillRetryAt) {
      const floor = Math.max(this.historyTrackedSince ?? oldest, oldest)
      if (this.historyFrom <= floor) { this.olderWanted = false; return null }
      return { kind: 'backfill', from: Math.max(floor, this.historyFrom - HISTORY_SPAN_MS), to: this.historyFrom, minLife: !this.olderWanted }
    }
    return null
  }

  private pumpHistory(): void {
    if (this.stopped || this.calibrating || this.historyBusy) return
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
